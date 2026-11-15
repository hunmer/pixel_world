## map_editor_block_palette.gd — 前景/背景方块槽与最近吸取栏的展示逻辑
##
## 方块槽标签/刷新、最近吸取的去重置顶（上限 8 条）、缩略图解析（内置地形顶面
## 或素材视觉贴图）与最近吸取栏重建。全部 static，ed=map_editor 实例；数值与
## 节点属性与原 map_editor.gd 内联实现逐行一致。

class_name MapEditorBlockPalette
extends RefCounted

const BattlefieldDocScript = preload("res://scripts/editor/battlefield_doc.gd")
const BattlefieldRendererScript = preload("res://scripts/iso/battlefield_renderer.gd")


## 方块槽标签："地形中文名 · zN"（素材用 id）
static func label(block: Dictionary) -> String:
	var id := String(block.get("id", "plain"))
	var name := id
	if String(block.get("kind", "terrain")) == "terrain":
		name = String(BattlefieldDocScript.TERRAIN_CN.get(StringName(id), id))
	return "%s · z%d" % [name, int(block.get("z", 0))]


## 前景/背景槽色块文案（前/后 + label）
static func refresh_slot_ui(ed) -> void:
	if ed._fg_swatch != null:
		ed._fg_swatch.text = "前 %s" % label(ed._block_fg)
		ed._fg_swatch.tooltip_text = "前景：%s" % label(ed._block_fg)
	if ed._bg_swatch != null:
		ed._bg_swatch.text = "后 %s" % label(ed._block_bg)
		ed._bg_swatch.tooltip_text = "背景：%s" % label(ed._block_bg)


## 仅吸管成功时调用：按 (kind,id) 去重并置顶，z 取最近一次，最多保留 8 条。
static func remember_pick(ed, block: Dictionary) -> void:
	var kind := String(block.get("kind", "terrain"))
	var id := String(block.get("id", "plain"))
	for i in range(ed._recent_picks.size()):
		var old: Dictionary = ed._recent_picks[i]
		if String(old.get("kind", "terrain")) == kind and String(old.get("id", "plain")) == id:
			ed._recent_picks.remove_at(i)
			break
	ed._recent_picks.insert(0, {"kind": kind, "id": id, "z": int(block.get("z", 0))})
	if ed._recent_picks.size() > 8:
		ed._recent_picks.resize(8)
	ed._refresh_recent_picks()


## 最近吸取按钮短标签（地形取中文名前 2 字；素材 id 前 8 字截断）
static func short_label(block: Dictionary) -> String:
	var id := String(block.get("id", "plain"))
	if String(block.get("kind", "terrain")) == "terrain":
		return String(BattlefieldDocScript.TERRAIN_CN.get(StringName(id), id)).left(2)
	return id.left(8) + ("…" if id.length() > 8 else "")


## 最近吸取使用与真实地图一致的地形顶面/素材视觉贴图；加载失败才回退短标签。
static func texture(ed, block: Dictionary) -> Texture2D:
	var id := String(block.get("id", "plain"))
	var previews: Array = []
	if String(block.get("kind", "terrain")) == "terrain":
		previews = BattlefieldRendererScript.preview_blocks(StringName(id), false, true)
	else:
		if ed._asset_adapter == null:
			return null
		var visual: Dictionary = ed._asset_adapter.resolve(id)
		if visual.is_empty() or bool(visual.get("missing", false)):
			return null
		previews = [BattlefieldRendererScript.preview_visual_block(visual)]
	for part in previews:
		var texture := part.get("texture", null) as Texture2D
		if texture != null:
			return texture
	return null


## 重建最近吸取栏（贴图优先，失败回退短标签文本）
static func refresh_recent_picks(ed) -> void:
	if ed._recent_pick_list == null:
		return
	for child in ed._recent_pick_list.get_children():
		ed._recent_pick_list.remove_child(child)
		child.queue_free()
	for i in range(ed._recent_picks.size()):
		var block: Dictionary = ed._recent_picks[i]
		var button: Button = ed._pixel_btn()
		button.name = "RecentPick%d" % i
		button.text = short_label(block)
		button.tooltip_text = label(block)
		button.custom_minimum_size = Vector2(0, 40)
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(ed._on_recent_pick_pressed.bind(i))
		ed._recent_pick_list.add_child(button)
		var tex := texture(ed, block)
		if tex != null:
			button.text = ""
			var thumb := TextureRect.new()
			thumb.name = "RecentPickThumb"
			thumb.texture = tex
			thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(thumb)
			thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			thumb.offset_left = 4.0
			thumb.offset_top = 2.0
			thumb.offset_right = -4.0
			thumb.offset_bottom = -2.0
