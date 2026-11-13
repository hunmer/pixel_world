## scripts/scenes/pixelfx_gallery.gd — pixelfx 特效画廊测试场景：左侧紧凑缩略图墙（96px 静态代表帧）分列展示全部 244 个特效，
## 支持分类过滤 / 搜索 / 调色板重着色；点击缩略图在右侧大预览区播放，act 类特效可用完整演出（角色 + 目标 + freeze + shake）。
## 性能：烘焙是逐帧 GDScript 模拟（sim 帧依赖前序状态，~50ms/帧），并发播放必然卡顿（实测 6 并发 ~300ms/帧），
## 因此缩略图全部静态化：每格只烘一张代表帧（第 BAKE_FRAME 帧）的 Sprite2D，首次滚入视口才分帧烘焙；动画只出现在预览面板。
## ESC 退出。
extends Control

const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const Registry := preload("res://addons/pixelfx/fx/registry.gd")
const Categories := preload("res://addons/pixelfx/fx/categories.gd")
const Baker := preload("res://addons/pixelfx/bake/baker.gd")
const PixelFx2DScript := preload("res://addons/pixelfx/nodes/pixel_fx_2d.gd")
const PixelFxAct2DScript := preload("res://addons/pixelfx/nodes/pixel_fx_act_2d.gd")
const Px := preload("res://addons/pixelfx/core/px.gd")

const CELL := 96
const HOST := 76
const GAP := 4
const PANEL_W := 440
const PREVIEW_W := 400.0
const PREVIEW_H := 340.0

## 网格展示的帧序号（0 是首帧，多数特效此时还是空白，第 3 帧通常已有可见内容）。
const BAKE_FRAME := 3
## 每次 Timer（0.4s）最多烘焙的格子数：每格 ~3 帧 × 56ms ≈ 170ms，分帧摊开避免卡顿。
const BAKE_PER_TICK := 2
## 探针实测首帧烘焙超 1s 的特效（transitions/burn-away 2.8s、impacts/impact-frame 1.2s）：
## 网格只显示占位文字，点击预览才播放。（有导出 png 时优先 png，此黑名单自动失效）
const NO_BAKE_IDS := ["transitions/burn-away", "impacts/impact-frame"]

## 离线导出的 png 缓存根目录（scripts/tools/pixelfx_export.gd 生成）。
## 命中时缩略图/预览直接读图零烘焙；未命中回退运行时烘焙。
const EXPORT_ROOT := "res://assets/pixelfx_export"

var _grid: GridContainer
var _scroll: ScrollContainer
var _category_option: OptionButton
var _palette_option: OptionButton
var _search_edit: LineEdit
var _count_label: Label
var _preview_host: Control
var _preview_info: Label
var _preview_fx: Node2D
var _preview_id := ""
var _preview_flip := false
var _preview_seed := -1
var _preview_act_mode := true
var _act_toggle: CheckButton
var _replay_btn: Button
var _selected_panel: PanelContainer
var _preview_bake_gen := 0

var _cells: Array = []
var _bake_queue: Array = []

var _style_idle: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _style_pick: StyleBoxFlat


func _ready() -> void:
	_mute_panku_overlays()
	_make_styles()
	_build_ui()
	_rebuild_grid()
	var t := Timer.new()
	t.wait_time = 0.4
	t.timeout.connect(_update_visibility)
	add_child(t)
	t.start()
	_show_preview("fire/campfire")
	tree_exiting.connect(_restore_panku_overlays)
	print("pixelfx_gallery: ready, %d cells, %d columns" % [_cells.size(), _grid.columns])
	get_viewport().size_changed.connect(_relayout_columns)
	for a in OS.get_cmdline_user_args():
		if a == "--shot":
			_shot_mode()
		elif a == "--verify":
			_verify_mode()
		elif a.begins_with("--auto-pick:"):
			var pick_id := a.substr("--auto-pick:".length())
			if Registry.EFFECTS.has(pick_id):
				_show_preview(pick_id)


## 自动验证：等待预览加载/预热完成后打印状态并退出。用法：... -- --verify [--auto-pick:<id>]
func _verify_mode() -> void:
	await get_tree().create_timer(6.0).timeout
	var png_dirs := 0
	for c in _cells:
		if _export_dir(c.id) != "":
			png_dirs += 1
	var kind := "none" if _preview_fx == null else "runtime_fx"
	print("pixelfx_gallery: verify preview_id=%s fx=%s replay_disabled=%s replay_text=%s png_dirs=%d/%d" % [
		_preview_id, kind, _replay_btn.disabled, _replay_btn.text, png_dirs, _cells.size()])
	get_tree().quit()


