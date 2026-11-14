## editor/asset_library_panel.gd — 用户素材库面板（地图编辑器「素材」Tab）
##
## 职责：素材库的可视化管理入口，全部操作经 UserAssetService 落库（user://custom_assets）：
##   - 分类过滤（地块/植物）+ 搜索（名称/id/标签）+ 标签过滤 + 来源过滤（本地/网络）
##   - 真实分页：全库先过滤 + 按 id 稳定排序，再切当前页；界面只创建当前页
##     列表行（PAGE_SIZE 条/页），翻页只重建本页行、不触发任何全库请求；
##     过滤条件变更回第 1 页，导入/隐藏/清单同步后校正页界（钳制不越界）
##   - 懒预览：列表项先上占位图标，真实缩略图由 UserAssetVisualAdapter.resolve 逐帧
##     限量烘焙（PREVIEW_BUDGET_PER_FRAME），1455 张素材不会一次性解码卡帧；
##     在线素材（image 为 http 且本地无 blob）保持占位显示、不自动下载——下载只由
##     「下载选中」按钮手动触发，asset_ready 后清 adapter 占位缓存换真图，
##     asset_failed 在状态栏给出真实错误
##   - 本地导入：FileDialog 多选 PNG/JPG/WebP（魔数校验在 service 层）
##   - 编辑：改名 / 改分类（kind）/ 标签 / render 参数（mode/crop/pivot/scale/footprint），
##     经 service.update_asset 校验落库，失败回滚
##   - 隐藏：remove_asset(keep_blob=true) + 二次确认；已下载 blob 保留，
##     地图与历史快照中的引用不丢失（缺图由渲染层占位提示）
##   - 多选与批量下载：列表为多选模式（普通点击=画笔主选，Ctrl+点击=加选/减选），
##     「保存标记」按钮对选中行切换用户保存标记（✓，持久化到库）；图片由预览自动加载缓存；
##     本地已有（导入/已下载）的素材行文本带「✓」前缀标注
##   - 来源 URL：编辑保存（set_source_url）/ 刷新（request_manifest）/ 错误重试
##
## 信号：
##   asset_selected(descriptor) — 选中变化；空 Dictionary = 取消选择
##   library_changed            — 库内容增删改（导入/隐藏/编辑/清单同步），
##                                map_editor 据此刷新画布与选中态
##
## 弹窗：FileDialog / ConfirmationDialog 均 exclusive，Esc 被弹窗自身消费（先关弹窗），
## 不会穿透到 map_editor 的 Esc→返回世界；map_editor 侧仍有 is_dialog_open() 双保险。

class_name AssetLibraryPanel
extends VBoxContainer

signal asset_selected(descriptor: Dictionary)
signal library_changed

const Catalog := preload("res://scripts/assets/user_asset_catalog.gd")
const UIFactoryScript = preload("res://scripts/ui/ui_factory.gd")
const UIThemeScript = preload("res://scripts/ui/ui_theme.gd")

## 每帧最多烘焙的真实预览数（懒队列限速：解码是同步磁盘 IO + CPU，避免卡帧）
const PREVIEW_BUDGET_PER_FRAME := 4

## 素材列表每页条数（3 列网格 × 8 行，侧栏宽 320 下一屏可读）
const PAGE_SIZE := 24

var service: UserAssetService = null
var adapter: UserAssetVisualAdapter = null

var _source_edit: LineEdit
var _source_save_btn: Button
var _refresh_btn: Button
var _retry_btn: Button
var _import_btn: Button
var _import_kind: OptionButton
var _download_btn: Button
var _kind_filter: OptionButton
var _source_filter: OptionButton
var _search_edit: LineEdit
var _tag_filter: OptionButton
var _asset_list: ItemList
var _empty_label: Label
var _status_label: Label

## 分页：当前页（0 起）；翻页/重建时由 _rebuild_grid 按过滤总数钳制
var _page := 0
var _prev_btn: Button
var _next_btn: Button
var _page_label: Label

var _detail_box: VBoxContainer
var _detail_title: Label
var _name_edit: LineEdit
var _tags_edit: LineEdit
var _mode_option: OptionButton
var _crop_x: SpinBox
var _crop_y: SpinBox
var _crop_w: SpinBox
var _crop_h: SpinBox
var _pivot_x: SpinBox
var _pivot_y: SpinBox
var _scale_box: SpinBox
var _fp_w: SpinBox
var _fp_h: SpinBox
var _apply_btn: Button
var _hide_btn: Button

