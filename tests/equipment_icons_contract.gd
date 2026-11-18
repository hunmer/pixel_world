## tests/equipment_icons_contract.gd — 装备图标目录与绑定契约
## 覆盖：①目录形状（"01".."11" 数字字符串稳定 ID、显式 ID→路径映射、ICON_LIST 完整）
## ②绑定完整性（data/equipment.json 11 件装备 iconId 与锁定绑定表一致、互异、全部在目录内）
## ③纹理行为（资产就绪→get_texture 加载本 ID 真实路径、禁兜底通过；资产未入库→
##   非 null 应急品红纹理同实例，UI 照常可用；缓存同实例；未知 ID 回退默认）
## ④隔离缝（_load_hook 模拟全部加载失败→非 null 应急纹理、同实例、绝不返回 null）
## 运行：godot --headless --path . --script res://tests/equipment_icons_contract.gd
extends SceneTree

## 装备 id → iconId 的稳定绑定表，防止既有绑定漂移（与 data/equipment.json 一致）。
const EXPECTED_BINDINGS := {
	&"ironSword": "01",
	&"steelSword": "02",
	&"ironLance": "03",
	&"ironAxe": "04",
	&"ironBow": "05",
	&"fire": "06",
	&"heal": "07",
	&"leatherShield": "08",
	&"kiteShield": "09",
	&"campaignCloak": "10",
	&"luckyPendant": "11",
}

var failures := 0

## headless 直跑不刷新全局类缓存，统一 preload 引用（与 item_icons 契约一致）。
const EquipmentIcons := preload("res://scripts/core/equipment_icons.gd")


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _run() -> void:
	_run_catalog_shape()
	_run_binding_integrity()
	_run_texture_behavior()
	_run_load_hook_seam()
	if failures == 0:
		print("EQUIPMENT_ICONS_CONTRACT_OK")
	else:
		printerr("EQUIPMENT_ICONS_CONTRACT_FAILED: %d 处失败" % failures)
	quit(0 if failures == 0 else 1)


## ①目录形状：11 个两位零填充数字字符串 ID，路径逐条与显式映射一致。
func _run_catalog_shape() -> void:
	var paths: Dictionary = EquipmentIcons.ICON_PATHS
	var ids: Array = EquipmentIcons.ICON_LIST
	_expect(paths.size() == 11, "图标目录应为 11 项，实际 %d" % paths.size())
	_expect(ids.size() == 11, "ICON_LIST 应为 11 项，实际 %d" % ids.size())
	for n in range(1, 12):
		var iid := StringName("%02d" % n)
		_expect(paths.has(iid), "目录缺少稳定 ID %s" % String(iid))
		_expect(ids.has(iid), "ICON_LIST 缺少 %s" % String(iid))
		_expect(String(paths.get(iid, "")) == "res://assets/ui/equipment/%02d.png" % n,
			"ID %s 路径应为 assets/ui/equipment/%02d.png" % [String(iid), n])
	_expect(EquipmentIcons.DEFAULT_ICON_ID == &"01", "默认图标应为 \"01\"")
	_expect(not EquipmentIcons.has_icon(&"12"), "目录不应含未声明的 \"12\"")
	_expect(EquipmentIcons.icon_path(&"99") == "", "未知 ID 的 icon_path 应为空串")


## ②绑定完整性：原始 JSON 直检 11 件装备 iconId（非空、在目录内、互异、与锁定表一致）。
func _run_binding_integrity() -> void:
	var f := FileAccess.open("res://data/equipment.json", FileAccess.READ)
	_expect(f != null, "data/equipment.json 应可读")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	_expect(parsed is Dictionary, "equipment.json 顶层应为对象")
	if not (parsed is Dictionary):
		return
	var entries: Variant = parsed.get("equipment", [])
	_expect(entries is Array, "equipment.json 应含 equipment 数组")
	if not (entries is Array):
		return
	_expect(entries.size() == 11, "装备应 11 件，实际 %d" % entries.size())
	var seen := {}
	for entry: Dictionary in entries:
		var eid := StringName(String(entry.get("id", "")))
		var expected: String = EXPECTED_BINDINGS.get(eid, "")
		_expect(expected != "", "出现未知装备 %s" % String(eid))
		var icon_id := String(entry.get("iconId", ""))
		_expect(icon_id != "", "装备 %s 的 iconId 不应为空" % String(eid))
		_expect(EquipmentIcons.has_icon(StringName(icon_id)),
			"装备 %s 的 iconId %s 不在图标目录内" % [String(eid), icon_id])
		_expect(icon_id == expected, "装备 %s 的 iconId 应为 %s，实际 %s" % [String(eid), expected, icon_id])
		_expect(not seen.has(icon_id), "iconId %s 被多件装备重复绑定" % icon_id)
		seen[icon_id] = true
	_expect(seen.size() == 11, "11 件装备应绑定 11 个互异 iconId，实际 %d" % seen.size())


## ③纹理行为：每个 ID 非 null；文件就绪→纹理来自本 ID 真实路径（禁兜底通过）；
## 未入库→应急品红纹理同实例；缓存同实例；未知 ID 回退默认。
func _run_texture_behavior() -> void:
	_reset_catalog_state()
	var emergency: Texture2D = EquipmentIcons._emergency_texture()
	_expect(emergency != null, "应急纹理构造应为非 null")
	for iid: StringName in EquipmentIcons.ICON_LIST:
		var tex: Texture2D = EquipmentIcons.get_texture(iid)
		_expect(tex != null, "ID %s 的 get_texture 绝不能返回 null" % String(iid))
		if tex == null:
			continue
		var path := EquipmentIcons.icon_path(iid)
		if ResourceLoader.exists(path):
			_expect(tex.resource_path == path,
				"ID %s 应加载本 ID 真实路径 %s，实际 %s（禁兜底通过）" % [String(iid), path, tex.resource_path])
			_expect(tex == EquipmentIcons.get_texture(iid), "ID %s 缓存应返回同实例" % String(iid))
		else:
			_expect(tex == emergency,
				"ID %s 资产未入库时应回退应急纹理（LibTV 生成前的可见占位）" % String(iid))
	# 未知 ID：回退默认图标纹理（非 null）
	var unknown: Texture2D = EquipmentIcons.get_texture(&"99")
	_expect(unknown != null, "未知 ID 也绝不能返回 null")
	_expect(unknown == EquipmentIcons.get_texture(EquipmentIcons.DEFAULT_ICON_ID),
		"未知 ID 应回退默认图标纹理")
	_reset_catalog_state()


## ④隔离缝：_load_hook 模拟全部加载失败→全部 ID 返回非 null 应急纹理且同实例；
## 缝复位后恢复正常加载路径。静态目录状态必须在缝前后重置，避免污染。
func _run_load_hook_seam() -> void:
	_reset_catalog_state()
	EquipmentIcons._load_hook = func(_path: String) -> Texture2D:
		return null
	var emergency: Texture2D = EquipmentIcons._emergency_texture()
	for iid: StringName in EquipmentIcons.ICON_LIST:
		var tex: Texture2D = EquipmentIcons.get_texture(iid)
		_expect(tex != null, "全缺资产时 ID %s 仍应返回非 null 应急纹理" % String(iid))
		_expect(tex == emergency, "全缺资产时 ID %s 应返回同实例应急纹理" % String(iid))
	EquipmentIcons._load_hook = Callable()
	_reset_catalog_state()


## 重置目录静态状态（缓存/告警去重），保证各阶段互不污染。
func _reset_catalog_state() -> void:
	EquipmentIcons._cache = {}
	EquipmentIcons._warned = {}