## 无头/自动验证：等待烘焙几批 + 预览启动后截取自身视口存盘退出。用法：... PixelFxGallery.tscn -- --shot
func _shot_mode() -> void:
	await get_tree().create_timer(8.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("E:/pixel_world/tmp/gallery_shot.png")
	print("pixelfx_gallery: shot saved, size=%s" % img.get_size())
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


var _panku_overlay_mode_prev: int = -1
var _panku_notifier_prev_visible := true


## 画廊是给人看的展示/截图场景：静音 panku 的屏幕消息展示——
## native_logger 的 output overlay（默认 AlwaysShow，把 print/警告逐条刷在画面左上角）与
## screen_notifier 的常驻通知层。只改运行时可见性（直接调 set_overlay_display_mode，绕开 opt 的
## 持久化 setter，不写 panku 全局配置）；tree_exiting 时恢复原状。
func _mute_panku_overlays() -> void:
	var panku := get_node_or_null("/root/Panku")
	if panku == null:
		return
	if panku.module_manager.has_module("native_logger"):
		var logger: PankuModuleNativeLogger = panku.module_manager.get_module("native_logger")
		_panku_overlay_mode_prev = logger.output_overlay_display_mode
		logger.set_overlay_display_mode(PankuModuleNativeLogger.ScreenOverlayDisplayMode.NeverShow)
	if panku.module_manager.has_module("screen_notifier"):
		var notifier: PankuModuleScreenNotifier = panku.module_manager.get_module("screen_notifier")
		_panku_notifier_prev_visible = notifier.notifier_layer.visible
		notifier.notifier_layer.visible = false


func _restore_panku_overlays() -> void:
	if _panku_overlay_mode_prev < 0:
		return
	var panku := get_node_or_null("/root/Panku")
	if panku == null:
		return
	if panku.module_manager.has_module("native_logger"):
		var logger: PankuModuleNativeLogger = panku.module_manager.get_module("native_logger")
		logger.set_overlay_display_mode(_panku_overlay_mode_prev)
	if panku.module_manager.has_module("screen_notifier"):
		var notifier: PankuModuleScreenNotifier = panku.module_manager.get_module("screen_notifier")
		notifier.notifier_layer.visible = _panku_notifier_prev_visible
	_panku_overlay_mode_prev = -1


func _make_styles() -> void:
	_style_idle = StyleBoxFlat.new()
	_style_idle.bg_color = Color(0.11, 0.11, 0.14)
	_style_idle.border_color = Color(0.25, 0.25, 0.32)
	_style_idle.set_border_width_all(1)
	_style_idle.set_corner_radius_all(4)
	_style_hover = _style_idle.duplicate()
	_style_hover.border_color = Color(0.45, 0.45, 0.58)
	_style_pick = _style_idle.duplicate()
	_style_pick.border_color = Color(0.30, 0.85, 0.50)
	_style_pick.set_border_width_all(2)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var top := HBoxContainer.new()
	top.anchor_left = 0.0
	top.anchor_top = 0.0
	top.anchor_right = 1.0
	top.anchor_bottom = 0.0
	top.offset_left = 8
	top.offset_top = 6
	top.offset_right = -PANEL_W
	top.offset_bottom = 44
	top.add_theme_constant_override("separation", 10)
	add_child(top)

	var title := UIFactoryScript.label("pixelfx 画廊", 18, Color(0.95, 0.85, 0.55))
	top.add_child(title)

	_category_option = UIFactoryScript.option_button()
	_category_option.add_item("全部分类", 0)
	_category_option.set_item_metadata(0, "")
	for i in Categories.categories.size():
		var c: Dictionary = Categories.categories[i]
		_category_option.add_item(String(c.name), i + 1)
		_category_option.set_item_metadata(i + 1, String(c.id))
	_category_option.item_selected.connect(func(_i: int) -> void: _rebuild_grid())
	top.add_child(_category_option)

	_search_edit = UIFactoryScript.line_edit("搜索 id / 名称…")
	_search_edit.custom_minimum_size = Vector2(190, 30)
	_search_edit.text_changed.connect(func(_t: String) -> void: _rebuild_grid())
	top.add_child(_search_edit)

	_palette_option = UIFactoryScript.option_button()
	_palette_option.add_item("原色", 0)
	_palette_option.set_item_metadata(0, "")
	var pal_keys: Array = Px.PAL.keys()
	for i in pal_keys.size():
		_palette_option.add_item(String(pal_keys[i]), i + 1)
		_palette_option.set_item_metadata(i + 1, String(pal_keys[i]))
	_palette_option.item_selected.connect(_on_palette_selected)
	top.add_child(_palette_option)

	_count_label = UIFactoryScript.label("", 16, Color(0.6, 0.6, 0.66))
	top.add_child(_count_label)

	_scroll = ScrollContainer.new()
	_scroll.anchor_left = 0.0
	_scroll.anchor_top = 0.0
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.offset_left = 8
	_scroll.offset_top = 52
	_scroll.offset_right = -(PANEL_W + 8)
	_scroll.offset_bottom = -8
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_grid = GridContainer.new()
	_grid.name = "ThumbGrid"
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	_scroll.add_child(_grid)

	var pv := PanelContainer.new()
	pv.anchor_left = 1.0
	pv.anchor_top = 0.0
	pv.anchor_right = 1.0
	pv.anchor_bottom = 1.0
	pv.offset_left = -PANEL_W
	pv.offset_top = 8
	pv.offset_right = -8
	pv.offset_bottom = -8
	add_child(pv)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pv.add_child(v)

	_preview_host = Control.new()
	_preview_host.custom_minimum_size = Vector2(PREVIEW_W, PREVIEW_H)
	_preview_host.clip_contents = true
	v.add_child(_preview_host)
	var pvbg := ColorRect.new()
	pvbg.color = Color(0.05, 0.05, 0.07)
	pvbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pvbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_host.add_child(pvbg)

	_preview_info = UIFactoryScript.label("", 13, Color.WHITE)
	_preview_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_info.custom_minimum_size = Vector2(0, 92)
	v.add_child(_preview_info)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)

	var replay := UIFactoryScript.button("重播", func() -> void:
		if _preview_fx:
			_preview_fx.play())
	row.add_child(replay)
	_replay_btn = replay

	var flip_btn := UIFactoryScript.button("翻转")
	flip_btn.toggle_mode = true
	flip_btn.toggled.connect(func(on: bool) -> void:
		_preview_flip = on
		_show_preview(_preview_id))
	row.add_child(flip_btn)

	var seed_btn := UIFactoryScript.button("换种子", func() -> void:
		_preview_seed = randi() % 1000
		_show_preview(_preview_id))
	row.add_child(seed_btn)

	_act_toggle = UIFactoryScript.check_button("完整演出")
	_act_toggle.button_pressed = _preview_act_mode
	_act_toggle.toggled.connect(func(on: bool) -> void:
		_preview_act_mode = on
		_show_preview(_preview_id))
	row.add_child(_act_toggle)


