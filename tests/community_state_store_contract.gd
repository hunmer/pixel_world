extends SceneTree

const CommunityStateStore = preload("res://scripts/ecology/community_state_store.gd")

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_infinite_exploration_stays_bounded()
	_test_access_refreshes_lru()
	_test_live_groups_are_not_evicted()
	_test_values_are_not_rewritten()
	_test_clear_resets_everything()

	if failures.is_empty():
		print("COMMUNITY_STATE_STORE_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_infinite_exploration_stays_bounded() -> void:
	var store := CommunityStateStore.new(32)
	for index in 10000:
		store.set_or_put("group-%d" % index, {"seed": index})
	_expect(store.size() == 32, "无限探索后 CommunityStateStore 没有保持容量上限")
	_expect(not store.has("group-0"), "无限探索没有淘汰最旧群落")
	_expect(store.has("group-9999"), "无限探索错误淘汰了最新群落")


func _test_access_refreshes_lru() -> void:
	var store := CommunityStateStore.new(3)
	store.set_or_put("a", {"seed": 1})
	store.set_or_put("b", {"seed": 2})
	store["c"] = {"seed": 3}
	_expect(store["c"]["seed"] == 3, "Dictionary-like bracket 读写没有生效")
	_expect(store.get("a")["seed"] == 1, "get 没有返回缓存值")
	store.set_or_put("d", {"seed": 4})
	_expect(store.has("a"), "读取没有刷新 LRU，刚访问的 a 被淘汰")
	_expect(not store.has("b"), "LRU 没有淘汰最久未访问的 b")
	_expect(store.touch("c"), "touch 对存在群落返回失败")
	store.set_or_put("e", {"seed": 5})
	_expect(store.has("c"), "touch 没有刷新群落的 LRU")
	_expect(not store.has("a"), "touch 后没有淘汰真正最旧的 a")
	_expect(not store.touch("missing"), "touch 对缺失群落错误返回成功")


func _test_live_groups_are_not_evicted() -> void:
	var store := CommunityStateStore.new(2)
	store.set_or_put("pinned-a", {"seed": 10}, true)
	store.set_or_put("pinned-b", {"seed": 11}, true)
	# Atomic pinning lets all-live state safely exceed the cache budget.
	store.set_or_put("pinned-c", {"seed": 12}, true)
	_expect(store.size() == 3, "全 pinned 群落不应为满足缓存上限而被淘汰")
	_expect(store.pin_count("pinned-c") == 1, "原子 pin 没有记录 pin count")
	store.unpin("pinned-a")
	_expect(store.size() == 2, "unpin 后没有重新收缩到上限")
	_expect(not store.has("pinned-a"), "unpin 后没有淘汰唯一 inactive 群落")

	var active_store := CommunityStateStore.new(2)
	active_store.set_or_put("active", {"seed": 20}, false, 3)
	active_store.set_or_put("idle-old", {"seed": 21})
	active_store.set_or_put("idle-new", {"seed": 22})
	_expect(active_store.has("active"), "含 active member 的群落被淘汰")
	_expect(not active_store.has("idle-old"), "active 群落存在时没有淘汰最旧 inactive 群落")
	_expect(active_store.active_member_count("active") == 3, "active member 数量记录错误")
	active_store.decrement_active_members("active", 2)
	_expect(active_store.active_member_count("active") == 1, "active member 递减错误")
	active_store.set_active_members("active", 0)
	active_store.max_entries = 1
	_expect(active_store.size() == 1, "active members 清零后没有允许 LRU 收缩")
	_expect(active_store.has("active"), "刚更新 active 状态的群落没有获得最新 LRU 顺序")


func _test_values_are_not_rewritten() -> void:
	var store := CommunityStateStore.new(4)
	var deterministic_plan := {
		"anchor": Vector2i(7, -3),
		"members": [{"species": "wolf", "origin": Vector2i(7, -3)}],
	}
	var expected := deterministic_plan.duplicate(true)
	store.set_or_put("wolf-pack", deterministic_plan)
	store.pin("wolf-pack")
	store.touch("wolf-pack")
	store.set_active_member_count("wolf-pack", 1)
	_expect(store.get("wolf-pack") == expected, "LRU/active 元数据改写了确定性群落数据")
	_expect(not deterministic_plan.has("last_access"), "LRU 元数据泄漏进原始群落 Dictionary")
	_expect(not deterministic_plan.has("pin_count"), "pin 元数据泄漏进原始群落 Dictionary")


func _test_clear_resets_everything() -> void:
	var store := CommunityStateStore.new(2)
	store.set_or_put("pinned", {"seed": 1}, true)
	store.set_or_put("active", {"seed": 2}, false, 2)
	store.clear()
	_expect(store.size() == 0, "clear 没有清空 values")
	_expect(store.keys().is_empty(), "clear 后 keys 仍非空")
	_expect(not store.has("pinned"), "clear 后 pinned 群落仍存在")
	_expect(store.pin_count("pinned") == 0, "clear 没有清空 pin 元数据")
	_expect(store.active_member_count("active") == 0, "clear 没有清空 active 元数据")
	_expect(store.get_value("missing", "fallback") == "fallback", "get 缺失默认值行为错误")
