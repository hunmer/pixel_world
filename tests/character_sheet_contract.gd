## tests/character_sheet_contract.gd — 8 职业角色精灵图（CharacterSheet）素材与解析契约
##
## 校验：sheet 存在性与 2304×288 尺寸、8 帧 region、manifest 一致性、
## 内容底边 y=284（脚底锚点 FEET_FROM_CENTER_PX=140 的事实基础）、
## resolve_facing / pose_frame / pose_flip 纯逻辑朝向规则。
## 运行：godot --headless --path . --script res://tests/character_sheet_contract.gd
extends SceneTree

const CLASSES: Array[StringName] = [
	&"archer", &"assassin", &"berserker", &"knight",
	&"lancer", &"mage", &"priest", &"swordsman",
]

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _content_bounds(image: Image) -> Rect2i:
	# 返回内容包围盒（alpha>13 视为内容）；空图返回负尺寸 Rect2i。
	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a8 > 13:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i(0, 0, -1, -1)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _run() -> void:
	# 1) 8 张 sheet 存在且尺寸 2304×288（8 格 × 288）。
	for class_id in CLASSES:
		_expect(CharacterSheet.sheet_exists(class_id), "缺 sheet: %s" % class_id)
		var tex := CharacterSheet.sheet_texture(class_id)
		if tex == null:
			continue
		_expect(tex.get_width() == 2304 and tex.get_height() == 288,
			"%s sheet 尺寸 %dx%d != 2304x288" % [class_id, tex.get_width(), tex.get_height()])

	# 2) 帧 region 与缓存一致性。
	for class_id in CLASSES:
		for frame in range(CharacterSheet.FRAME_ORDER.size()):
			var atlas := CharacterSheet.frame_texture(class_id, frame)
			_expect(atlas != null, "%s 帧 %d 加载失败" % [class_id, frame])
			if atlas == null:
				continue
			_expect(atlas.region == Rect2(frame * 288, 0, 288, 288),
				"%s 帧 %d region 错误: %s" % [class_id, frame, atlas.region])
			_expect(atlas.filter_clip, "%s 帧 %d filter_clip 应为 true（最近邻不越界采样）" % [class_id, frame])
		_expect(CharacterSheet.frame_texture(class_id, 0) == CharacterSheet.frame_texture(class_id, 0),
			"%s 帧缓存应复用同一 AtlasTexture" % class_id)

	# 3) AtlasTexture.get_image() 行为实测（血条 _visible_top_world 依赖）。
	var probe := CharacterSheet.frame_texture(&"swordsman", 0)
	var probe_image := probe.get_image()
	_expect(probe_image != null and not probe_image.is_empty(),
		"swordsman front AtlasTexture.get_image() 为空")
	if probe_image != null and not probe_image.is_empty():
		print("[character_sheet] AtlasTexture.get_image() size=%dx%d" % [
			probe_image.get_width(), probe_image.get_height()])
		if probe_image.get_width() == 2304:
			push_warning("AtlasTexture.get_image() 返回整图 2304 宽，_visible_top_world 需按 region 裁剪")
		else:
			_expect(probe_image.get_width() == 288, "AtlasTexture.get_image() 宽度 %d != 288" % probe_image.get_width())

	# 4) 内容底边 y=284（脚底锚点事实；alpha=1 的抗锯齿尾迹行视为内容边缘）+ 站姿内容高 218~239。
	for class_id in CLASSES:
		var image := CharacterSheet.frame_texture(class_id, CharacterSheet.FRAME_FRONT).get_image()
		if image == null or image.is_empty():
			continue
		var bounds := _content_bounds(image)
		_expect(bounds.size.y > 0, "%s front 帧无内容" % class_id)
		if bounds.size.y <= 0:
			continue
		var bottom_edge := 0
		for y in range(image.get_height() - 1, -1, -1):
			var has_alpha := false
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a8 > 0:
					has_alpha = true
					break
			if has_alpha:
				bottom_edge = y + 1
				break
		_expect(bottom_edge == 284, "%s front 内容底边 y=%d != 284" % [class_id, bottom_edge])
		_expect(bounds.size.y >= 218 and bounds.size.y <= 239,
			"%s front 内容高 %d 超出 218~239" % [class_id, bounds.size.y])

	# 5) 纯逻辑朝向规则（等距约定：dx/dy 同号=朝向/远离相机轴 → front/back；
	#    异号=横切轴 → side+镜像。4 向网格移动在 45° 族 yaw 下恒为对角位移，
	#    最近主轴量化会恒 side，必须按符号分开两条对角轴）。
	# 映射表（yaw=PI/4 运行时实测）：E(+x)=(+,+)→front、W(-x)=(-,-)→back、
	# S(+z)=(-,+)→side 不翻、N(-z)=(+,-)→side flip。
	var diag_down_right := CharacterSheet.resolve_facing(Vector2(10, 4))  # 朝向相机对角
	_expect(diag_down_right[&"frame"] == CharacterSheet.FRAME_FRONT and diag_down_right[&"flip"] == false,
		"resolve_facing(朝相机对角 +,+) 应 front 不翻转")
	var diag_up_left := CharacterSheet.resolve_facing(Vector2(-10, -4))  # 远离相机对角
	_expect(diag_up_left[&"frame"] == CharacterSheet.FRAME_BACK and diag_up_left[&"flip"] == false,
		"resolve_facing(离相机对角 -,-) 应 back 不翻转")
	var diag_up_right := CharacterSheet.resolve_facing(Vector2(10, -4))  # 横切对角
	_expect(diag_up_right[&"frame"] == CharacterSheet.FRAME_SIDE and diag_up_right[&"flip"] == true,
		"resolve_facing(横切对角 +,-) 应 side+flip")
	var diag_down_left := CharacterSheet.resolve_facing(Vector2(-10, 4))  # 横切对角
	_expect(diag_down_left[&"frame"] == CharacterSheet.FRAME_SIDE and diag_down_left[&"flip"] == false,
		"resolve_facing(横切对角 -,+) 应 side 不翻转")
	# 退化（纯屏幕主轴，对角世界朝向/未来 8 向移动）：dy≈0→side；dx≈0→front/back。
	_expect(CharacterSheet.resolve_facing(Vector2(10, 0))[&"frame"] == CharacterSheet.FRAME_SIDE,
		"resolve_facing(纯右) 应 side")
	_expect(CharacterSheet.resolve_facing(Vector2(0, 10))[&"frame"] == CharacterSheet.FRAME_FRONT,
		"resolve_facing(纯下) 应 front")
	_expect(CharacterSheet.resolve_facing(Vector2(0, -10))[&"frame"] == CharacterSheet.FRAME_BACK,
		"resolve_facing(纯上) 应 back")

	# 5b) resolve_pose：idle=三视图解析；run 在朝向/远离相机轴必须用 front/back 帧
	# （不得用固定 side run 帧覆盖三视图），横切轴用 run 帧+镜像；attack/hurt/downed 单帧+镜像。
	var run_front := CharacterSheet.resolve_pose(CharacterSheet.POSE_RUN, Vector2(10, 4))
	_expect(run_front[&"frame"] == CharacterSheet.FRAME_FRONT and run_front[&"flip"] == false,
		"resolve_pose(run,朝相机) 应用 front 帧而非 side run 帧")
	var run_back := CharacterSheet.resolve_pose(CharacterSheet.POSE_RUN, Vector2(-10, -4))
	_expect(run_back[&"frame"] == CharacterSheet.FRAME_BACK and run_back[&"flip"] == false,
		"resolve_pose(run,离相机) 应用 back 帧而非 side run 帧")
	var run_side_r := CharacterSheet.resolve_pose(CharacterSheet.POSE_RUN, Vector2(10, -4))
	_expect(run_side_r[&"frame"] == CharacterSheet.FRAME_RUN and run_side_r[&"flip"] == false,
		"resolve_pose(run,横切右) 应用 run 帧不翻转（原图朝右）")
	var run_side_l := CharacterSheet.resolve_pose(CharacterSheet.POSE_RUN, Vector2(-10, 4))
	_expect(run_side_l[&"frame"] == CharacterSheet.FRAME_RUN and run_side_l[&"flip"] == true,
		"resolve_pose(run,横切左) 应用 run 帧翻转")
	var idle_same := CharacterSheet.resolve_pose(CharacterSheet.POSE_IDLE, Vector2(10, 4))
	_expect(idle_same[&"frame"] == CharacterSheet.FRAME_FRONT,
		"resolve_pose(idle) 应与 resolve_facing 一致")
	var attack_pose := CharacterSheet.resolve_pose(CharacterSheet.POSE_ATTACK, Vector2(10, -4))
	_expect(attack_pose[&"frame"] == CharacterSheet.FRAME_ATTACK and attack_pose[&"flip"] == true,
		"resolve_pose(attack,右) 应 attack 帧+flip")

	# 6) 姿态帧与镜像规则（8 职业一致：side/attack/hurt 朝左，run/downed 朝右）。
	_expect(CharacterSheet.pose_frame(CharacterSheet.POSE_RUN) == CharacterSheet.FRAME_RUN, "pose_frame(run)")
	_expect(CharacterSheet.pose_frame(CharacterSheet.POSE_ATTACK) == CharacterSheet.FRAME_ATTACK, "pose_frame(attack)")
	_expect(CharacterSheet.pose_frame(CharacterSheet.POSE_HURT) == CharacterSheet.FRAME_HURT, "pose_frame(hurt)")
	_expect(CharacterSheet.pose_frame(CharacterSheet.POSE_DOWNED) == CharacterSheet.FRAME_DOWNED, "pose_frame(downed)")
	_expect(CharacterSheet.pose_flip(CharacterSheet.POSE_RUN, 5.0) == false, "run 朝右：dx>0 不翻转")
	_expect(CharacterSheet.pose_flip(CharacterSheet.POSE_RUN, -5.0) == true, "run 朝右：dx<0 翻转")
	_expect(CharacterSheet.pose_flip(CharacterSheet.POSE_ATTACK, 5.0) == true, "attack 朝左：dx>0 翻转")
	_expect(CharacterSheet.pose_flip(CharacterSheet.POSE_HURT, -5.0) == false, "hurt 朝左：dx<0 不翻转")
	_expect(CharacterSheet.pose_flip(CharacterSheet.POSE_DOWNED, -5.0) == true, "downed 头朝右：dx<0 翻转")
	_expect(CharacterSheet.pose_flip(CharacterSheet.POSE_IDLE, 5.0) == false, "idle 不走路径镜像")

	# 7) 尺度：1/224 像素尺寸与脚底偏移。
	_expect(is_equal_approx(CharacterSheet.pixel_size(), 1.0 / 224.0), "pixel_size 应为 1/224")
	_expect(CharacterSheet.FEET_FROM_CENTER_PX == 140.0, "FEET_FROM_CENTER_PX 应为 140")

	# 8) manifest 一致性：8 个文件、order 与 FRAME_ORDER 一致。
	var manifest := CharacterSheet.manifest()
	_expect(not manifest.is_empty(), "manifest.json 缺失或解析失败")
	if not manifest.is_empty():
		var files: Array = manifest.get("files", [])
		_expect(files.size() == 8, "manifest files 数量 %d != 8" % files.size())
		for entry_value in files:
			var entry: Dictionary = entry_value
			var class_id := StringName(entry.get("class", &""))
			_expect(CLASSES.has(class_id), "manifest 未知职业: %s" % class_id)
			var order: Array = entry.get("order", [])
			var order_names: Array[StringName] = []
			for frame_name in order:
				order_names.append(StringName(frame_name))
			_expect(order_names == CharacterSheet.FRAME_ORDER, "%s order 与 FRAME_ORDER 不一致" % class_id)
			_expect(ResourceLoader.exists("res://%s" % entry.get("out", "")), "%s out 不存在: %s" % [class_id, entry.get("out", "")])

	if failures > 0:
		push_error("character_sheet_contract: %d 项失败" % failures)
		quit(1)
	else:
		print("character_sheet_contract: OK")
		quit(0)
