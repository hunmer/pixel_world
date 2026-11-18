## iso/unit_status_badges.gd — 单位头顶状态图标行（独立 Node3D 模块）
##
## UnitSprite3D 的子模块，世界 B1 与独立 B2 共用（挂在 UnitSprite3D 下即跟随）：
##   - 按 unit.buffs 数组顺序水平排列独立图标（StatusIcons 稳定 ID → 纹理），
##     每个图标右下角 Label3D 显示 buff.turns 剩余回合；
##   - 图标/数字各自 billboard；行内水平排列与数字右下偏移全部走
##     Sprite3D.offset / Label3D.offset（屏幕像素）：节点 position 恒为
##     Vector3.ZERO，相机旋转到任意正交角屏幕排列不变（世界轴布局在
##     90° 角会把行排成深度方向、数字脱离右下角）；
##   - refresh() 带签名检查：状态未变化不重建节点、不重载纹理（纹理另有
##     StatusIcons 静态缓存），update_state 状态变化时才刷新；
##   - 素材缺失（get_texture → null）时仅隐藏该槽位，不以技能图等伪装；
##   - 数字右下角对齐：Label3D offset 按位数补偿，右缘不随位数水平漂移；
##   - set_alpha() 供 UnitSprite3D 演出淡出链（_set_children_alpha/fade_alpha）
##     联动；clear() 供死亡/净化后清理，节点复用不残留。
##
## 锚点约定：本节点 position 由 UnitSprite3D 设置为状态行中心高度
## （anchor_y(head_y)）；行内槽位以本节点原点为中心水平展开。

class_name UnitStatusBadges
extends Node3D

## 图标边长（像素）：素材 native 规格 16~24px，取 20px 中值渲染为同尺寸。
const STATUS_ICON_SIZE_PX := 20.0
## 相邻图标间距（像素，行内空隙）。
const STATUS_ICON_GAP_PX := 3.0
## 状态行底边与「可见头顶」（UnitSprite3D._head_y）的间距（像素）。
const STATUS_ANCHOR_GAP_PX := 4.0
## 剩余回合数字：字号 12px、黑色描边（与 UnitSprite3D 头顶文本同风格）。
const STATUS_DIGIT_FONT_PX := 12
const STATUS_DIGIT_OUTLINE_PX := 3
## 12px 像素字体单数字宽（近似）：多位数字右对齐补偿用。
const STATUS_DIGIT_W_PX := 7.0
## 数字中心相对图标中心的偏移（像素，右下角内收）。
const STATUS_DIGIT_ANCHOR_PX := Vector2(6.0, 5.0)
## 像素 → 世界单位比例，与 UnitSprite3D 血条/头顶文本一致（32px = 1 单位）。
const PIXEL_SIZE := 1.0 / 32.0
## 深度：图标/数字 no_depth_test + render_priority 压过血条（1/2）防深度冲突。
const ICON_RENDER_PRIORITY := 5
const DIGIT_RENDER_PRIORITY := 6

var _sprites: Array[Sprite3D] = []
var _labels: Array[Label3D] = []
var _signature := ""
var _alpha := 1.0


## 当前可见槽位数（含素材缺失但状态有效的槽位）。
func slot_count() -> int:
	return _sprites.size()


## 状态行中心相对头顶锚点（head_y = UnitSprite3D._head_y）的世界高度。
func anchor_y(head_y: float) -> float:
	return head_y + (STATUS_ANCHOR_GAP_PX + STATUS_ICON_SIZE_PX * 0.5) * PIXEL_SIZE


## 状态行顶部的世界高度（hover 指针等上方元素避让用）；
## 无状态时不占高，返回 head_y 本身。
func top_world_y(head_y: float) -> float:
	if _sprites.is_empty():
		return head_y
	return head_y + (STATUS_ANCHOR_GAP_PX + STATUS_ICON_SIZE_PX) * PIXEL_SIZE


