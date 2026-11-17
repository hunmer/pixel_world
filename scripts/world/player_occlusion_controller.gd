## player_occlusion_controller.gd — 玩家植被遮挡：重建门控、billboard 相交收集、像素 alpha 精测。
##
## 从 main.gd 玩家遮挡簇整体迁出（结构性拆分，行为不变）。每帧行人状态
## （视觉位置/站立层/是否精灵图）由调用方传入；玩家、相机、地形为长生命周期引用，
## 在 configure() 一次注入。
class_name PlayerOcclusionController
extends RefCounted

const IsoProjection = preload("res://scripts/iso/iso_projection_3d.gd")

## 精灵图内容包围盒（像素）：脚底=节点原点；用于植物遮挡屏幕包围盒，
## 与贴图画布尺寸解耦（288 格含大量透明留白，直接量贴图会误淡化周围植物）。
const PLAYER_SHEET_CONTENT_SIZE := Vector2(224.0, 240.0)
## 植物锚点比人物更靠近镜头超过该深度余量才判定为遮挡（植物 billboard 有厚度）。
const PLAYER_PROP_OCCLUSION_DEPTH_MARGIN := 0.05
## 静止时遮挡集合的定期重算间隔（秒）：防御检测抖动后的卡死状态。
const PLAYER_OCCLUSION_REFRESH_INTERVAL := 0.5
## 贴图像素 alpha 命中阈值；低于它视为透明，不触发整格淡化。
const PROP_TEXTURE_ALPHA_HIT_THRESHOLD := 0.01
## 每个遮挡块保持固定的强透明度；不能按命中块总数继续拆分，否则高山会近乎消失。
const PLAYER_OCCLUSION_BLOCK_ALPHA := 0.20

var _screen_margin := Vector2(24.0, 12.0)
var _player: Sprite3D = null
var _cam: Camera3D = null
var _terrain: Node = null
var _dirty := true
var _refresh_elapsed := 0.0
var _last_visual_position := Vector2(1.0e20, 1.0e20)
var _last_yaw := 1.0e20
var _last_zoom := 1.0e20
var _last_stand_level := 1.0e20
var _occluder_cells := {}  ## cell -> 当前遮挡人物的植物格（调试面板查询）
var _fading_cells := {}  ## 包含正在恢复不透明度的格
var _prop_texture_image_cache := {}  ## prop 贴图 instance_id -> Image（alpha 精测用）


## 注入长生命周期引用与瓦片尺寸（遮挡命中边距按瓦片 0.75 格计算）。
func configure(player: Sprite3D, cam: Camera3D, terrain: Node, tile_w: float, tile_h: float) -> void:
	_player = player
	_cam = cam
	_terrain = terrain
	_screen_margin = Vector2(tile_w * 0.75, tile_h * 0.75)


## 流式生成/视角旋转/排序原点重置等事件后的强制重建标记。
func mark_dirty() -> void:
	_dirty = true


## 单格被释放（离开流式范围）时同步移出遮挡记录。
func on_cell_freed(cell: Vector2i) -> void:
	_occluder_cells.erase(cell)
	_fading_cells.erase(cell)
	_dirty = true


## 世界重生成时的全量清空。
func clear_recorded() -> void:
	_occluder_cells.clear()
	_fading_cells.clear()
	_dirty = true


## 调试面板查询：当前遮挡人物的植物格（按 y、x 升序）。
func get_occluder_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_value in _occluder_cells.keys():
		result.append(cell_value)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


## 每帧驱动：定期重算门控 + 依需重建 + 推进植物淡化动画。
func update(
	delta: float,
	viewport_height: float,
	visual_position: Vector2,
	stand_level: float,
	uses_sheet: bool
) -> void:
	# 静止时也周期性重算：相机/流式稳定期若发生过检测抖动（重建瞬间遮挡判定翻转），
	# 靠定期 rebuild 自愈，避免"已记录遮挡但淡化状态被恢复"的卡死局面。
	_refresh_elapsed += delta
	if _refresh_elapsed >= PLAYER_OCCLUSION_REFRESH_INTERVAL:
		_refresh_elapsed = 0.0
		_dirty = true
	if _needs_rebuild(visual_position, stand_level):
		_rebuild(viewport_height, visual_position, stand_level, uses_sheet)
	if is_instance_valid(_terrain):
		_terrain.advance_prop_fades(delta)
		_fading_cells = {}
		for cell_value in _terrain.get_active_prop_fade_cells():
			_fading_cells[cell_value] = true


func _needs_rebuild(visual_position: Vector2, stand_level: float) -> bool:
	var moved := (
		not _last_visual_position.is_equal_approx(visual_position)
		or not is_equal_approx(_last_stand_level, stand_level)
	)
	if not moved and is_instance_valid(_cam):
		# 相机绕焦点旋转时人物可能停在屏幕同一位置，但其他物体的投影全部移动，
		# 所以门控必须包含视角与缩放。
		moved = (
			not is_equal_approx(_last_yaw, _cam.yaw_radians)
			or not is_equal_approx(_last_zoom, _cam.zoom)
		)
	return _dirty or moved


