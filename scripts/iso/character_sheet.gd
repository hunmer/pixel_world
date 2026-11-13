## iso/character_sheet.gd — 8 职业水平角色精灵图（assets/ui/gen/split/sheets/）加载与朝向/姿态解析。
##
## 素材规格：每职业一张 2304×288，单行 8 格 × 288×288，帧序固定
## front, side, back, attack, hurt, run, downed, potion；锚点 bottom-center
## （内容底边统一 y=284）。每姿态只有单帧：三视图只用于移动/静止朝向，
## 严禁当作循环步行动画逐张轮播；攻击/受击/奔跑/倒地是单帧姿态演出。
## 原图朝向（8 职业一致，接触表目检）：front/back/potion 朝 viewer 不镜像；
## side/attack/hurt 朝左（flip_h = 屏幕水平位移 > 0）；
## run/downed 朝右（flip_h = 屏幕水平位移 < 0）。
class_name CharacterSheet
extends RefCounted

const CELL_SIZE := 288
const FRAME_FRONT := 0
const FRAME_SIDE := 1
const FRAME_BACK := 2
const FRAME_ATTACK := 3
const FRAME_HURT := 4
const FRAME_RUN := 5
const FRAME_DOWNED := 6
const FRAME_POTION := 7
const FRAME_ORDER: Array[StringName] = [
	&"front", &"side", &"back", &"attack", &"hurt", &"run", &"downed", &"potion",
]

## 锚点 bottom-center：内容底边 y=284、格中心 y=144 → 脚底在格中心下方 140px。
const FEET_FROM_CENTER_PX := 140.0
## 站姿内容高 218~239px（manifest body_scale 实测）；统一以 224px ≈ 1 世界单位，
## 与旧 48px 立绘（pixel_size = 1/tex_h ≈ 1.0 单位高）保持一致。
const REFERENCE_HEIGHT_PX := 224.0

const POSE_IDLE := &"idle"
const POSE_RUN := &"run"
const POSE_ATTACK := &"attack"
const POSE_HURT := &"hurt"
const POSE_DOWNED := &"downed"

const _SHEET_DIR := "res://assets/ui/gen/split/sheets"
const MANIFEST_PATH := "res://assets/ui/gen/split/manifest.json"

static var _texture_cache: Dictionary = {}  # class_id -> Texture2D（含 null 负缓存）
static var _frame_cache: Dictionary = {}  # "class:frame" -> AtlasTexture
static var _manifest: Variant = null  # 惰性加载并缓存


static func sheet_path(class_id: StringName) -> String:
	return "%s/%s_sheet.png" % [_SHEET_DIR, class_id]


static func sheet_exists(class_id: StringName) -> bool:
	return ResourceLoader.exists(sheet_path(class_id))


static func sheet_texture(class_id: StringName) -> Texture2D:
	if _texture_cache.has(class_id):
		return _texture_cache[class_id]
	var tex: Texture2D = null
	if sheet_exists(class_id):
		tex = load(sheet_path(class_id))
	_texture_cache[class_id] = tex
	return tex


static func frame_texture(class_id: StringName, frame: int) -> AtlasTexture:
	var key := "%s:%d" % [class_id, frame]
	if _frame_cache.has(key):
		return _frame_cache[key]
	var sheet := sheet_texture(class_id)
	if sheet == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(frame * CELL_SIZE, 0, CELL_SIZE, CELL_SIZE)
	atlas.filter_clip = true
	_frame_cache[key] = atlas
	return atlas


static func pixel_size() -> float:
	return 1.0 / REFERENCE_HEIGHT_PX


