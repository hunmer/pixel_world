## tests/skill_icons_contract.gd — 技能图标目录与绑定契约
## 覆盖：①目录形状（"01".."53" 数字字符串稳定 ID、显式 ID→路径映射、非法输入拒绝）
## ②绑定完整性（skills.json 8 技能 iconId 与约定绑定表一致、互异，经 SkillData 规范化可查）
## ③纹理性（53 个文件全部存在，每个 ID 加载到本 ID 真实路径的 64x64 纹理，不得以兜底通过；
##   get_texture 缓存同实例；未知 iconId 回退默认图标并告警）
## ④skill_icon 链路（每技能非 null 且等于其 iconId 纹理；未知技能必须 null）
## ⑤战斗数值不动（iconId 为纯新增字段，锁定 8 技能关键结算数值基线）
## 运行：godot --headless --path . --script res://tests/skill_icons_contract.gd
extends SceneTree

## 技能 id → iconId 的稳定绑定表，防止既有绑定漂移。
const EXPECTED_BINDINGS := {
	&"fireball": &"11",
	&"smite": &"37",
	&"heal": &"32",
	&"blizzard": &"31",
	&"powerSurge": &"51",
	&"guard": &"52",
	&"weaken": &"46",
	&"haste": &"53",
}

var failures := 0


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
	_run_textures()
	_run_skill_icon_chain()
	_run_battle_values_untouched()
	if failures == 0:
		print("SKILL_ICONS_CONTRACT_OK")
	else:
		printerr("SKILL_ICONS_CONTRACT_FAILED: %d 处失败" % failures)
	quit(0 if failures == 0 else 1)


## ①目录形状：53 个数字字符串 ID、逐条路径与显式映射一致、非法 ID 拒绝。
func _run_catalog_shape() -> void:
	var paths: Dictionary = SkillIcons.ICON_PATHS
	var ids: Array = SkillIcons.ICON_LIST
	_expect(paths.size() == 53, "图标目录应为 53 项，实际 %d" % paths.size())
	_expect(ids.size() == 53, "ICON_LIST 应为 53 项，实际 %d" % ids.size())
	# 数字字符串 ID 完整集合："01".."53"，两位零填充
	for n in range(1, 54):
		var iid := StringName("%02d" % n)
		_expect(paths.has(iid), "目录缺少稳定 ID %s" % String(iid))
		_expect(ids.has(iid), "ICON_LIST 缺少 %s" % String(iid))
	# 51/52/53 指向语义命名文件（不得按编号拼路径）
	_expect(paths[&"51"] == "res://assets/ui/skills/power_surge.png", "51 应指向 power_surge.png，实际 %s" % paths[&"51"])
	_expect(paths[&"52"] == "res://assets/ui/skills/guard.png", "52 应指向 guard.png，实际 %s" % paths[&"52"])
	_expect(paths[&"53"] == "res://assets/ui/skills/haste.png", "53 应指向 haste.png，实际 %s" % paths[&"53"])
	# 01..50 指向数字命名文件（抽查首尾 + 全量在 ③ 的纹理段验证）
	_expect(paths[&"01"] == "res://assets/ui/skills/01.png", "01 路径错误: %s" % paths[&"01"])
	_expect(paths[&"50"] == "res://assets/ui/skills/50.png", "50 路径错误: %s" % paths[&"50"])
	# 非法 ID 拒绝
	for bad in [&"skill_01", &"1", &"54", &"00", &"junk", &""]:
		_expect(not SkillIcons.has_icon(bad), "非法 ID %s 不应在目录内" % String(bad))
		_expect(SkillIcons.icon_path(bad) == "", "非法 ID %s 路径应为空串" % String(bad))
	_expect(SkillIcons.has_icon(SkillIcons.DEFAULT_ICON_ID), "默认兜底图标必须在目录内")


## ②绑定完整性：8 技能 iconId 与约定表逐项一致且互异。
func _run_binding_integrity() -> void:
	var seen: Dictionary = {}
	var skills: Array = SkillData.SKILL_LIST
	_expect(skills.size() == EXPECTED_BINDINGS.size(), "技能数应为 %d，实际 %d" % [EXPECTED_BINDINGS.size(), skills.size()])
	for raw in skills:
		var sk: Dictionary = raw
		var sid: StringName = sk[&"id"]
		var icon_id: StringName = sk.get(&"iconId", &"")
		_expect(EXPECTED_BINDINGS.has(sid), "出现约定外技能 %s" % String(sid))
		_expect(icon_id == EXPECTED_BINDINGS.get(sid, &"<none>"),
			"%s 的 iconId 应为 %s，实际 %s" % [String(sid), String(EXPECTED_BINDINGS.get(sid, &"")), String(icon_id)])
		_expect(icon_id != &"" and SkillIcons.has_icon(icon_id),
			"%s 的 iconId %s 不在图标目录内" % [String(sid), String(icon_id)])
		_expect(not seen.has(icon_id), "iconId %s 被 %s 与 %s 重复绑定" % [
			String(icon_id), String(seen.get(icon_id, &"")), String(sid)])
		seen[icon_id] = sid