## 窗口/视口尺寸变化时只重算列数（GridContainer 自动重排，烘焙缓存不失效）。
func _relayout_columns() -> void:
	if _grid == null:
		return
	var cols := maxi(3, int((get_viewport_rect().size.x - PANEL_W - 48) / (CELL + GAP)))
	if cols != _grid.columns:
		_grid.columns = cols


func _current_category() -> String:
	var i := _category_option.selected
	return "" if i <= 0 else String(_category_option.get_item_metadata(i))


func _current_palette() -> String:
	var i := _palette_option.selected
	return "" if i <= 0 else String(_palette_option.get_item_metadata(i))


func _on_palette_selected(_i: int) -> void:
	var pal := _current_palette()
	for c in _cells:
		if _export_dir(c.id) != "":
			continue  # png 缩略图固定原色，不随调色板变，不重置
		c["baked"] = false
		c["queued"] = false
		if c.sprite != null:
			c.sprite.texture = null
	_bake_queue.clear()
	_update_visibility()
	if _preview_id != "":
		_show_preview(_preview_id)


static func _cat_index(cat: String) -> int:
	for i in Categories.categories.size():
		if String(Categories.categories[i].id) == cat:
			return i
	return 999


func _cat_first(a: String, b: String) -> bool:
	var ca := _cat_index(a.get_slice("/", 0))
	var cb := _cat_index(b.get_slice("/", 0))
	if ca != cb:
		return ca < cb
	return a < b


func _rebuild_grid() -> void:
	for c in _cells:
		c.panel.queue_free()
	_cells.clear()
	_bake_queue.clear()
	_selected_panel = null
	_relayout_columns()
	var cat := _current_category()
	var search := _search_edit.text.to_lower()
	var ids: Array = Registry.ids()
	ids.sort_custom(_cat_first)
	var shown := 0
	for id in ids:
		var meta: Dictionary = Registry.EFFECTS[id]
		if cat != "" and String(id).get_slice("/", 0) != cat:
			continue
		if search != "" and not (String(id).to_lower().contains(search) or String(meta.name).to_lower().contains(search)):
			continue
		_cells.append(_make_cell(String(id), meta))
		shown += 1
	_count_label.text = "%d / %d" % [shown, ids.size()]
	_update_visibility()


