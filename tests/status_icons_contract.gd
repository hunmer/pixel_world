## tests/status_icons_contract.gd — 状态图标目录与头顶状态行契约
## 覆盖：
## ①目录形状：6 个稳定 ID 显式映射 res://assets/ui/status/<id>.png，非法 ID 拒绝
## ②真实技能四状态：SkillSystem.execute 走 data/skills.json 真实技能
##   powerSurge/guard/weaken/haste → buff 落地（unit.buffs + result.buffed.status）、
##   图标映射 str+/def+/def-/spd+ → power_up/defense_up/defense_down/speed_up、
##   effective_stat 生效、结算数值基线锁定
## ③BuffSystem 生命周期与映射兜底：同 stat+label 刷新、不同 label 叠加、
##   tick 递减/到期移除、cleanse 移除负数；未知属性通用 buff/debuff 兜底；
##   零值/到期/旧字典（缺字段、String 键）过滤且不崩
## ④头顶节点（headless Node3D）：槽位数量/顺序/签名、素材缺失槽位隐藏、
##   数字文本与右下角右对齐补偿、头顶锚点、hover 指针避让不重叠、
##   重复 update_state 不重建节点、tick 到期/cleanse 后槽位回收、
##   fade_alpha 淡出联动、显示尺寸按纹理宽度归一（native 64px 恒显 20px）、
##   屏幕空间排布在等距 4 正交相机角下 offset/position 不变、
##   battle_result_stage 递归捕获 restore 复原、死亡清理不残留
## ⑤素材纹理性：6 文件齐全时 64×64 正方形（当前规格）、缓存同实例；
##   显示尺寸由 STATUS_ICON_SIZE_PX 归一，素材规格变更须随断言更新
## 运行：godot --headless --path . --script res://tests/status_icons_contract.gd
extends SceneTree

## 四个真实状态技能的结算数值基线（data/skills.json 现值，防映射契约依赖漂移）。
const SKILL_BASELINE := {
	&"powerSurge": {stat = &"str", buffValue = 4, buffTurns = 3, mpCost = 4},
	&"guard": {stat = &"def", buffValue = 5, buffTurns = 3, mpCost = 3},
	&"weaken": {stat = &"def", buffValue = -4, buffTurns = 3, mpCost = 5},
	&"haste": {stat = &"spd", buffValue = 4, buffTurns = 3, mpCost = 5},
}

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)


func _make_unit(id: StringName) -> Dictionary:
	return {
		"id": id,
		"classId": &"status_contract_unit",  # 无立绘素材 → 走 _VISIBLE_TOP_FALLBACK 确定性头顶
		"faction": &"player",
		"stats": {hp = 20, str = 8, def = 5, spd = 6, mag = 7, skl = 5, luk = 4, res = 3, mov = 4},
		"hp": 20,
		"mp": 40,
		"position": Vector2i(1, 1),
		"buffs": [],
		"skillCooldowns": {},
		"hasActed": false,
		"isDead": false,
	}


func _run() -> void:
	_run_catalog_shape()
	_run_real_skills()
	_run_buff_lifecycle()
	await _run_head_badges()
	_run_textures()
	if failures == 0:
		print("STATUS_ICONS_CONTRACT_OK")
	else:
		printerr("STATUS_ICONS_CONTRACT_FAILED: %d 处失败" % failures)
	quit(0 if failures == 0 else 1)


## ①目录形状：6 个稳定 ID、显式路径、非法 ID 拒绝。
func _run_catalog_shape() -> void:
	var paths: Dictionary = StatusIcons.ICON_PATHS
	_expect(paths.size() == 6, "状态图标目录应为 6 项，实际 %d" % paths.size())
	var expected := {
		&"power_up": "res://assets/ui/status/power_up.png",
		&"defense_up": "res://assets/ui/status/defense_up.png",
		&"speed_up": "res://assets/ui/status/speed_up.png",
		&"defense_down": "res://assets/ui/status/defense_down.png",
		&"buff": "res://assets/ui/status/buff.png",
		&"debuff": "res://assets/ui/status/debuff.png",
	}
	for iid in expected:
		_expect(String(paths.get(iid, "")) == expected[iid],
			"稳定 ID %s 路径错误：%s" % [String(iid), String(paths.get(iid, ""))])
	_expect(StatusIcons.ICON_LIST.size() == 6, "ICON_LIST 应为 6 项，实际 %d" % StatusIcons.ICON_LIST.size())
	for iid in expected:
		_expect(StatusIcons.has_icon(iid), "目录缺少稳定 ID %s" % String(iid))
	for bad in [&"powerup", &"attack_up", &"attack_down", &"status/power_up", &"01", &""]:
		_expect(not StatusIcons.has_icon(bad), "非法 ID %s 不应在目录内" % String(bad))
		_expect(StatusIcons.icon_path(bad) == "", "非法 ID %s 路径应为空串" % String(bad))
	# 未知 ID 安全处理：不崩、返回 null（不伪装成功）。
	_expect(StatusIcons.get_texture(&"not_an_icon") == null, "未知 ID 应返回 null 而非兜底纹理")


