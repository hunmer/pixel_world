extends SceneTree
## 无窗口接线检查：运行时加载主场景，避免独立 check-only 缺失 autoload。
const Loader = preload("res://scripts/core/battlefield_loader.gd")
const Grid = preload("res://scripts/systems/grid_system.gd")
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
func _run() -> void:
	var editor_scene: PackedScene = load("res://scenes/MapEditor.tscn")
	var battle_scene: PackedScene = load("res://scenes/Battle.tscn")
	_expect(editor_scene != null and battle_scene != null, "主场景加载失败")
	var result: Dictionary = Loader.load_battlefield("res://data/battlefields/building_demo.json")
	_expect(bool(result.get("ok", false)), "真实塔楼示例读取失败")
	if not failures.is_empty():
		_finish()
		return
	var chapter: Dictionary = result["chapter"]
	_expect(chapter.get("buildings", []).size() == 1, "示例应恰有一栋建筑")
	var harness := GDScript.new()
	harness.source_code = "extends \"res://scripts/scenes/battle.gd\"\nfunc _ready() -> void:\n\tpass\nfunc _exit_tree() -> void:\n\tpass\n"
	_expect(harness.reload() == OK, "战斗脚本编译失败")
	var battle = harness.new()
	battle.chapter = chapter
	battle.grid = Grid.new(chapter.width, chapter.height, chapter.map)
	battle.grid.apply_buildings(chapter.get("buildings", []), chapter.get("user_assets", {}))
	root.add_child(battle)
	battle._setup_b2_render()
	var visuals: Array = battle.renderer.building_visuals_snapshot()
	_expect(visuals.size() == 1, "B2 未注入建筑视觉")
	_expect(battle.grid.is_building_cell(4, 4), "B2 未加载建筑占用")
	var front: Dictionary = visuals[0]["visual"]
	var back: Dictionary = visuals[0]["back_visual"]
	_expect(front.get("back_mode", "") == "front_back" and not back.is_empty(), "真实背图未接入")
	_expect(not front.get("missing", true) and not back.get("missing", true), "真实前背图片读取失败")
	var adapter = load("res://scripts/assets/user_asset_visual_adapter.gd").new()
	var front_id: String = front["asset_id"]
	var back_id: String = back["asset_id"]
	var library_front: Dictionary = adapter.library_descriptor(front_id)
	var library_back: Dictionary = adapter.library_descriptor(back_id)
	_expect(library_front.get("render", {}).get("back_asset_id", "") == back_id, "素材库未关联背图")
	_expect(library_back.get("sha256", "") == "79ed6bfc47a40b0cadf542cb24f269fd9c5b5ced1c96c6f06419c0a778cb546c", "背图不是用户更正后的图片")
	_expect((front["texture"] as Texture2D).get_size() == (back["texture"] as Texture2D).get_size(), "前背图显示尺寸不一致")
	for quadrant in range(4):
		_expect(battle.renderer._camera_quadrant == quadrant, "B2 相机象限不同步")
		var chosen_id := ""
		for block in battle.renderer.cell_blocks_snapshot(Vector2i(4, 4)):
			if bool(block.get("building", false)):
				chosen_id = block.get("asset_id", "")
		_expect(chosen_id == (front_id if quadrant < 2 else back_id), "真实石塔四方向未正确切图")
		battle._rotate_camera(1)
	battle._reset_camera_rotation()
	_expect(battle.renderer._camera_quadrant == 0, "B2 相机复位未同步")
	battle.queue_free()
	await process_frame
	editor_scene = null
	battle_scene = null
	harness = null
	_finish()
func _finish() -> void:
	if failures.is_empty():
		print("BUILDING_SCENE_SMOKE_OK")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)