## 收集真正挡住人物的植物格：锚点必须位于镜头与人物之间（更近），
## billboard 投影与人物包围盒相交，且贴图像素在相交区内确实有 alpha。
func _collect_occluders(viewport_height: float, uses_sheet: bool) -> Dictionary:
	var result := {}
	if (
		_player == null
		or _player.texture == null
		or not is_instance_valid(_cam)
		or not is_instance_valid(_terrain)
	):
		return result
	var px_per_world := viewport_height / maxf(_cam.size, 0.0001)
	# 精灵图画布含大量透明留白，遮挡包围盒按内容尺寸计算，避免误淡化周围植物。
	var sprite_size := (
		PLAYER_SHEET_CONTENT_SIZE * _player.pixel_size
		if uses_sheet
		else _player.texture.get_size() * _player.pixel_size
	)
	var center_world := _player.global_position + Vector3.UP * (sprite_size.y * 0.5)
	var center_screen := _cam.unproject_position(center_world)
	var core := Rect2(
		center_screen - sprite_size * 0.5 * px_per_world,
		sprite_size * px_per_world
	).grow_individual(
		_screen_margin.x,
		_screen_margin.y,
		_screen_margin.x,
		_screen_margin.y
	)
	var camera_back := _cam.global_transform.basis.z
	var player_depth := camera_back.dot(center_world)
	for cell_value in _terrain.get_prop_cells():
		var cell: Vector2i = cell_value
		for block_value in _terrain.get_prop_block_occlusion_data(cell):
			var block: Dictionary = block_value
			# camera_back（镜头 +Z）指向观察者：点积越小越远离镜头。
			# 锚点比人物更远离镜头 → 不可能遮挡（深度测试已保证它画在人物后面）。
			var depth_point: Vector3 = block["center"] if bool(block.get("building", false)) else block["anchor"]
			if camera_back.dot(depth_point) < player_depth - PLAYER_PROP_OCCLUSION_DEPTH_MARGIN:
				continue
			var block_half := (block["size_px"] as Vector2) * float(block.get("display_scale", 1.0)) / IsoProjection.TILE_PIXELS * 0.5 * px_per_world
			var block_rect := Rect2(
				_cam.unproject_position(block["center"]) - block_half,
				block_half * 2.0
			)
			if not block_rect.intersects(core):
				continue
			if _block_covers_player(block, block_rect, core):
				result[cell] = true
				break
	return result


func _block_covers_player(block: Dictionary, block_rect: Rect2, core: Rect2) -> bool:
	var overlap := block_rect.intersection(core)
	if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
		return false
	var image := _texture_image(block["texture"])
	if image == null or image.is_empty():
		return true
	var origin: Vector2 = block.get("origin_px", Vector2.ZERO)
	var size_px: Vector2 = block["size_px"]
	var max_x := mini(image.get_width() - 1, maxi(0, ceili(
		(overlap.end.x - block_rect.position.x) / block_rect.size.x * size_px.x + origin.x
	)))
	var max_y := mini(image.get_height() - 1, maxi(0, ceili(
		(overlap.end.y - block_rect.position.y) / block_rect.size.y * size_px.y + origin.y
	)))
	for pixel_y in range(maxi(0, floori(
		(overlap.position.y - block_rect.position.y) / block_rect.size.y * size_px.y + origin.y
	)), max_y + 1):
		for pixel_x in range(maxi(0, floori(
			(overlap.position.x - block_rect.position.x) / block_rect.size.x * size_px.x + origin.x
		)), max_x + 1):
			if image.get_pixel(pixel_x, pixel_y).a > PROP_TEXTURE_ALPHA_HIT_THRESHOLD:
				return true
	return false


func _texture_image(texture: Texture2D) -> Image:
	var key := texture.get_instance_id()
	if not _prop_texture_image_cache.has(key):
		_prop_texture_image_cache[key] = texture.get_image()
	return _prop_texture_image_cache[key]


func _rebuild(
	viewport_height: float,
	visual_position: Vector2,
	stand_level: float,
	uses_sheet: bool
) -> void:
	_dirty = false
	_last_visual_position = visual_position
	_last_stand_level = stand_level
	if is_instance_valid(_cam):
		_last_yaw = _cam.yaw_radians
		_last_zoom = _cam.zoom
	var occluders := _collect_occluders(viewport_height, uses_sheet)
	if is_instance_valid(_terrain):
		for cell_value in _occluder_cells.keys():
			if not occluders.has(cell_value):
				_terrain.set_prop_fade_target(cell_value, 1.0)
		for cell_value in occluders.keys():
			# 幂等重设：chunk 重建可能已清掉该格的淡化状态，重设目标可让
			# set_prop_fade_target 重新建代理（仅靠集合 diff 无法发现这种状态丢失）。
			_terrain.set_prop_fade_target(cell_value, PLAYER_OCCLUSION_BLOCK_ALPHA)
	_occluder_cells = occluders