## ②真实技能四状态：execute 走真实技能 JSON，buff 落地与图标映射一一对应。
func _run_real_skills() -> void:
	# 数值基线：状态映射契约依赖的结算数值不得漂移。
	for raw in SkillData.SKILL_LIST:
		var sk: Dictionary = raw
		var sid: StringName = sk[&"id"]
		if not SKILL_BASELINE.has(sid):
			continue
		var want: Dictionary = SKILL_BASELINE[sid]
		for key in want:
			_expect(sk.get(key, null) == want[key],
				"%s.%s 结算数值漂移：期望 %s 实际 %s" % [String(sid), String(key), str(want[key]), str(sk.get(key, null))])
	var u := _make_unit(&"skill_unit")
	var order: Array = []
	for sid in [&"powerSurge", &"guard", &"weaken", &"haste"]:
		var result: Dictionary = SkillSystem.execute(u, [u], sid)
		_expect(not result.is_empty(), "%s execute 不应返回空" % String(sid))
		_expect(result.get(&"buffed", []).size() == 1, "%s 应有 1 个受术目标" % String(sid))
		if result.get(&"buffed", []).is_empty():
			continue
		var status: Dictionary = result[&"buffed"][0][&"status"]
		order.append(status)
		_expect(status[&"stat"] == SKILL_BASELINE[sid][&"stat"] and status[&"value"] == SKILL_BASELINE[sid][&"buffValue"],
			"%s 落地 status 与技能定义不一致：%s" % [String(sid), str(status)])
	_expect(int(u[&"mp"]) == 40 - 4 - 3 - 5 - 5, "四技能 MP 扣除错误，实际 %d" % int(u[&"mp"]))
	var buffs: Array = u[&"buffs"]
	_expect(buffs.size() == 4, "四技能应叠加 4 条 buff（label 互异），实际 %d" % buffs.size())
	# guard(+def) 与 weaken(-def) 同属性不同方向不同 label：并存且各占一槽。
	var icon_expect := [&"power_up", &"defense_up", &"defense_down", &"speed_up"]
	for i in range(mini(buffs.size(), 4)):
		_expect(StatusIcons.icon_id_for_buff(buffs[i]) == icon_expect[i],
			"buff[%d]（%s）应映射 %s，实际 %s" % [i, String(buffs[i][&"label"]), String(icon_expect[i]), String(StatusIcons.icon_id_for_buff(buffs[i]))])
	# 映射不影响结算：effective_stat 仍按 BuffSystem 累计。
	_expect(SkillSystem.effective_stat(u, &"str") == 12, "str 应为 8+4=12")
	_expect(SkillSystem.effective_stat(u, &"def") == 6, "def 应为 5+5-4=6")
	_expect(SkillSystem.effective_stat(u, &"spd") == 10, "spd 应为 6+4=10")
	_expect(order.size() == 4, "四技能 status 顺序断言数据不足")