var _file_dialog: FileDialog
var _hide_confirm: ConfirmationDialog

var _selected_id := ""
var _selected_index := -1
var _syncing_detail := false
## asset_id -> AssetList 行号（懒预览回写与重选恢复用）
var _cells: Dictionary = {}
var _preview_queue: Array[String] = []
var _queued: Dictionary = {}
var _placeholder_tex: Texture2D = null


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build_ui()


## map_editor 注入共享 service（非 autoload，场景持有）与共享 adapter（与画布同库同缓存）。
func setup(p_service: UserAssetService, p_adapter: UserAssetVisualAdapter) -> void:
	service = p_service
	adapter = p_adapter
	if not service.manifest_loaded.is_connected(_on_manifest_loaded):
		service.manifest_loaded.connect(_on_manifest_loaded)
	if not service.asset_ready.is_connected(_on_asset_ready):
		service.asset_ready.connect(_on_asset_ready)
	if not service.asset_failed.is_connected(_on_asset_failed):
		service.asset_failed.connect(_on_asset_failed)
	_source_edit.text = service.get_source_url()
	_rebuild_tag_filter()
	_rebuild_grid()


# ============================================================
# UI 构建
# ============================================================

func _build_ui() -> void:
	# ---- 来源 URL：输入 + 保存 + 刷新 + 错误重试 ----
	var src_row := HBoxContainer.new()
	src_row.name = "SourceRow"
	src_row.add_theme_constant_override("separation", 4)
	src_row.add_child(UIFactoryScript.label("来源", 11, UIThemeScript.TEXT_DIM))
	_source_edit = UIFactoryScript.line_edit("http://…/blocks.json")
	_source_edit.name = "SourceEdit"
	_source_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	src_row.add_child(_source_edit)
	add_child(src_row)
	UIFactoryScript.center_row(src_row)

	var src_btn_row := HBoxContainer.new()
	src_btn_row.add_theme_constant_override("separation", 4)
	_source_save_btn = UIFactoryScript.button("保存", _on_source_save, "floppy_disk")
	_source_save_btn.name = "SourceSaveButton"
	_source_save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	src_btn_row.add_child(_source_save_btn)
	_refresh_btn = UIFactoryScript.button("刷新清单", _on_refresh_pressed, "rotate")
	_refresh_btn.name = "RefreshButton"
	_refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	src_btn_row.add_child(_refresh_btn)
	_retry_btn = UIFactoryScript.button("重试", _on_refresh_pressed, "rotate")
	_retry_btn.name = "RetryButton"
	_retry_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retry_btn.visible = false
	src_btn_row.add_child(_retry_btn)
	add_child(src_btn_row)

	# ---- 本地导入 ----
	var import_row := HBoxContainer.new()
	import_row.name = "ImportRow"
	import_row.add_theme_constant_override("separation", 4)
	import_row.add_child(UIFactoryScript.label("导入", 11, UIThemeScript.TEXT_DIM))
	_import_kind = UIFactoryScript.option_button()
	_import_kind.name = "ImportKind"
	_import_kind.add_item("地块")
	_import_kind.set_item_metadata(0, Catalog.KIND_TERRAIN)
	_import_kind.add_item("植物")
	_import_kind.set_item_metadata(1, Catalog.KIND_PLANT)
	import_row.add_child(_import_kind)
	_import_btn = UIFactoryScript.button("本地图片…", _on_import_pressed, "folder_open")
	_import_btn.name = "ImportButton"
	_import_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_row.add_child(_import_btn)
	_download_btn = UIFactoryScript.button("保存标记", _on_download_selected, "cloud")
	_download_btn.name = "DownloadSelectedButton"
	_download_btn.tooltip_text = "下载所有选中（Ctrl+点击多选）的在线素材；已下载的自动跳过"
	_download_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_row.add_child(_download_btn)
	add_child(import_row)
	UIFactoryScript.center_row(import_row)

	# ---- 过滤：分类 / 来源 / 搜索 / 标签 ----
	var filter_row := HBoxContainer.new()
	filter_row.name = "FilterRow"
	filter_row.add_theme_constant_override("separation", 4)
	_kind_filter = UIFactoryScript.option_button()
	_kind_filter.name = "KindFilter"
	_kind_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kind_filter.add_item("地块")
	_kind_filter.set_item_metadata(0, Catalog.KIND_TERRAIN)
	_kind_filter.add_item("植物")
	_kind_filter.set_item_metadata(1, Catalog.KIND_PLANT)
	_kind_filter.item_selected.connect(func(_i: int): _page = 0; _rebuild_grid())
	filter_row.add_child(_kind_filter)
	_source_filter = UIFactoryScript.option_button()
	_source_filter.name = "SourceFilter"
	_source_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_filter.add_item("全部来源")
	_source_filter.set_item_metadata(0, "")
	_source_filter.add_item("本地")
	_source_filter.set_item_metadata(1, "local")
	_source_filter.add_item("网络")
	_source_filter.set_item_metadata(2, "net")
	_source_filter.item_selected.connect(func(_i: int): _page = 0; _rebuild_grid())
	filter_row.add_child(_source_filter)
	add_child(filter_row)

	_search_edit = UIFactoryScript.line_edit("搜索名称 / id / 标签")
	_search_edit.name = "SearchEdit"
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(func(_t: String): _page = 0; _rebuild_grid())
	add_child(_search_edit)

	_tag_filter = UIFactoryScript.option_button()
	_tag_filter.name = "TagFilter"
	_tag_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_filter.item_selected.connect(func(_i: int): _page = 0; _rebuild_grid())
	add_child(_tag_filter)

	# ---- 素材列表（懒预览网格）----
	_asset_list = ItemList.new()
	_asset_list.name = "AssetList"
	_asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_list.custom_minimum_size = Vector2(0, 180)
	_asset_list.icon_mode = ItemList.ICON_MODE_TOP
	_asset_list.max_columns = 3
	_asset_list.same_column_width = true
	_asset_list.fixed_icon_size = Vector2i(48, 48)
	_asset_list.allow_reselect = true
	# 多选：普通点击=切换画笔选中（主选），Ctrl+点击=加选/减选（用于批量下载）
	_asset_list.select_mode = ItemList.SELECT_MULTI
	_asset_list.multi_selected.connect(_on_multi_selected)
	_asset_list.item_clicked.connect(_on_item_clicked)
	add_child(_asset_list)

	# ---- 翻页：上一页 / 页码·总页数·匹配总数 / 下一页 ----
	var page_row := HBoxContainer.new()
	page_row.name = "PageRow"
	page_row.add_theme_constant_override("separation", 4)
	_prev_btn = UIFactoryScript.button("上一页", _on_prev_page, "arrow_up_from_line")
	_prev_btn.name = "PagePrevButton"
	page_row.add_child(_prev_btn)
	_page_label = UIFactoryScript.label("0 / 0", 11, UIThemeScript.TEXT_DIM)
	_page_label.name = "PageLabel"
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_row.add_child(_page_label)
	_next_btn = UIFactoryScript.button("下一页", _on_next_page, "arrow_down_to_line")
	_next_btn.name = "PageNextButton"
	page_row.add_child(_next_btn)
	add_child(page_row)

	_empty_label = UIFactoryScript.label("素材库为空 — 导入本地图片或刷新远程清单", 11, UIThemeScript.TEXT_DIM)
	_empty_label.name = "EmptyLabel"
	_empty_label.visible = false
	add_child(_empty_label)

	_build_detail_box()
	_build_dialogs()

	_status_label = UIFactoryScript.label("素材库就绪", 10, UIThemeScript.TEXT_DIM)
	_status_label.name = "AssetStatusLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)