func _make_cell(id: String, meta: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CELL, CELL)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _style_idle)
	_grid.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var host := Control.new()
	host.custom_minimum_size = Vector2(HOST, HOST)
	host.clip_contents = true
	host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(host)

	var label := Label.new()
	label.text = id.get_slice("/", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
	box.add_child(label)

	# 静态代表帧：Sprite2D + 延迟烘焙（_update_visibility 分帧）；重型特效仅在无导出 png 时放占位文字，
	# 有 png 则照常建 Sprite2D（黑名单自动失效，与 _update_visibility/_bake_cell 的守卫语义一致）。
	var sp: Sprite2D = null
	if NO_BAKE_IDS.has(id) and _export_dir(id) == "":
		var hint := Label.new()
		hint.text = "（点击预览）"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 9)
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.56))
		host.add_child(hint)
	else:
		sp = Sprite2D.new()
		sp.centered = false
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		host.add_child(sp)

	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_pick(id, panel))
	panel.mouse_entered.connect(func() -> void:
		if _selected_panel != panel:
			panel.add_theme_stylebox_override("panel", _style_hover))
	panel.mouse_exited.connect(func() -> void:
		if _selected_panel != panel:
			panel.add_theme_stylebox_override("panel", _style_idle))
	return {"panel": panel, "sprite": sp, "id": id}


## 视口裁剪 + 分帧烘焙：可见且未烘的格子进队列，每次只烘 BAKE_PER_TICK 个，摊平 ~170ms/格 的烘焙成本。
func _update_visibility() -> void:
	if _scroll == null:
		return
	var view := _scroll.get_global_rect().grow(CELL * 2)
	for c in _cells:
		if c.get("baked", false):
			continue
		if NO_BAKE_IDS.has(c.id) and _export_dir(c.id) == "":
			continue
		var on: bool = c.panel.get_global_rect().intersects(view)
		if on and not c.get("queued", false):
			if _export_dir(c.id) != "":
				# png 直读便宜（几 ms），同步出图不排队
				c["queued"] = true
				_bake_cell(c)
				continue
			c["queued"] = true
			_bake_queue.append(c)
	var baked := 0
	while baked < BAKE_PER_TICK and not _bake_queue.is_empty():
		var cell: Dictionary = _bake_queue.pop_front()
		if not is_instance_valid(cell.panel):
			continue
		_bake_cell(cell)
		baked += 1


## 该特效离线导出目录（id 中 / 换 _），无缩略图返回 ""。
func _export_dir(id: String) -> String:
	var dir := "%s/%s" % [EXPORT_ROOT, id.replace("/", "_")]
	return dir if FileAccess.file_exists(dir + "/thumb.png") else ""


## 直接从磁盘读 png（绕过资源导入，headless/发布包可用），失败返回 null。
func _load_png_texture(path: String) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(img)


## 烘出该格的代表帧（第 BAKE_FRAME 帧）并挂到 Sprite2D 上。
## 有离线导出 png 时直接读 thumb.png（零烘焙、不随调色板换色）；否则回退运行时烘焙。
func _bake_cell(c: Dictionary) -> void:
	var meta: Dictionary = Registry.EFFECTS[c.id]
	var sp: Sprite2D = c.sprite
	var edir := _export_dir(c.id)
	if edir != "":
		var thumb: ImageTexture = _load_png_texture(edir + "/thumb.png")
		if thumb != null:
			sp.texture = thumb
			var size := Vector2(meta.size[0], meta.size[1])
			var s := _fit(size.x, size.y, HOST, HOST, 4.0)
			sp.scale = Vector2(s, s)
			sp.position = Vector2(HOST, HOST) * 0.5 - size * s * 0.5
			c["baked"] = true
			return
	var mod: Resource = load(meta.get("path"))
	var opts := {"seed": 1.0}
	var pal := _current_palette()
	if pal != "" and Px.PAL.has(pal):
		opts["palette"] = Px.PAL[pal]
	var track = Baker.track(mod, opts)
	var i := mini(BAKE_FRAME, track.n - 1)
	var tex: ImageTexture = track.get_textures(i)[2]
	sp.texture = tex
	var size := Vector2(meta.size[0], meta.size[1])
	# 缩略图按纹理几何中心对齐格子中心（忽略 origin —— origin 常在角色脚部，会把内容顶到格子边缘），
	# 并放宽放大上限让小素材也能填满格子。
	var s := _fit(size.x, size.y, HOST, HOST, 4.0)
	sp.scale = Vector2(s, s)
	sp.position = Vector2(HOST, HOST) * 0.5 - size * s * 0.5
	c["baked"] = true