## ③BuffSystem 生命周期与映射兜底。
func _run_buff_lifecycle() -> void:
	var v := _make_unit(&"life_unit")
	# 同 stat+label：刷新时长并覆盖值，不新增条目。
	BuffSystem.apply_buff(v, &"str", 3, 2, "勇猛")
	BuffSystem.apply_buff(v, &"str", 5, 4, "勇猛")
	var buffs: Array = v[&"buffs"]
	_expect(buffs.size() == 1 and int(buffs[0][&"value"]) == 5 and int(buffs[0][&"turns"]) == 4,
		"同 stat+label 应刷新为 value=5/turns=4，实际 %s" % str(buffs))
	# 不同 label：叠加两条。
	BuffSystem.apply_buff(v, &"str", -2, 3, "衰弱")
	_expect((v[&"buffs"] as Array).size() == 2, "不同 label 应叠加为 2 条")
	# tick 递减；turns<=0 移除。
	BuffSystem.tick_buffs([v])
	buffs = v[&"buffs"]
	_expect(buffs.size() == 2 and int(buffs[0][&"turns"]) == 3 and int(buffs[1][&"turns"]) == 2,
		"tick 后 turns 应为 3/2，实际 %s" % str(buffs))
	v[&"isDead"] = false
	# 手工塞到期残留（旧档防御）：映射必须过滤。
	(v[&"buffs"] as Array).append({stat = &"spd", value = 4, turns = 0, label = "残留"})
	_expect(StatusIcons.icon_id_for_buff(v[&"buffs"][2]) == &"", "turns=0 的残留 buff 必须被映射过滤")
	# cleanse：移除负数保留正数。
	v[&"buffs"] = [
		{stat = &"str", value = 5, turns = 4, label = "勇猛"},
		{stat = &"str", value = -2, turns = 3, label = "衰弱"},
		{stat = &"luk", value = -1, turns = 2, label = "厄运"},
	]
	var removed := BuffSystem.cleanse_debuffs(v)
	_expect(removed == 2 and (v[&"buffs"] as Array).size() == 1, "cleanse 应移除 2 条负值保留 1 条正值")
	# 未知属性通用兜底。
	_expect(StatusIcons.icon_id_for_buff({stat = &"mag", value = 3, turns = 2, label = ""}) == &"buff",
		"未知正面属性 mag+ 应兜底 buff")
	_expect(StatusIcons.icon_id_for_buff({stat = &"luk", value = -2, turns = 2, label = ""}) == &"debuff",
		"未知负面属性 luk- 应兜底 debuff")
	# 零值/负零：过滤。
	_expect(StatusIcons.icon_id_for_buff({stat = &"str", value = 0, turns = 3, label = ""}) == &"",
		"value=0 必须被映射过滤")
	# 旧字典（缺字段/空字典/String 键）：不崩且安全过滤或正确映射。
	_expect(StatusIcons.icon_id_for_buff({}) == &"", "空字典应安全返回空 ID")
	_expect(StatusIcons.icon_id_for_buff({stat = &"str", value = 3}) == &"", "缺 turns 的旧字典应过滤")
	_expect(StatusIcons.icon_id_for_buff({stat = &"str", turns = 3}) == &"", "缺 value 的旧字典应过滤")
	var json_style := {"stat": "str", "value": 2, "turns": 2, "label": "存档"}
	_expect(StatusIcons.icon_id_for_buff(json_style) == &"power_up",
		"String 键/值的存档字典应与 StringName 等价映射")