## ③纹理性：53 个文件全部存在；每个 ID 取到本 ID 真实路径的 64x64 纹理（不得以兜底通过）。
func _run_textures() -> void:
	for iid in SkillIcons.ICON_LIST:
		var path: String = SkillIcons.ICON_PATHS[iid]
		_expect(FileAccess.file_exists(path), "图标文件缺失: %s" % path)
		_expect(ResourceLoader.exists(path), "图标未导入不可加载: %s" % path)
		var tex: Texture2D = SkillIcons.get_texture(iid)
		_expect(tex != null, "%s 纹理为 null（不得以兜底通过）" % String(iid))
		if tex == null:
			continue
		# 必须来自本 ID 的真实路径（同路径 load 同实例），而非兜底纹理
		var direct: Texture2D = load(path) as Texture2D
		_expect(tex == direct, "%s 应加载自真实路径 %s，而非兜底纹理" % [String(iid), path])
		_expect(tex.get_size() == Vector2(64, 64),
			"%s 纹理应为 64x64，实际 %s" % [String(iid), tex.get_size()])
	# 缓存：同一 ID 返回同一实例（battle_ui_components 用 == 比较图标）
	var a: Texture2D = SkillIcons.get_texture(&"01")
	var b: Texture2D = SkillIcons.get_texture(&"01")
	_expect(a != null and a == b, "get_texture 同一 ID 应返回同一实例")
	# 未知 iconId：明确兜底（非 null、等于默认图标纹理）
	var fb: Texture2D = SkillIcons.get_texture(&"not_an_icon")
	_expect(fb != null and fb == SkillIcons.get_texture(SkillIcons.DEFAULT_ICON_ID),
		"未知 iconId 应回退默认图标（非 null 且同实例）")


## ④skill_icon 链路：每技能可取图标且等于其 iconId 纹理；未知技能必须 null。
func _run_skill_icon_chain() -> void:
	for raw in SkillData.SKILL_LIST:
		var sk: Dictionary = raw
		var sid: StringName = sk[&"id"]
		var tex: Texture2D = SkillData.skill_icon(sid)
		_expect(tex != null, "skill_icon(%s) 不应为 null" % String(sid))
		var expect_id: StringName = sk.get(&"iconId", &"")
		if expect_id != &"":
			_expect(tex == SkillIcons.get_texture(expect_id),
				"skill_icon(%s) 应等于其 iconId 纹理" % String(sid))
	_expect(SkillData.skill_icon(&"__no_such_skill__") == null, "未知技能 skill_icon 必须返回 null，不得回退默认技能图标")


## ⑤战斗数值不动：iconId 为纯新增字段，锁定 8 技能关键结算数值基线。
func _run_battle_values_untouched() -> void:
	var baseline := {
		&"fireball": {mpCost = 6, cooldown = 0, power = 10, hitBonus = 90, type = &"damage", element = &"fire"},
		&"smite": {mpCost = 4, cooldown = 1, power = 8, hitBonus = 95, type = &"damage", element = &"physical"},
		&"heal": {mpCost = 5, cooldown = 0, power = 15, type = &"heal", element = &"holy"},
		&"blizzard": {mpCost = 12, cooldown = 2, power = 7, hitBonus = 85, type = &"aoe", element = &"ice"},
		&"powerSurge": {mpCost = 4, cooldown = 3, stat = &"str", buffValue = 4, buffTurns = 3, type = &"buff", element = &"physical"},
		&"guard": {mpCost = 3, cooldown = 3, stat = &"def", buffValue = 5, buffTurns = 3, type = &"buff", element = &"physical"},
		&"weaken": {mpCost = 5, cooldown = 2, stat = &"def", buffValue = -4, buffTurns = 3, type = &"debuff", element = &"dark"},
		&"haste": {mpCost = 5, cooldown = 3, stat = &"spd", buffValue = 4, buffTurns = 3, type = &"buff", element = &"wind"},
	}
	for raw in SkillData.SKILL_LIST:
		var sk: Dictionary = raw
		var sid: StringName = sk[&"id"]
		var want: Dictionary = baseline.get(sid, {})
		for key in want:
			_expect(sk.get(key, null) == want[key],
				"%s.%s 战斗数值被改动：期望 %s 实际 %s" % [String(sid), String(key), str(want[key]), str(sk.get(key, null))])
	_expect(SkillData.SKILL_LIST.size() == baseline.size(), "技能数量不应变化（应仍为 8）")