## 选中素材的详情/编辑区（未选中时隐藏）
func _build_detail_box() -> void:
	_detail_box = VBoxContainer.new()
	_detail_box.name = "DetailBox"
	_detail_box.add_theme_constant_override("separation", 4)
	_detail_box.visible = false
	add_child(_detail_box)

	_detail_title = UIFactoryScript.label("选中：", 12, UIThemeScript.ACCENT)
	_detail_title.name = "DetailTitle"
	_detail_box.add_child(_detail_title)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	name_row.add_child(UIFactoryScript.label("名称", 11, UIThemeScript.TEXT_DIM))
	_name_edit = UIFactoryScript.line_edit()
	_name_edit.name = "NameEdit"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	_detail_box.add_child(name_row)
	UIFactoryScript.center_row(name_row)

	var tags_row := HBoxContainer.new()
	tags_row.add_theme_constant_override("separation", 4)
	tags_row.add_child(UIFactoryScript.label("标签", 11, UIThemeScript.TEXT_DIM))
	_tags_edit = UIFactoryScript.line_edit("逗号分隔")
	_tags_edit.name = "TagsEdit"
	_tags_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tags_row.add_child(_tags_edit)
	_detail_box.add_child(tags_row)
	UIFactoryScript.center_row(tags_row)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	mode_row.add_child(UIFactoryScript.label("模式", 11, UIThemeScript.TEXT_DIM))
	_mode_option = UIFactoryScript.option_button()
	_mode_option.name = "ModeOption"
	_mode_option.add_item("整图")
	_mode_option.set_item_metadata(0, Catalog.RENDER_MODE_FULL)
	_mode_option.add_item("裁切")
	_mode_option.set_item_metadata(1, Catalog.RENDER_MODE_CROP)
	mode_row.add_child(_mode_option)
	mode_row.add_child(UIFactoryScript.label("缩放", 11, UIThemeScript.TEXT_DIM))
	_scale_box = _spin(0.1, 4.0, 0.1, 1.0)
	_scale_box.name = "ScaleSpin"
	mode_row.add_child(_scale_box)
	_detail_box.add_child(mode_row)
	UIFactoryScript.center_row(mode_row)

	var crop_row := HBoxContainer.new()
	crop_row.name = "CropRow"
	crop_row.add_theme_constant_override("separation", 4)
	crop_row.add_child(UIFactoryScript.label("裁切", 11, UIThemeScript.TEXT_DIM))
	_crop_x = _spin(0, 8192, 1, 0)
	_crop_x.name = "CropX"
	crop_row.add_child(_crop_x)
	_crop_y = _spin(0, 8192, 1, 0)
	_crop_y.name = "CropY"
	crop_row.add_child(_crop_y)
	_crop_w = _spin(0, 8192, 1, 0)
	_crop_w.name = "CropW"
	crop_row.add_child(_crop_w)
	_crop_h = _spin(0, 8192, 1, 0)
	_crop_h.name = "CropH"
	crop_row.add_child(_crop_h)
	_detail_box.add_child(crop_row)
	UIFactoryScript.center_row(crop_row)

	var pivot_row := HBoxContainer.new()
	pivot_row.name = "PivotRow"
	pivot_row.add_theme_constant_override("separation", 4)
	pivot_row.add_child(UIFactoryScript.label("轴心", 11, UIThemeScript.TEXT_DIM))
	_pivot_x = _spin(0.0, 1.0, 0.05, 0.5)
	_pivot_x.name = "PivotX"
	pivot_row.add_child(_pivot_x)
	_pivot_y = _spin(0.0, 1.0, 0.05, 1.0)
	_pivot_y.name = "PivotY"
	pivot_row.add_child(_pivot_y)
	pivot_row.add_child(UIFactoryScript.label("占地", 11, UIThemeScript.TEXT_DIM))
	_fp_w = _spin(1, 8, 1, 1)
	_fp_w.name = "FootprintW"
	pivot_row.add_child(_fp_w)
	_fp_h = _spin(1, 8, 1, 1)
	_fp_h.name = "FootprintH"
	pivot_row.add_child(_fp_h)
	_detail_box.add_child(pivot_row)
	UIFactoryScript.center_row(pivot_row)

	var action_row := HBoxContainer.new()
	action_row.name = "DetailActionRow"
	action_row.add_theme_constant_override("separation", 4)
	_apply_btn = UIFactoryScript.button("应用修改", _on_apply_pressed, "checkmark")
	_apply_btn.name = "ApplyButton"
	_apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_apply_btn)
	_hide_btn = UIFactoryScript.button("隐藏素材", _on_hide_pressed, "eye_closed")
	_hide_btn.name = "HideButton"
	_hide_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_hide_btn)
	_detail_box.add_child(action_row)
	_detail_box.add_child(UIFactoryScript.label(
		"隐藏仅从素材库移除；图片文件保留，地图/历史引用不丢失（缺图显示占位）。",
		10, UIThemeScript.TEXT_DIM))