## ④头顶状态行（headless Node3D 全链路）。
func _run_head_badges() -> void:
	var board := IsoBoard.new()
	root.add_child(board)
	await process_frame
	await process_frame
	var u := _make_unit(&"badge_unit")
	var sprite := UnitSprite3D.new()
	root.add_child(sprite)
	sprite.setup(u, board)
	var badges: UnitStatusBadges = sprite._status_badges
	_expect(badges != null, "UnitSprite3D 应创建状态行子模块")
	if badges == null:
		return
	# 无状态存活：零槽位、不渲染、单位可见。
	sprite.update_state()
	_expect(badges.slot_count() == 0, "无 buff 时槽位应为 0，实际 %d" % badges.slot_count())
	_expect(sprite.visible, "存活单位应可见")
	# hover 基准（无状态）：指针仍在 head_y+0.32 附近（±sin 波动 0.06）。
	sprite.set_hovered(true, false)
	await process_frame
	var head_y := sprite.get_head_y()
	_expect(sprite._hover_marker != null and absf(sprite._hover_marker.position.y - (head_y + 0.32)) <= 0.065,
		"无状态时 hover 指针应保持 head_y+0.32 原锚点，实际 %s" % str(sprite._hover_marker.position.y if sprite._hover_marker != null else -1.0))
	sprite.set_hovered(false)
	# 真实技能四状态挂头。
	for sid in [&"powerSurge", &"guard", &"weaken", &"haste"]:
		SkillSystem.execute(u, [u], sid)
	u[&"mp"] = 40
	sprite.update_state()
	_expect(badges.slot_count() == 4, "四状态应有 4 槽，实际 %d" % badges.slot_count())
	_expect(badges._signature == "power_up:3|defense_up:3|defense_down:3|speed_up:3|",
		"槽位顺序应按 buffs 数组映射，实际签名 %s" % badges._signature)
	for i in range(badges._labels.size()):
		_expect(badges._labels[i].text == "3", "槽 %d 剩余回合数字应为 3，实际 %s" % [i, badges._labels[i].text])
	# 头顶锚点：状态行中心在头顶之上。
	_expect(is_equal_approx(badges.position.y, badges.anchor_y(head_y)) and badges.position.y > head_y,
		"状态行锚点应在头顶上方，head_y=%s badges.y=%s" % [str(head_y), str(badges.position.y)])
	# hover 避让：指针抬到状态行上方，不与图标行重叠。
	var row_top := badges.top_world_y(head_y)
	sprite.set_hovered(true, false)
	await process_frame
	_expect(sprite._hover_marker.position.y >= row_top + 0.25,
		"有状态时 hover 指针应抬到状态行上方（行顶 %s），实际 %s" % [str(row_top), str(sprite._hover_marker.position.y)])
	sprite.set_hovered(false)
	# 屏幕空间布局基准：槽位节点 position 恒 ZERO，行内水平与数字右下全走 offset。
	var digit_pos := (badges._labels[1].position as Vector3)
	var center_px := (1.0 - 1.5) * (UnitStatusBadges.STATUS_ICON_SIZE_PX + UnitStatusBadges.STATUS_ICON_GAP_PX)
	_expect(digit_pos == Vector3.ZERO, "数字节点 position 应恒为 ZERO，实际 %s" % str(digit_pos))
	_expect(is_equal_approx((badges._labels[1].offset as Vector2).x, center_px + UnitStatusBadges.STATUS_DIGIT_ANCHOR_PX.x),
		"一位数 offset.x 应为 center+anchor=%s，实际 %s" % [str(center_px + UnitStatusBadges.STATUS_DIGIT_ANCHOR_PX.x), str((badges._labels[1].offset as Vector2).x)])
	# 检查引擎实际生成的文字网格，避免把 Label3D.offset 的 y 方向误当成二维坐标。
	await process_frame
	var text_mesh: TriangleMesh = badges._labels[1].generate_triangle_mesh()
	var points: PackedVector3Array = text_mesh.get_faces()
	var bounds_min: Vector3 = points[0]
	var bounds_max: Vector3 = points[0]
	for point: Vector3 in points:
		bounds_min = bounds_min.min(point)
		bounds_max = bounds_max.max(point)
	var text_center: Vector3 = (bounds_min + bounds_max) * 0.5
	_expect(text_center.y < 0.0 and text_center.x > center_px / 32.0,
		"文字网格中心必须在所属图标右下方（局部 +X/-Y），实际 %s" % str(text_center))
	# 同 label 刷新 turns=12：数字右缘补偿，节点位置不漂移。
	BuffSystem.apply_buff(u, &"def", 5, 12, "铁壁")
	sprite.update_state()
	_expect(badges._labels[1].text == "12", "刷新后防御槽数字应为 12，实际 %s" % badges._labels[1].text)
	_expect((badges._labels[1].position as Vector3) == digit_pos,
		"多位数数字节点 position 不得漂移（右缘补偿只动 offset）")
	_expect(is_equal_approx((badges._labels[1].offset as Vector2).x, center_px + UnitStatusBadges.STATUS_DIGIT_ANCHOR_PX.x - UnitStatusBadges.STATUS_DIGIT_W_PX * 0.5),
		"两位数 offset.x 应右缘补偿 -半个字宽，实际 %s" % str((badges._labels[1].offset as Vector2).x))
	# 素材装载与显示归一：native 64px 素材也恒定显示 20px（换算按纹理实际宽度）。
	var tex := StatusIcons.get_texture(&"power_up")
	if FileAccess.file_exists(StatusIcons.icon_path(&"power_up")):
		_expect(tex != null and badges._sprites[0].texture == tex, "素材存在时槽位应装载真实纹理")
		var tex_w := float(tex.get_width())
		_expect(is_equal_approx(badges._sprites[0].pixel_size, UnitStatusBadges.STATUS_ICON_SIZE_PX / (tex_w * 32.0)),
			"pixel_size 应按纹理宽度归一（20px 显示），实际 %s" % str(badges._sprites[0].pixel_size))
		_expect(is_equal_approx(badges._sprites[0].pixel_size * tex_w, 20.0 / 32.0),
			"图标 quad 世界宽应恒为 20/32≈0.625，实际 %s" % str(badges._sprites[0].pixel_size * tex_w))
		# 行内水平排布在屏幕空间：Sprite3D.offset 单位为纹理像素，换算 = 期望屏幕px × tex_w/20。
		var want_x := (0.0 - 1.5) * (UnitStatusBadges.STATUS_ICON_SIZE_PX + UnitStatusBadges.STATUS_ICON_GAP_PX) * tex_w / UnitStatusBadges.STATUS_ICON_SIZE_PX
		_expect(is_equal_approx((badges._sprites[0].offset as Vector2).x, want_x) and is_equal_approx((badges._sprites[0].offset as Vector2).y, 0.0),
			"槽 0 屏幕偏移应为 center×tex_w/20=%s，实际 %s" % [str(want_x), str(badges._sprites[0].offset)])
		_expect(badges._sprites[0].alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED,
			"图标必须 ALPHA_CUT_DISABLED（DISCARD 裁半透明像素会破坏 modulate 淡出）")
		for s in badges._sprites:
			_expect((s as Sprite3D).position == Vector3.ZERO, "屏幕空间布局：所有槽位节点 position 应恒为 ZERO")
	else:
		_expect(tex == null, "素材缺失时 get_texture 应返回 null")
		_expect(not badges._sprites[0].visible and not badges._labels[0].visible,
			"素材缺失时槽位应隐藏而非伪装")
	# 纹理宽度无关性：注入 24×24 临时纹理，显示尺寸与排布换算不随 native 尺寸漂移。
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	StatusIcons._cache[&"power_up"] = ImageTexture.create_from_image(img)
	u[&"buffs"][0][&"turns"] = 5  # 签名变化触发刷新（不重建节点）
	sprite.update_state()
	_expect(badges._sprites[0].texture == StatusIcons._cache[&"power_up"], "注入纹理后槽 0 应换装临时纹理")
	_expect(is_equal_approx(badges._sprites[0].pixel_size, 20.0 / (24.0 * 32.0)),
		"24px 纹理 pixel_size 应为 20/(24×32)，实际 %s" % str(badges._sprites[0].pixel_size))
	_expect(is_equal_approx((badges._sprites[0].offset as Vector2).x, -34.5 * 24.0 / 20.0),
		"24px 纹理 offset.x 应按 tex_w/20 换算，实际 %s" % str(badges._sprites[0].offset.x))
	StatusIcons.clear_cache()
	u[&"buffs"][0][&"turns"] = 3  # 还原并重载真实素材
	sprite.update_state()
	# 重复 update_state：不重建节点（同实例）。
	var ids := []
	for s in badges._sprites:
		ids.append(s.get_instance_id())
	sprite.update_state()
	for i in range(ids.size()):
		_expect(badges._sprites[i].get_instance_id() == ids[i], "状态未变时不得重建槽位节点")
	# 屏幕空间排布与相机角度无关：等距 4 正交角旋转下节点 position/offset 恒定
	# （世界轴布局在 90° 角会把行排成深度方向、数字脱离右下角）。
	var offsets := []
	for s in badges._sprites:
		offsets.append((s as Sprite3D).offset)
	for l in badges._labels:
		offsets.append((l as Label3D).offset)
	for k in 4:
		board.camera.rotation.y = PI * 0.25 + k * PI * 0.5
		await process_frame
		for i in range(badges._sprites.size()):
			_expect((badges._sprites[i] as Sprite3D).position == Vector3.ZERO,
				"相机角 %d 下槽位 position 不得偏离 ZERO（世界轴布局会排成深度）" % k)
			_expect((badges._sprites[i] as Sprite3D).offset == offsets[i],
				"相机角 %d 下槽位 offset 不得漂移" % k)
		for i in range(badges._labels.size()):
			_expect((badges._labels[i] as Label3D).offset == offsets[badges._sprites.size() + i],
				"相机角 %d 下数字 offset 不得漂移" % k)
	board.camera.rotation.y = PI * 0.25  # 还原默认角
	# tick 递减：数字跟随；到期：槽位回收。
	BuffSystem.apply_buff(u, &"def", 5, 12, "铁壁")  # 恢复已知 turns 基线
	u[&"buffs"][1][&"turns"] = 3
	BuffSystem.tick_buffs([u])
	sprite.update_state()
	_expect(badges._labels[1].text == "2", "tick 后防御槽数字应为 2，实际 %s" % badges._labels[1].text)
	u[&"buffs"] = [
		{stat = &"str", value = 5, turns = 2, label = "力量觉醒"},
		{stat = &"def", value = -4, turns = 2, label = "虚弱术"},
		{stat = &"luk", value = -1, turns = 2, label = "厄运"},
	]
	sprite.update_state()
	_expect(badges.slot_count() == 3, "三条有效 buff 应 3 槽，实际 %d" % badges.slot_count())
	BuffSystem.cleanse_debuffs(u)
	sprite.update_state()
	_expect(badges.slot_count() == 1 and badges._signature.begins_with("power_up:"),
		"cleanse 后仅剩正面槽位，实际 %d 槽 %s" % [badges.slot_count(), badges._signature])
	# 淡出联动：整行 alpha 跟随 fade_alpha（battle_result_stage 死亡淡出走此链）。
	sprite.fade_alpha(0.25)
	_expect(is_equal_approx(badges._sprites[0].modulate.a, 0.25) and is_equal_approx(badges._labels[0].modulate.a, 0.25),
		"fade_alpha(0.25) 应联动状态行，实际 %s/%s" % [str(badges._sprites[0].modulate.a), str(badges._labels[0].modulate.a)])
	_expect(is_equal_approx(badges._labels[0].outline_modulate.a, 0.25), "数字描边也应随淡出透明，不能留下黑色残影")
	sprite.fade_alpha(1.0)
	_expect(is_equal_approx(badges._sprites[0].modulate.a, 1.0), "fade_alpha(1.0) 应恢复状态行 alpha")
	# battle_result_stage 捕获面兼容：状态行必须是纯 Node3D 容器（非渲染原语），
	# 渲染节点只在其内部，递归捕获恢复 alpha 不与容器冲突。
	_expect(badges.get_class() == "Node3D",
		"状态行容器应保持纯 Node3D（非渲染原语），实际 %s" % badges.get_class())
	# battle_result_stage 递归捕获兼容：capture→fade→restore 后嵌套状态行 alpha 复原。
	var stage := BattleResultStage.new()
	root.add_child(stage)
	stage._capture_visual(sprite)
	sprite.fade_alpha(0.2)
	_expect(is_equal_approx(badges._sprites[0].modulate.a, 0.2), "fade 后状态行 alpha 应为 0.2，实际 %s" % str(badges._sprites[0].modulate.a))
	stage.restore()
	_expect(is_equal_approx(badges._sprites[0].modulate.a, 1.0) and is_equal_approx(badges._labels[0].modulate.a, 1.0),
		"restore 应把递归捕获的状态行节点 alpha 恢复为 1（跳过演出不留残影）")
	_expect(is_equal_approx(badges._labels[0].outline_modulate.a, 1.0) and is_equal_approx(badges._alpha, 1.0),
		"restore 应同时恢复数字描边和状态行后续新节点使用的 alpha")
	stage.queue_free()
	# 死亡：清理不残留，单位隐藏。
	u[&"isDead"] = true
	sprite.update_state()
	_expect(badges.slot_count() == 0, "死亡后状态行必须清空，实际 %d 槽" % badges.slot_count())
	_expect(not sprite.visible, "死亡单位应隐藏")
	board.queue_free()
	sprite.queue_free()
	await process_frame