## 按 buffs 数组刷新图标行：有效项（icon_id_for_buff 非 &""）按顺序一一对应。
## 签名（icon:turns 列表）未变化时直接返回，不触碰任何节点。
func refresh(buffs: Array) -> void:
	var entries: Array = []
	for b in buffs:
		var icon_id := StatusIcons.icon_id_for_buff(b)
		if icon_id == &"":
			continue
		entries.append({ icon = icon_id, turns = maxi(1, int(b.get(&"turns", 0))) })
	var sig := ""
	for e in entries:
		sig += "%s:%d|" % [String(e[&"icon"]), int(e[&"turns"])]
	if sig == _signature:
		return
	_signature = sig
	_resize_slots(entries.size())
	# 屏幕像素偏移（offset）以本口径定义：32px = 1 世界单位。
	var step_px := STATUS_ICON_SIZE_PX + STATUS_ICON_GAP_PX
	for i in entries.size():
		var e: Dictionary = entries[i]
		var center_px := (float(i) - float(entries.size() - 1) * 0.5) * step_px
		var sprite := _sprites[i]
		var label := _labels[i]
		var tex: Texture2D = StatusIcons.get_texture(e[&"icon"])
		sprite.texture = tex
		# 素材缺失时隐藏整个槽位（图标无锚点，数字悬空无意义），不报错不伪装。
		var slot_visible := tex != null
		sprite.visible = slot_visible
		label.visible = slot_visible
		# 恒定 20px 显示：native 16~24px 素材或未来更大切片（如 64px）都按
		# 纹理实际宽度归一到同一屏幕尺寸。
		var tex_w := float(tex.get_width()) if tex != null else STATUS_ICON_SIZE_PX
		sprite.pixel_size = STATUS_ICON_SIZE_PX / (tex_w * 32.0)
		# 行内水平位置走屏幕空间：Sprite3D.offset 单位是纹理像素，
		# 世界位移 = offset * pixel_size，故除以显示比例换算（tex_w / 20px）。
		sprite.offset = Vector2(center_px * tex_w / STATUS_ICON_SIZE_PX, 0.0)
		var digits := str(int(e[&"turns"]))
		label.text = digits
		# Label3D.offset 的 y 正向朝上，右下角使用负值。
		# 位数增加时中心左移半个字宽，右缘恒定不漂移。
		label.offset = Vector2(
			center_px + STATUS_DIGIT_ANCHOR_PX.x - (digits.length() - 1) * STATUS_DIGIT_W_PX * 0.5,
			-STATUS_DIGIT_ANCHOR_PX.y)
		label.modulate.a = _alpha
		label.outline_modulate.a = _alpha
		sprite.modulate.a = _alpha


## 清空全部槽位（死亡/无状态）；节点池保留待复用。
func clear() -> void:
	_signature = ""
	_resize_slots(0)


## 演出淡出联动：整行图标与数字统一 alpha（新建槽位沿用当前值）。
func set_alpha(a: float) -> void:
	_alpha = a
	for sprite in _sprites:
		sprite.modulate.a = a
	for label in _labels:
		label.modulate.a = a
		label.outline_modulate.a = a


func _resize_slots(count: int) -> void:
	while _sprites.size() > count:
		var s: Sprite3D = _sprites.pop_back()
		var l: Label3D = _labels.pop_back()
		s.queue_free()
		l.queue_free()
	while _sprites.size() < count:
		var sprite := Sprite3D.new()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		# ALPHA_CUT_DISABLED（默认）：modulate alpha 半透明淡出（演出死亡淡出）
		# 平滑渐隐；DISCARD 会裁掉半透明像素导致淡出"突然消失"。
		# 透明排序交给 no_depth_test + render_priority。
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sprite.shaded = false
		sprite.no_depth_test = true
		sprite.render_priority = ICON_RENDER_PRIORITY
		sprite.pixel_size = PIXEL_SIZE
		sprite.modulate.a = _alpha
		add_child(sprite)
		_sprites.append(sprite)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.render_priority = DIGIT_RENDER_PRIORITY
		label.shaded = false
		label.position = Vector3.ZERO
		label.pixel_size = PIXEL_SIZE
		label.font_size = STATUS_DIGIT_FONT_PX
		label.outline_size = STATUS_DIGIT_OUTLINE_PX
		label.outline_modulate = Color.BLACK
		label.modulate = Color.WHITE
		label.modulate.a = _alpha
		add_child(label)
		_labels.append(label)
