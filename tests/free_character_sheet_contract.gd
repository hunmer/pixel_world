## tests/free_character_sheet_contract.gd — 免费角色包原字节、有效帧、朝向与动画状态契约
extends SceneTree

const Sheet = preload("res://scripts/characters/free_character_sheet.gd")
const Animator = preload("res://scripts/characters/free_character_animator.gd")

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _frame_has_alpha(image: Image, row: int, frame: int) -> bool:
	for y in range(row * 64, (row + 1) * 64):
		for x in range(frame * 64, (frame + 1) * 64):
			if image.get_pixel(x, y).a > 0.0:
				return true
	return false


func _run() -> void:
	var manifest := Sheet.manifest()
	_expect(not manifest.is_empty(), "free character manifest parses")
	_expect(Sheet.character_ids().size() == 20, "exactly 20 stable character ids")
	_expect(Sheet.character_ids().front() == &"002", "first stable id is 002")
	_expect(Sheet.character_ids().back() == &"021", "last stable id is 021")
	_expect(Sheet.foot_offset() == Vector2(0, 31), "bottom-center anchor maps to positive Sprite3D local Y")
	_expect(is_equal_approx(Sheet.pixel_size(), 1.0 / 36.0), "world pixel size is independent from CharacterSheet")
	_expect(FileAccess.file_exists(Sheet.PACK_PATH + "upstream_example/.gdignore"),
		"upstream example scripts and nested project are ignored")
	_expect(Sheet.valid_frames(4) == [0, 1, 2], "row 4 excludes three blank tail frames")
	_expect(Sheet.valid_frames(6) == [0, 1, 2], "row 6 excludes three blank tail frames")
	_expect(Sheet.valid_frames(7) == [0, 1, 2, 3, 4, 5], "run row keeps all six frames")
	_expect(Sheet.frame_texture(&"002", 4, 3) == null, "blank tail frame cannot produce an atlas")

	for entry_value: Variant in manifest.get("characters", []):
		var entry: Dictionary = entry_value
		var character_id := StringName(entry.get("id", ""))
		var path := Sheet.sheet_path(character_id)
		_expect(FileAccess.get_sha256(path) == String(entry.get("sha256", "")),
			"%s preserves migrated source bytes" % character_id)
		var texture := Sheet.sheet_texture(character_id)
		_expect(texture != null, "%s sheet loads" % character_id)
		if texture == null:
			continue
		_expect(texture.get_width() == 384 and texture.get_height() == 832,
			"%s sheet dimensions are 384x832" % character_id)
		var image := texture.get_image()
		_expect(image != null and not image.is_empty(), "%s source image decodes" % character_id)
		if image == null or image.is_empty():
			continue
		for row_value: Variant in manifest.get("rows", []):
			var row_spec: Dictionary = row_value
			var row := int(row_spec.get("row", -1))
			for frame in range(6):
				var expected := Sheet.valid_frames(row).has(frame)
				_expect(_frame_has_alpha(image, row, frame) == expected,
					"%s row %d frame %d alpha matches valid_frames" % [character_id, row, frame])

	var first := Sheet.frame_texture(&"002", 7, 0)
	var same := Sheet.frame_texture(&"002", 7, 0)
	var other := Sheet.frame_texture(&"003", 7, 0)
	_expect(first != null and first == same, "same character/frame reuses AtlasTexture cache")
	_expect(first != other and first.atlas != other.atlas, "character switches retain independent sheet/cache entries")
	_expect(first.region == Rect2(0, 448, 64, 64), "run down frame zero region")
	_expect(first.filter_clip, "atlas filtering cannot bleed into adjacent frame")

	var down := Sheet.resolve_direction(Vector2(10, 4))
	var up := Sheet.resolve_direction(Vector2(-10, -4))
	var right := Sheet.resolve_direction(Vector2(10, -4))
	var left := Sheet.resolve_direction(Vector2(-10, 4))
	_expect(down.get(&"direction") == &"down" and int(down.get("row", -1)) == 7,
		"toward-camera diagonal uses run down row")
	_expect(up.get(&"direction") == &"up" and int(up.get("row", -1)) == 9,
		"away-camera diagonal uses run up row")
	_expect(right.get(&"direction") == &"right" and bool(right.get("flip_h", false)),
		"screen-right uses left row mirrored")
	_expect(left.get(&"direction") == &"left" and not bool(left.get("flip_h", true)),
		"screen-left uses left row unmirrored")
	_expect(Sheet.resolve_direction(Vector2(0, -1)).get(&"direction") == &"up", "screen up resolves up")
	_expect(Sheet.resolve_direction(Vector2(1, 0)).get(&"direction") == &"right", "screen right resolves right")

	var animator := Animator.new(&"002")
	animator.set_locomotion(true, Vector2(10, 4))
	_expect(animator.mode == &"run" and animator.current_row() == 7 and animator.frame_index == 0,
		"run starts at down row frame zero")
	animator.advance(0.125)
	_expect(animator.frame_index == 1, "run advances at 8 fps")
	animator.advance(0.625)
	_expect(animator.frame_index == 0, "run loops after six frames")
	animator.set_locomotion(false, Vector2.ZERO)
	_expect(animator.mode == &"idle" and animator.frame_index == 0 and animator.direction == &"down",
		"idle resets visible frame but preserves facing")
	animator.set_locomotion(true, Vector2(10, -4))
	_expect(animator.direction == &"right" and animator.current_flip_h(), "run right mirrors left sheet")
	animator.set_locomotion(false, Vector2.ZERO)
	_expect(animator.direction == &"right", "idle keeps last screen-right facing")

	_expect(animator.start_preview(&"preview_04"), "non-moving numbered preview starts")
	_expect(animator.current_row() == 4 and animator.mode == &"preview", "preview uses source row four")
	animator.advance(0.25)
	_expect(animator.frame_index == 2, "three-frame preview reaches final valid frame")
	_expect(not animator.start_preview(&"preview_00"), "preview rejects re-entry/restart while active")
	animator.advance(0.125)
	_expect(animator.mode == &"idle" and animator.preview_id == &"" and animator.frame_index == 0,
		"one-shot preview ends at idle instead of looping blank frames")
	_expect(not animator.start_preview(&"run"), "run cannot be triggered as one-shot preview")
	_expect(animator.set_character(&"003"), "character switch accepts next stable id")
	_expect(animator.character_id == &"003" and animator.mode == &"idle", "switch resets animation safely")
	_expect(not animator.set_character(&"999"), "unknown character is rejected")
	var external_manifest := Sheet.manifest()
	external_manifest["characters"] = []
	_expect(Sheet.character_ids().size() == 20, "callers cannot mutate shared manifest cache")

	if failures.is_empty():
		print("FREE_CHARACTER_SHEET_CONTRACT_OK checks=%d" % checks)
	else:
		push_error("FREE_CHARACTER_SHEET_CONTRACT_FAILED checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