## ⑤素材纹理性：齐全才验收；整体未就绪 SKIP；部分缺失失败。
func _run_textures() -> void:
	var missing: Array = []
	for iid in StatusIcons.ICON_LIST:
		var path: String = StatusIcons.icon_path(iid)
		if not FileAccess.file_exists(path):
			missing.append(path)
	if missing.size() == StatusIcons.ICON_LIST.size():
		print("STATUS_ICONS_TEXTURES_SKIPPED: 素材未就绪（等生成后 Lead 整合复跑）")
		return
	for path in missing:
		_expect(false, "状态图标素材部分缺失（不允半装）: %s" % path)
	for iid in StatusIcons.ICON_LIST:
		var path: String = StatusIcons.icon_path(iid)
		var tex: Texture2D = StatusIcons.get_texture(iid)
		_expect(tex != null, "%s 纹理为 null（素材存在但不可加载）" % path)
		if tex == null:
			continue
		_expect(tex == (load(path) as Texture2D), "%s 应加载自真实路径而非伪装" % path)
		var size := tex.get_size()
		_expect(size.x == size.y, "%s 应为正方形，实际 %s" % [path, str(size)])
		_expect(size.x == 64.0, "%s 应为 64×64（当前素材规格；显示由 STATUS_ICON_SIZE_PX 归一 20px，规格变更须随断言更新），实际 %s" % [path, str(size)])
	var a: Texture2D = StatusIcons.get_texture(&"buff")
	var b: Texture2D = StatusIcons.get_texture(&"buff")
	_expect(a != null and a == b, "get_texture 同一 ID 应返回同一缓存实例")
