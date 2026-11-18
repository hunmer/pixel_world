## free_character_sheet.gd — 免费角色包的 64px 图集裁剪、朝向解析与独立缓存
class_name FreeCharacterSheet
extends RefCounted

const PACK_PATH := "res://assets/characters/free_character_pack/"
const MANIFEST_PATH := PACK_PATH + "manifest.json"
const FRAME_WIDTH := 64
const FRAME_HEIGHT := 64
const RUN_DOWN_ROW := 7
const RUN_LEFT_ROW := 8
const RUN_UP_ROW := 9

static var _manifest_cache: Dictionary = {}
static var _sheet_cache: Dictionary = {}
static var _frame_cache: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest_cache.is_empty() and FileAccess.file_exists(MANIFEST_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			_manifest_cache = parsed as Dictionary
	return _manifest_cache.duplicate(true)


static func _data() -> Dictionary:
	manifest()
	return _manifest_cache


static func character_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for value: Variant in _data().get("characters", []):
		var entry: Dictionary = value
		ids.append(StringName(entry.get("id", "")))
	return ids


static func character_entry(character_id: StringName) -> Dictionary:
	for value: Variant in _data().get("characters", []):
		var entry: Dictionary = value
		if StringName(entry.get("id", "")) == character_id:
			return entry
	return {}


static func sheet_path(character_id: StringName) -> String:
	var entry := character_entry(character_id)
	if entry.is_empty():
		return ""
	return PACK_PATH + String(entry.get("file", ""))


static func sheet_exists(character_id: StringName) -> bool:
	var path := sheet_path(character_id)
	return not path.is_empty() and ResourceLoader.exists(path)


static func sheet_texture(character_id: StringName) -> Texture2D:
	var key := String(character_id)
	if _sheet_cache.has(key):
		return _sheet_cache[key] as Texture2D
	var path := sheet_path(character_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture != null:
		_sheet_cache[key] = texture
	return texture


static func row_spec(row: int) -> Dictionary:
	for value: Variant in _data().get("rows", []):
		var spec: Dictionary = value
		if int(spec.get("row", -1)) == row:
			return spec
	return {}


static func animation_spec(animation_id: StringName) -> Dictionary:
	for value: Variant in _data().get("rows", []):
		var spec: Dictionary = value
		if StringName(spec.get("id", "")) == animation_id:
			return spec
	return {}


static func preview_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for value: Variant in _data().get("preview_order", []):
		ids.append(StringName(value))
	return ids


static func valid_frames(row: int) -> Array[int]:
	var frames: Array[int] = []
	for value: Variant in row_spec(row).get("valid_frames", []):
		frames.append(int(value))
	return frames


static func frame_region(row: int, frame: int) -> Rect2:
	return Rect2(frame * FRAME_WIDTH, row * FRAME_HEIGHT, FRAME_WIDTH, FRAME_HEIGHT)


static func frame_texture(
	character_id: StringName,
	row: int,
	frame: int
) -> AtlasTexture:
	if not valid_frames(row).has(frame):
		return null
	var key := "%s:%d:%d" % [character_id, row, frame]
	if _frame_cache.has(key):
		return _frame_cache[key] as AtlasTexture
	var sheet := sheet_texture(character_id)
	if sheet == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = sheet
	texture.region = frame_region(row, frame)
	texture.filter_clip = true
	_frame_cache[key] = texture
	return texture


static func direction_spec(direction: StringName) -> Dictionary:
	var directions: Dictionary = _data().get("directions", {})
	return directions.get(String(direction), {}) as Dictionary


static func resolve_direction(screen_delta: Vector2) -> Dictionary:
	var direction := &"down"
	if absf(screen_delta.x) < 0.001:
		if screen_delta.y < 0.0:
			direction = &"up"
	elif absf(screen_delta.y) < 0.001:
		direction = &"right" if screen_delta.x > 0.0 else &"left"
	elif signf(screen_delta.x) == signf(screen_delta.y):
		direction = &"down" if screen_delta.x > 0.0 else &"up"
	else:
		direction = &"right" if screen_delta.x > 0.0 else &"left"
	var resolved := direction_spec(direction).duplicate()
	resolved[&"direction"] = direction
	return resolved


static func facing_screen_delta(
	camera: Camera3D,
	world_position: Vector3,
	facing: Vector3
) -> Vector2:
	var origin := camera.unproject_position(world_position)
	return camera.unproject_position(world_position + facing) - origin


static func pixel_size() -> float:
	var frame: Dictionary = _data().get("frame", {})
	return float(frame.get("pixel_size", 1.0 / 36.0))


## Sprite3D 默认 centered=true 且局部 Y 向上；正 Y 偏移才能把 bottom-center 锚点落到脚底。
static func foot_offset() -> Vector2:
	var frame: Dictionary = _data().get("frame", {})
	var anchor: Array = frame.get("foot_anchor_px", [32, 63])
	return Vector2(
		float(anchor[0]) - float(frame.get("width", FRAME_WIDTH)) * 0.5,
		float(anchor[1]) - float(frame.get("height", FRAME_HEIGHT)) * 0.5
	)
