## iso/iso_coords.gd — 2D 等距坐标变换（从 phaserjs 的 3D 版重写）
##
## pixel_world 的等距世界是 2D Node2D（Camera2D + ColumnBatch），不是 3D。
## 本文件提供 cell ↔ screen 的纯函数变换，常量与 main.gd 的 TILE_W/H/LEVEL_H 一致。
##
## 历史兼容：phaserjs 原 API 是 to_world(x,y) -> Vector3 / to_cell(world) -> Vector2i。
## 为了让逻辑层（turn_director / battle.gd）改动最小，这里保留同名 API 但语义改为：
##   - to_world(x, y) 返回 Vector3，其中 .xy 是屏幕坐标（单位=像素），.z=0
##     —— 这样原代码里 global_position(Vector3) / tween_property(global_position, Vector3)
##        仍能编译通过（Node2D.global_position 接受 Vector3 时会自动取 xy）。
##   - to_screen(x, y) 返回 Vector2，新代码推荐用这个。
##   - to_cell(screen_pos) 由屏幕坐标反算 cell。
##
## 单位：1 cell 的菱形 = TILE_W(32) × TILE_H(16) 像素；侧壁层高 LEVEL_H(10) 像素。

class_name IsoCoords
extends RefCounted

## 等距菱形宽（像素）。与 main.gd.TILE_W 保持一致。
const TILE_W := 32.0
## 等距菱形高（像素）。与 main.gd.TILE_H 保持一致。
const TILE_H := 16.0
## 方块侧壁一层的高度（像素）。与 main.gd.LEVEL_H 保持一致。
const LEVEL_H := 10.0

## 兼容旧 API（phaserjs 里 CELL=1.0 世界单位）；这里保留常量名避免引用处报错。
const CELL := 1.0


## cell (x,y) → 屏幕坐标（菱形顶面中心，像素）。推荐入口。
static func to_screen(x: float, y: float, level: float = 0.0) -> Vector2:
	return Vector2(
		(x - y) * TILE_W * 0.5,
		(x + y) * TILE_H * 0.5 - level * LEVEL_H,
	)


## 兼容旧 API：to_world(x, y) 返回 Vector3，.xy 是屏幕坐标，.z=0。
## 让原代码 tween_property(us, "global_position", Vector3(...)) 在 Node2D 上仍能工作
## （Node2D.global_position 是 Vector2，赋 Vector3 时 Godot 自动取 xy）。
static func to_world(x: float, y: float) -> Vector3:
	var s := to_screen(x, y)
	return Vector3(s.x, s.y, 0.0)


## 整数版（兼容旧 to_world(int,int) 调用点）。
static func to_worldi(x: int, y: int) -> Vector3:
	return to_world(float(x), float(y))


## 屏幕坐标 → cell（四舍五入）。
## 输入：相对 board（Node2D）的局部坐标或全局世界坐标（两者在 board 无平移时一致）。
static func to_cell(world: Vector2) -> Vector2i:
	# 反解：sx = (cx-cy)*W/2, sy = (cx+cy)*H/2
	# → (cx-cy) = sx/(W/2) = 2sx/W； (cx+cy) = sy/(H/2) = 2sy/H
	# → cx = ((2sx/W) + (2sy/H)) / 2 = sx/W + sy/H
	# → cy = ((2sy/H) - (2sx/W)) / 2 = sy/H - sx/W
	var hx := world.x / TILE_W
	var hy := world.y / TILE_H
	return Vector2i(roundi(hx + hy), roundi(hy - hx))


## Vector3 版重载（兼容旧 to_cell(Vector3) 调用点）。
static func to_cell_v3(world: Vector3) -> Vector2i:
	return to_cell(Vector2(world.x, world.y))


# ============================================================
# 以下旧 3D 相机相关 API 已废弃；保留空壳避免编译错误，但不应再被调用。
# （如调用方仍引用，会在运行时返回无效值或 NaN。）
# ============================================================

## 已废弃：3D 相机朝向。pixel_world 用 2D，不存在相机朝向。
static func iso_view_dir() -> Vector3:
	push_warning("IsoCoords.iso_view_dir() 已废弃（2D 项目无 3D 相机）")
	return Vector3.ZERO


## 已废弃：3D 正交相机配置。pixel_world 用 Camera2D.zoom。
static func setup_ortho_camera(_cam: Camera3D, _cell_count_max: int, _center_cell: Vector2i) -> void:
	push_warning("IsoCoords.setup_ortho_camera() 已废弃（2D 项目用 Camera2D）")


## 已废弃：屏幕 → 3D 水平面射线。pixel_world 用 to_cell(Vector2) 反投影。
static func screen_to_ground(_cam: Camera3D, _screen_pos: Vector2, _viewport_size: Vector2) -> Vector3:
	push_warning("IsoCoords.screen_to_ground() 已废弃，请用 to_cell(screen_pos)")
	# 返回一个让旧逻辑 NaN 检查命中的值，促使调用方走新分支
	return Vector3(NAN, NAN, NAN)