## 屏幕位移 → 朝向帧。等距约定（4 正交相机 yaw + 4 向网格移动的几何事实：
## 四个移动方向的屏幕位移恒为两条对角线，|dx|>|dy|，按最近屏幕主轴量化会恒 side）：
## 按位移符号把两条对角轴分开——
##   dx/dy 同号（朝向/远离相机的对角轴）：dy>0（朝向相机）→ front，否则 → back；
##   dx/dy 异号（横切对角轴）→ side，flip = dx>0（side 原图朝左）。
## 退化（对角世界朝向/未来 8 向移动）：dy≈0 → side；dx≈0 → front/back。
## 映射表（yaw=PI/4 运行时实测）：E(+x)=front、W(-x)=back、S(+z)=side 不翻、
## N(-z)=side flip；相机每转 90° 同一世界方向换屏侧，映射随屏幕位移自动跟随。
static func resolve_facing(screen_delta: Vector2) -> Dictionary:
	var dx := screen_delta.x
	var dy := screen_delta.y
	if absf(dy) <= 0.0001:
		return { &"frame": FRAME_SIDE, &"flip": dx > 0.0 }
	if absf(dx) <= 0.0001:
		return { &"frame": FRAME_FRONT if dy > 0.0 else FRAME_BACK, &"flip": false }
	if (dx > 0.0) == (dy > 0.0):
		# 同号：朝向/远离相机轴。dy>0 = 屏幕下方 = 朝向相机。
		return { &"frame": FRAME_FRONT if dy > 0.0 else FRAME_BACK, &"flip": false }
	# 异号：横切轴，side 按屏幕水平方向镜像。
	return { &"frame": FRAME_SIDE, &"flip": dx > 0.0 }


## 姿态+屏幕位移 → 帧与镜像（调用方统一入口）。
## run 只有朝右单帧：当移动落在朝向/远离相机轴（front/back）时不得用 side  run
## 帧覆盖三视图，改用 front/back 帧；横切轴才用 run 帧+镜像。
static func resolve_pose(pose: StringName, screen_delta: Vector2) -> Dictionary:
	if pose == POSE_IDLE:
		return resolve_facing(screen_delta)
	if pose == POSE_RUN:
		var resolved := resolve_facing(screen_delta)
		var frame: int = resolved[&"frame"]
		if frame == FRAME_FRONT or frame == FRAME_BACK:
			return { &"frame": frame, &"flip": false }
		return { &"frame": FRAME_RUN, &"flip": pose_flip(POSE_RUN, screen_delta.x) }
	return { &"frame": pose_frame(pose), &"flip": pose_flip(pose, screen_delta.x) }


## 姿态 → 固定帧；idle 由朝向解析（resolve_facing），不在此列。
static func pose_frame(pose: StringName) -> int:
	match pose:
		POSE_RUN:
			return FRAME_RUN
		POSE_ATTACK:
			return FRAME_ATTACK
		POSE_HURT:
			return FRAME_HURT
		POSE_DOWNED:
			return FRAME_DOWNED
	return FRAME_FRONT


## 该姿态是否按屏幕水平位移镜像：side/attack/hurt 原图朝左，dx>0 时翻转；
## run/downed 原图朝右，dx<0 时翻转；front/back/potion 恒不翻转。
static func pose_flip(pose: StringName, screen_dx: float) -> bool:
	match pose:
		POSE_RUN, POSE_DOWNED:
			return screen_dx < 0.0
		POSE_ATTACK, POSE_HURT:
			return screen_dx > 0.0
	return false


## 世界朝向在相机屏幕空间的投影位移；相机旋转后同一世界朝向可能换帧/镜像。
static func facing_screen_delta(camera: Camera3D, origin: Vector3, dir_world: Vector3) -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return Vector2.ZERO
	var from := camera.unproject_position(origin)
	var to := camera.unproject_position(origin + dir_world)
	if camera.is_position_behind(origin + dir_world):
		# 相机正后方时 unproject 返回镜像坐标，退化为只用水平分量符号。
		return Vector2(to.x - from.x, 0.0)
	return to - from


## manifest 原样（Dictionary）；缺失时返回空 Dictionary。仅供测试/工具校验。
static func manifest() -> Dictionary:
	if _manifest != null:
		return _manifest
	_manifest = {}
	if not ResourceLoader.exists(MANIFEST_PATH):
		return _manifest
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return _manifest
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_manifest = parsed
	return _manifest