func _build_dialogs() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.name = "ImportFileDialog"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = false  # 内嵌弹窗：Esc 由弹窗自身消费，不穿透编辑器
	_file_dialog.exclusive = true
	_file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片文件"])
	_file_dialog.files_selected.connect(_on_files_selected)
	add_child(_file_dialog)

	_hide_confirm = ConfirmationDialog.new()
	_hide_confirm.name = "HideConfirmDialog"
	_hide_confirm.exclusive = true
	_hide_confirm.confirmed.connect(_on_hide_confirmed)
	add_child(_hide_confirm)


func _spin(min_v: float, max_v: float, step: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


# ============================================================
# 列表 / 过滤 / 懒预览
# ============================================================

## 当前过滤条件下的素材（分类 + 搜索 + 标签 + 来源），按 id 稳定排序保证翻页确定性
func _filtered_assets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if service == null:
		return out
	var want_kind := str(_kind_filter.get_selected_metadata())
	var want_source := str(_source_filter.get_selected_metadata())
	var want_tag := str(_tag_filter.get_selected_metadata())
	var q := _search_edit.text.strip_edges().to_lower()
	for d in service.list_assets():
		if String(d.get("kind", "")) != want_kind:
			continue
		if want_source == "net" and not String(d.get("image", "")).begins_with("http"):
			continue
		if want_source == "local" and String(d.get("image", "")).begins_with("http"):
			continue
		if not want_tag.is_empty():
			var has_tag := false
			for t in d.get("tags", []):
				if String(t) == want_tag:
					has_tag = true
					break
			if not has_tag:
				continue
		if not q.is_empty():
			var hay := "%s %s %s" % [d.get("id", ""), d.get("name", ""), " ".join(PackedStringArray(d.get("tags", [])))]
			if not hay.to_lower().contains(q):
				continue
		out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", "")))
	return out


## 标签下拉：按当前分类过滤后的全部标签（保留已选项）
func _rebuild_tag_filter() -> void:
	var keep := str(_tag_filter.get_selected_metadata()) if _tag_filter.selected >= 0 else ""
	_tag_filter.clear()
	_tag_filter.add_item("全部标签")
	_tag_filter.set_item_metadata(0, "")
	var tags := {}
	if service != null:
		var want_kind := str(_kind_filter.get_selected_metadata())
		for d in service.list_assets():
			if String(d.get("kind", "")) != want_kind:
				continue
			for t in d.get("tags", []):
				tags[String(t)] = true
	var sorted: Array = tags.keys()
	sorted.sort()
	var sel := 0
	for i in range(sorted.size()):
		_tag_filter.add_item(String(sorted[i]))
		_tag_filter.set_item_metadata(i + 1, sorted[i])
		if String(sorted[i]) == keep:
			sel = i + 1
	_tag_filter.select(sel)


func _rebuild_grid() -> void:
	if _asset_list == null:
		return
	_preview_queue.clear()
	_queued.clear()
	_cells.clear()
	_asset_list.clear()
	_selected_index = -1
	if adapter != null and _placeholder_tex == null:
		_placeholder_tex = adapter.placeholder_visual("__grid__").texture
	var assets := _filtered_assets()
	_empty_label.visible = assets.is_empty()
	# 页界校正：总数变化（导入/隐藏/清单同步/过滤变更）后钳制当前页
	var total_pages := maxi(1, int(ceil(float(assets.size()) / float(PAGE_SIZE))))
	_page = clampi(_page, 0, total_pages - 1)
	_update_pager(assets.size(), total_pages)
	var from := _page * PAGE_SIZE
	var to := mini(from + PAGE_SIZE, assets.size())
	for i in range(from, to):
		var d: Dictionary = assets[i]
		var aid := String(d.get("id", ""))
		var idx := _asset_list.item_count
		_asset_list.add_item(_row_display_name(d, aid))
		_asset_list.set_item_metadata(idx, aid)
		if _placeholder_tex != null:
			_asset_list.set_item_icon(idx, _placeholder_tex)
		var src := "网络" if String(d.get("image", "")).begins_with("http") else "本地"
		var tag_parts := PackedStringArray()
		for t in d.get("tags", []):
			tag_parts.append(String(t))
		_asset_list.set_item_tooltip(idx, "%s\n%s · %s · %dx%d\n%s" % [
			aid, "地块" if String(d.get("kind", "")) == Catalog.KIND_TERRAIN else "植物",
			src, int(d.get("width", 0)), int(d.get("height", 0)), ", ".join(tag_parts)])
		_cells[aid] = idx
		_enqueue_preview(aid)
	# 重选恢复（编辑改名/改标签后重建列表，选中态不丢）；翻页后选中项不在本页则不强行选回
	if not _selected_id.is_empty() and _cells.has(_selected_id):
		_selected_index = _cells[_selected_id]
		_asset_list.select(_selected_index)


## 页码 / 总页数 / 匹配总数；0 项时翻页禁用
func _update_pager(total_items: int, total_pages: int) -> void:
	if _page_label == null:
		return
	_page_label.text = "第 %d / %d 页 · 共 %d 条" % [_page + 1, total_pages, total_items]
	var can_prev := _page > 0
	var can_next := _page < total_pages - 1 and total_items > 0
	_prev_btn.disabled = not can_prev
	_next_btn.disabled = not can_next


func _goto_page(p: int) -> void:
	_page = p
	_rebuild_grid()


func _on_prev_page() -> void:
	_goto_page(_page - 1)


func _on_next_page() -> void:
	_goto_page(_page + 1)


func _enqueue_preview(asset_id: String) -> void:
	if _queued.has(asset_id):
		return
	_queued[asset_id] = true
	_preview_queue.append(asset_id)


## 懒预览泵：每帧限量把占位图标换成真实烘焙缩略图；面板不可见时暂停
func _process(_delta: float) -> void:
	if _preview_queue.is_empty() or not is_visible_in_tree() or adapter == null:
		return
	var budget := PREVIEW_BUDGET_PER_FRAME
	while budget > 0 and not _preview_queue.is_empty():
		var aid: String = _preview_queue.pop_front()
		_queued.erase(aid)
		if not _cells.has(aid):
			continue
		budget -= 1
		var visual: Dictionary = adapter.resolve(aid)
		var tex: Texture2D = visual.get("texture")
		if tex != null:
			_asset_list.set_item_icon(_cells[aid], tex)
		# 在线素材无本地 blob → 预览即自动加载，缓存进 blob 目录（用户随后可「保存标记」）
		if bool(visual.get("missing", false)) and service != null:
			var d: Variant = service.find_by_id(aid)
			if d is Dictionary and UserAssetService.is_http_url(String((d as Dictionary).get("image", ""))):
				service.request_asset_image(aid)


## 图片下载/导入完成：对应行立即上真实缩略图
func _on_asset_ready(asset_id: String) -> void:
	if _cells.has(asset_id) and adapter != null:
		# blob 刚到，必须先清掉 adapter 的占位缓存（占位按 "v:"+id 缓存，否则陈旧的占位会一直命中）
		adapter.clear_cache(asset_id)
		var visual: Dictionary = adapter.resolve(asset_id)
		var tex: Texture2D = visual.get("texture")
		if tex != null and not bool(visual.get("missing", false)):
			_asset_list.set_item_icon(_cells[asset_id], tex)


## 下载失败：占位保留，但状态栏必须给出真实错误（不再静默紫图）
func _on_asset_failed(asset_id: String, error: String) -> void:
	_status("素材 %s 下载失败：%s" % [asset_id, error], true)


# ============================================================
# 选择 / 编辑 / 隐藏
# ============================================================

func _on_item_selected(index: int) -> void:
	_apply_primary(index)


## 多选模式逐行回调：选中即成为画笔主选；减选主选时回退到其余选中行或清空
func _on_multi_selected(index: int, selected: bool) -> void:
	if selected:
		_apply_primary(index)
		return
	if index != _selected_index:
		return
	var rest := _asset_list.get_selected_items()
	if rest.is_empty():
		_selected_index = -1
		_selected_id = ""
		_detail_box.visible = false
		asset_selected.emit({})
	else:
		_apply_primary(rest[rest.size() - 1])


## 主选行：详情 + 画笔信号（单选语义保持，兼容既有调用方/测试）
func _apply_primary(index: int) -> void:
	var aid := str(_asset_list.get_item_metadata(index))
	_selected_index = index
	_selected_id = aid
	var d: Variant = service.find_by_id(aid)
	if d is Dictionary:
		_fill_detail(d)
		asset_selected.emit((d as Dictionary).duplicate(true))
	else:
		_detail_box.visible = false
		asset_selected.emit({})


## 再点一次已选中项 = 取消选择（与地形页按钮组互斥逻辑呼应）
func _on_item_clicked(index: int, _at: Vector2, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT or index != _selected_index:
		return
	_selected_index = -1
	_selected_id = ""
	_detail_box.visible = false
	asset_selected.emit({})


## 保存标记：对全部选中行切换「已保存」标记（✓），已标记的取消标记。
## 图片本身由懒预览自动加载进缓存目录，此按钮只维护用户保存标记（持久化到库）。
func _on_download_selected() -> void:
	if service == null:
		_status("素材服务未初始化", true)
		return
	var rows := _asset_list.get_selected_items()
	if rows.is_empty():
		_status("未选中素材：Ctrl+点击可加选多个", false)
		return
	var to_save: Array = []
	var to_unsave: Array = []
	for i in rows:
		var aid := str(_asset_list.get_item_metadata(i))
		var d: Variant = service.find_by_id(aid)
		if aid.is_empty() or not (d is Dictionary):
			continue
		if bool((d as Dictionary).get("saved", false)):
			to_unsave.append(aid)
		else:
			to_save.append(aid)
	if to_save.is_empty() and to_unsave.is_empty():
		_status("选中行无有效素材", false)
		return
	var err := ""
	if not to_save.is_empty():
		var r: Dictionary = service.set_assets_saved(to_save, true)
		if not bool(r.get("ok", false)):
			err = String(r.get("error", ""))
	if err.is_empty() and not to_unsave.is_empty():
		var r2: Dictionary = service.set_assets_saved(to_unsave, false)
		if not bool(r2.get("ok", false)):
			err = String(r2.get("error", ""))
	if not err.is_empty():
		_status("保存标记失败：%s" % err, true)
		return
	_status("已标记保存 %d 条，取消标记 %d 条" % [to_save.size(), to_unsave.size()], false)
	library_changed.emit()
	_rebuild_grid()


# ============================================================
# 已保存 ✓ 标注
# ============================================================

const READY_MARK := "✓ "

## 行显示名：用户标记保存（descriptor.saved）的加 ✓ 前缀；与图片是否已缓存无关
func _row_display_name(d: Dictionary, aid: String) -> String:
	var n := String(d.get("name", aid))
	if bool(d.get("saved", false)):
		return READY_MARK + n
	return n


func _base_item_text(row: int) -> String:
	return _asset_list.get_item_text(row).trim_prefix(READY_MARK)


## 外部清空选中（map_editor 选地形/植物时调用）；不回发信号，由调用方自清状态
func deselect() -> void:
	_selected_id = ""
	_selected_index = -1
	if _asset_list != null:
		_asset_list.deselect_all()
	if _detail_box != null:
		_detail_box.visible = false


func _fill_detail(desc: Dictionary) -> void:
	_syncing_detail = true
	_detail_box.visible = true
	_detail_title.text = "选中：%s（%s）" % [desc.get("name", ""), desc.get("id", "")]
	_name_edit.text = String(desc.get("name", ""))
	var tag_parts := PackedStringArray()
	for t in desc.get("tags", []):
		tag_parts.append(String(t))
	_tags_edit.text = ", ".join(tag_parts)
	var render: Dictionary = desc.get("render", Catalog.default_render())
	_mode_option.select(0 if String(render.get("mode", "full")) == Catalog.RENDER_MODE_FULL else 1)
	var img_w := int(desc.get("width", 0))
	var img_h := int(desc.get("height", 0))
	_crop_x.max_value = maxf(img_w, 1)
	_crop_y.max_value = maxf(img_h, 1)
	_crop_w.max_value = maxf(img_w, 1)
	_crop_h.max_value = maxf(img_h, 1)
	var crop: Variant = render.get("crop")
	if crop is Dictionary:
		_crop_x.value = int(crop.get("x", 0))
		_crop_y.value = int(crop.get("y", 0))
		_crop_w.value = int(crop.get("w", 0))
		_crop_h.value = int(crop.get("h", 0))
	else:
		_crop_x.value = 0
		_crop_y.value = 0
		_crop_w.value = 0
		_crop_h.value = 0
	var pivot: Dictionary = render.get("pivot", {"x": 0.5, "y": 1.0})
	_pivot_x.value = float(pivot.get("x", 0.5))
	_pivot_y.value = float(pivot.get("y", 1.0))
	_scale_box.value = float(render.get("scale", 1.0))
	var fp: Dictionary = render.get("footprint", {"w": 1, "h": 1})
	_fp_w.value = int(fp.get("w", 1))
	_fp_h.value = int(fp.get("h", 1))
	_syncing_detail = false


func _on_apply_pressed() -> void:
	if _selected_id.is_empty() or _syncing_detail:
		return
	var mode := str(_mode_option.get_selected_metadata())
	var render := {
		"mode": mode,
		"crop": null,
		"pivot": {"x": _pivot_x.value, "y": _pivot_y.value},
		"scale": _scale_box.value,
		"footprint": {"w": int(_fp_w.value), "h": int(_fp_h.value)},
	}
	if mode == Catalog.RENDER_MODE_CROP:
		render["crop"] = {"x": int(_crop_x.value), "y": int(_crop_y.value),
			"w": int(_crop_w.value), "h": int(_crop_h.value)}
	var tags: Array = []
	for t in _tags_edit.text.split(",", false):
		var ts := t.strip_edges()
		if not ts.is_empty():
			tags.append(ts)
	var changes := {
		"name": _name_edit.text,
		"tags": tags,
		"render": render,
	}
	var res: Dictionary = service.update_asset(_selected_id, changes)
	if bool(res.get("ok", false)):
		adapter.clear_cache(_selected_id)  # render 变了，旧缓存与烘焙图作废
		adapter.invalidate_baked(_selected_id)
		_status("已更新素材 %s" % _selected_id)
		library_changed.emit()
		_rebuild_grid()
	else:
		_status("更新失败：%s" % res.get("error", ""), true)


func _on_hide_pressed() -> void:
	if _selected_id.is_empty():
		return
	var d: Variant = service.find_by_id(_selected_id)
	var nm := String((d as Dictionary).get("name", _selected_id)) if d is Dictionary else _selected_id
	_hide_confirm.dialog_text = ("从素材库隐藏「%s」？\n已下载的图片文件保留；"
		+ "已放置的地图引用与历史快照不丢失（缺图时显示占位图）。") % nm
	_hide_confirm.popup_centered()


func _on_hide_confirmed() -> void:
	if _selected_id.is_empty():
		return
	var res: Dictionary = service.remove_asset(_selected_id, true)
	if bool(res.get("ok", false)):
		adapter.clear_cache(_selected_id)
		_selected_id = ""
		_selected_index = -1
		_detail_box.visible = false
		_status("已隐藏素材（图片 blob 保留）")
		library_changed.emit()
		_rebuild_grid()
	else:
		_status("隐藏失败：%s" % res.get("error", ""), true)


# ============================================================
# 导入 / 来源 URL
# ============================================================

func _on_import_pressed() -> void:
	_file_dialog.popup_centered_ratio(0.72)


func _on_files_selected(paths: PackedStringArray) -> void:
	var kind := str(_import_kind.get_selected_metadata())
	var ok_count := 0
	var fail_msgs: Array[String] = []
	for p in paths:
		var res: Dictionary = service.import_local_file(p, kind)
		if bool(res.get("ok", false)):
			ok_count += 1
		else:
			fail_msgs.append("%s: %s" % [p.get_file(), res.get("error", "")])
	if ok_count > 0:
		adapter.clear_cache()
		_rebuild_tag_filter()
		_status("导入完成：%d 个素材（%s）" % [ok_count, "地块" if kind == Catalog.KIND_TERRAIN else "植物"])
		library_changed.emit()
		_rebuild_grid()
	else:
		_status("导入失败：%s" % "; ".join(fail_msgs), true)


func _on_source_save() -> void:
	var res: Dictionary = service.set_source_url(_source_edit.text.strip_edges())
	if bool(res.get("ok", false)):
		_status("来源已保存：%s" % _source_edit.text.strip_edges())
		_request_refresh()
	else:
		_status("来源无效：%s" % res.get("error", ""), true)


func _on_refresh_pressed() -> void:
	_request_refresh()


func _request_refresh() -> void:
	var res: Dictionary = service.request_manifest()
	if bool(res.get("ok", false)):
		_retry_btn.visible = false
		_status("正在同步素材清单…")
	else:
		_status("清单请求失败：%s" % res.get("error", ""), true)
		_retry_btn.visible = true


func _on_manifest_loaded(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		_retry_btn.visible = false
		_status("清单同步完成：新增 %d / 更新 %d / 共 %d" % [
			int(result.get("added", 0)), int(result.get("updated", 0)), int(result.get("total", 0))])
		adapter.clear_cache()
		_rebuild_tag_filter()
		library_changed.emit()
		_rebuild_grid()
	else:
		_status("清单同步失败：%s" % result.get("error", ""), true)
		_retry_btn.visible = true


# ============================================================
# 弹窗守卫（map_editor Esc 双保险）/ 状态栏
# ============================================================

func is_dialog_open() -> bool:
	return (_file_dialog != null and _file_dialog.visible) \
		or (_hide_confirm != null and _hide_confirm.visible)


func close_dialogs() -> void:
	if _file_dialog != null:
		_file_dialog.hide()
	if _hide_confirm != null:
		_hide_confirm.hide()


func _status(text: String, is_error := false) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color",
		UIThemeScript.ERROR if is_error else UIThemeScript.TEXT_DIM)