func _pick(id: String, panel: PanelContainer) -> void:
	if _selected_panel:
		_selected_panel.add_theme_stylebox_override("panel", _style_idle)
	_selected_panel = panel
	panel.add_theme_stylebox_override("panel", _style_pick)
	_show_preview(id)


func _show_preview(id: String) -> void:
	if id == "" or not Registry.EFFECTS.has(id):
		return
	_preview_id = id
	if _preview_fx:
		_preview_fx.queue_free()
		_preview_fx = null
	var meta: Dictionary = Registry.EFFECTS[id]
	var use_act: bool = meta.act and _preview_act_mode
	_act_toggle.disabled = not meta.act
	_replay_btn.disabled = false
	_replay_btn.text = "重播"
	if use_act:
		var act: Node2D = PixelFxAct2DScript.new()
		act.effect = id
		act.autoplay = true
		act.loop_act = true
		act.flip = _preview_flip
		act.seed = _preview_seed
		act.palette_preset = _current_palette()
		_preview_host.add_child(act)
		var w: int = act._frame.w
		var h: int = act._frame.h
		var sa := _fit(w, h, PREVIEW_W - 24.0, PREVIEW_H - 24.0, 2.0)
		act.scale = Vector2(sa, sa)
		act.position = Vector2(PREVIEW_W, PREVIEW_H) * 0.5 + (act._pivot - Vector2(w, h) * 0.5) * sa
		_preview_fx = act
	else:
		var fx: Node2D = PixelFx2DScript.new()
		fx.effect = id
		fx.autoplay = false
		fx.speed_scale = 1.0
		fx.flip = _preview_flip
		fx.seed = _preview_seed
		fx.palette_preset = _current_palette()
		_preview_host.add_child(fx)
		var sp := _fit(meta.size[0], meta.size[1], PREVIEW_W - 24.0, PREVIEW_H - 24.0, 3.0)
		fx.scale = Vector2(sp, sp)
		fx.position = Vector2(PREVIEW_W, PREVIEW_H) * 0.5 + (Vector2(meta.origin[0], meta.origin[1]) - Vector2(meta.size[0], meta.size[1]) * 0.5) * sp
		if not meta.loop:
			fx.finished.connect(func() -> void:
				await get_tree().create_timer(1.0).timeout
				if is_instance_valid(fx) and _preview_fx == fx:
					fx.play())
		_preview_fx = fx
		_preview_bake_gen += 1
		_prebake_preview(fx, _preview_bake_gen)
	_preview_info.text = _info_text(id, meta, use_act)


## 分帧预热预览特效的全部烘焙帧（BAKED 懒烘是逐帧实时模拟，首播每帧 ~50ms 会卡成 ~15fps）。
## 每游戏帧烘 1 帧摊平成本，进度显示在重播按钮上；全部就绪后再 play()，播放全程走缓存纹理。
func _prebake_preview(fx: Node2D, gen: int) -> void:
	_replay_btn.disabled = true
	var track = fx._track
	if track == null or track.n <= 1:
		_replay_btn.disabled = false
		if is_instance_valid(fx):
			fx.play()
		return
	for i in track.n:
		if not is_instance_valid(fx) or gen != _preview_bake_gen:
			return
		track.get_textures(i)
		_replay_btn.text = "烘焙中 %d/%d" % [i + 1, track.n]
		await get_tree().process_frame
	if not is_instance_valid(fx) or gen != _preview_bake_gen:
		return
	_replay_btn.disabled = false
	_replay_btn.text = "重播"
	fx.play()


func _info_text(id: String, meta: Dictionary, use_act: bool) -> String:
	var cat := id.get_slice("/", 0)
	var blurb := ""
	for c in Categories.categories:
		if String(c.id) == cat:
			blurb = String(c.blurb)
			break
	var kind_map := {"factory": "多段招式", "sim": "粒子模拟", "pure": "程序绘制"}
	var kind := String(kind_map.get(String(meta.kind), String(meta.kind)))
	var act_note := ""
	if meta.act:
		act_note = " · 完整演出" if use_act else " · 可演出"
	return "%s — %s\n%s\n%dx%d · %.2fs · %s · %s%s" % [
		id, String(meta.name), blurb,
		int(meta.size[0]), int(meta.size[1]), float(meta.duration),
		"循环" if meta.loop else "单次", kind, act_note,
	]


func _fit(w: float, h: float, aw: float, ah: float, cap: float) -> float:
	if w <= 0.0 or h <= 0.0:
		return 1.0
	return minf(minf(aw / w, ah / h), cap)
