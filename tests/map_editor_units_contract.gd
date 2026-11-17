## map_editor_units_contract.gd — 编辑器角色与战场精灵、顶面高度及粘贴预览契约。
extends SceneTree

const CanvasScript = preload("res://scripts/editor/editor_canvas.gd")
const DocScript = preload("res://scripts/editor/battlefield_doc.gd")
const ClipboardScript = preload("res://scripts/editor/region_clipboard.gd")
const ProjectionScript = preload("res://scripts/iso/iso_projection_3d.gd")
const CLASSES: Array[String] = [
	"swordsman", "archer", "knight", "mage", "priest", "lancer", "assassin", "berserker",
]
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _check_units(canvas: EditorCanvas, document: Dictionary) -> void:
	_expect(canvas._unit_markers.size() == document.units.size(), "角色数量与显示文档一致")
	for index in range(canvas._unit_markers.size()):
		var marker: UnitSprite3D = canvas._unit_markers[index]
		var placed: Dictionary = document.units[index]
		var cell := Vector2i(int(placed.x), int(placed.y))
		_expect(marker.get_parent() == canvas._board, "角色进入地形同一 3D 场景")
		_expect(marker.unit.classId == StringName(placed["class"]), "使用文档职业")
		_expect(marker.portrait != null and marker.portrait.texture is AtlasTexture,
			"职业使用战场 CharacterSheet 精灵")
		_expect(marker.global_position.is_equal_approx(ProjectionScript.grid_to_world(
			cell, float(canvas._renderer.visual_top_level(cell.x, cell.y)))), "脚底随顶面高度对齐")
		_expect(not marker._hp_bar.visible and not marker._hp_bg.visible, "编辑器隐藏战斗血条")


func _run() -> void:
	var canvas: EditorCanvas = CanvasScript.new()
	root.add_child(canvas)
	var document: Dictionary = DocScript.create_empty(8, 4)
	for index in range(CLASSES.size()):
		document.units.append({"class": CLASSES[index], "x": index, "y": 0,
			"faction": "player" if index % 2 == 0 else "enemy", "level": index + 1})
		DocScript.set_cell_z(document, Vector2i(index, 0), index)
	canvas.model = document
	await process_frame
	_check_units(canvas, document)
	DocScript.set_cell_z(document, Vector2i(0, 0), 10)
	canvas._refresh_cell(Vector2i(0, 0))
	_check_units(canvas, document)
	var payload: Dictionary = ClipboardScript.extract(document, Vector2i.ZERO, Vector2i(1, 0))
	canvas.set_placement_preview(payload, Vector2i(0, 2))
	_expect(canvas._placement_model.units.size() == document.units.size() + 2,
		"粘贴预览新增两个角色")
	_check_units(canvas, canvas._placement_model)
	_expect(document.units.size() == CLASSES.size(), "预览不修改权威角色数据")
	canvas.clear_placement_preview()
	_check_units(canvas, document)
	document.units.clear()
	canvas.model = document
	await process_frame
	_expect(canvas._unit_markers.is_empty(), "删除或撤销放置后无角色残留")
	canvas.queue_free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("MAP_EDITOR_UNITS_CONTRACT_OK")
	quit(0 if failures.is_empty() else 1)
