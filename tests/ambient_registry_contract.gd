extends SceneTree

const AmbientRegistry = preload("res://scripts/ecology/ambient_registry.gd")

const BUTTERFLY_RENDERER_PATH := (
	"res://tests/fixtures/unknown_butterfly_ambient_renderer.gd"
)
const INCOMPLETE_RENDERER_PATH := (
	"res://tests/fixtures/incomplete_ambient_renderer.gd"
)
const FIREFLY_ADAPTER_PATH := (
	"res://scripts/ecology/ambient_renderers/firefly_renderer_adapter.gd"
)

var failures: Array[String] = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _has_error(registry: Node, code: StringName, ambient_id: StringName = &"") -> bool:
	for error: Dictionary in registry.get_errors():
		if StringName(error.get("code", "")) != code:
			continue
		if ambient_id.is_empty() or StringName(error.get("ambient_id", "")) == ambient_id:
			return true
	return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := AmbientRegistry.new()
	registry.name = "AmbientRegistryContract"
	root.add_child(registry)

	# The Registry has no butterfly branch. Its script and profile are data.
	var butterfly_profile := {
		"wing_tint": "azure",
		"max_visible": 18,
	}
	var catalog := {
		# Alias comes first deliberately; catalog registration must be order-safe.
		"monarch": {
			"renderer_alias": "butterfly",
		},
		"butterfly": {
			"renderer_script": BUTTERFLY_RENDERER_PATH,
			"renderer_profile": butterfly_profile,
		},
		# Identical script + profile shares automatically without an alias.
		"swallowtail": {
			"renderer_script": BUTTERFLY_RENDERER_PATH,
			"renderer_profile": butterfly_profile.duplicate(true),
		},
	}
	_expect(registry.register_species_catalog(catalog), "未知蝴蝶 renderer catalog 注册失败")
	_expect(registry.has_species(&"butterfly"), "蝴蝶 ambient id 没有注册")
	_expect(registry.has_species(&"monarch"), "alias-only ambient id 没有注册")
	_expect(registry.has_species(&"swallowtail"), "共享 renderer 物种没有注册")
	_expect(registry.renderer_count() == 1, "相同 script/profile 创建了多个 renderer")
	_expect(
		registry.shares_renderer(&"butterfly", &"swallowtail"),
		"相同 script/profile 没有自动共享 renderer"
	)
	_expect(
		registry.shares_renderer(&"butterfly", &"monarch"),
		"renderer_alias 没有路由到目标 renderer"
	)
	var butterfly_renderer: Node = registry.get_renderer(&"butterfly")
	_expect(butterfly_renderer != null, "动态 renderer Script 没有实例化为 Node")
	_expect(
		butterfly_renderer.get("configured_profile") == butterfly_profile,
		"renderer profile 没有通过 configure 注入"
	)
	_expect(
		int(butterfly_renderer.get("configure_count")) == 1,
		"共享 renderer 被重复 configure"
	)

	var host := Node2D.new()
	host.name = "AmbientHost"
	root.add_child(host)
	_expect(
		registry.add_cluster(
			&"monarch",
			Vector2i(4, 7),
			host,
			Vector2(12.0, -5.0),
			5,
			12345
		),
		"add_cluster 没有按 ambient id 路由"
	)
	var clusters: Dictionary = butterfly_renderer.get("clusters")
	_expect(clusters.has(Vector2i(4, 7)), "自定义 renderer 没有收到 cluster")
	_expect(int(clusters[Vector2i(4, 7)]["count"]) == 5, "cluster 参数传递错误")
	_expect(registry.refresh_field(&"butterfly"), "refresh_field 路由失败")
	_expect(int(butterfly_renderer.get("refresh_count")) == 1, "refresh_field 未被调用")
	_expect(
		registry.set_environment_amount(&"swallowtail", 0.65),
		"set_environment_amount 路由失败"
	)
	_expect(
		is_equal_approx(float(butterfly_renderer.get("environment_amount")), 0.65),
		"环境量没有透传到 renderer"
	)
	_expect(
		registry.remove_cell(&"butterfly", Vector2i(4, 7)),
		"remove_cell 路由失败"
	)
	_expect(
		not (butterfly_renderer.get("clusters") as Dictionary).has(Vector2i(4, 7)),
		"remove_cell 未删除自定义 cluster"
	)
	_expect(registry.clear(&"monarch"), "clear 路由失败")
	_expect(int(butterfly_renderer.get("clear_count")) == 1, "clear 未被调用")

	# Broadcasts deduplicate renderer instances shared by several species IDs.
	var updates_before := int(butterfly_renderer.get("environment_update_count"))
	_expect(registry.set_all_environment_amount(0.25), "环境量广播失败")
	_expect(
		int(butterfly_renderer.get("environment_update_count")) == updates_before + 1,
		"共享 renderer 在一次广播中被重复调用"
	)
	var errors_before_optional_update := registry.get_errors().size()
	registry.update_observer_all(
		{"player_cell": Vector2i.ZERO, "viewport_size": Vector2(320.0, 180.0)},
		1.0 / 60.0
	)
	_expect(
		registry.get_errors().size() == errors_before_optional_update,
		"不需要观察者信息的 ambient renderer 被错误报告缺接口"
	)

	# Duplicate IDs, missing scripts, and requested missing interfaces are all
	# explicit contract errors rather than silent skips.
	_expect(
		not registry.register_species(
			&"butterfly",
			{"renderer_script": BUTTERFLY_RENDERER_PATH}
		),
		"重复 ambient id 被覆盖"
	)
	_expect(
		_has_error(registry, &"duplicate_ambient_id", &"butterfly"),
		"重复 ambient id 没有严格报告"
	)
	_expect(
		not registry.register_species(&"missing_visual", {}),
		"没有 renderer_script/alias 的定义仍被接受"
	)
	_expect(
		_has_error(registry, &"missing_renderer_script", &"missing_visual"),
		"缺脚本没有严格报告"
	)
	_expect(
		not registry.register_species(
			&"bad_path",
			{"renderer_script": "res://tests/fixtures/not_present.gd"}
		),
		"不存在的 renderer script 仍被接受"
	)
	_expect(
		_has_error(registry, &"missing_renderer_script", &"bad_path"),
		"不存在的 renderer script 没有严格报告"
	)
	_expect(
		registry.register_species(
			&"incomplete",
			{"renderer_script": INCOMPLETE_RENDERER_PATH}
		),
		"合法但接口较少的 renderer 无法注册"
	)
	_expect(
		not registry.refresh_field(&"incomplete"),
		"缺少 refresh_field 接口时被静默视为成功"
	)
	_expect(
		_has_error(registry, &"missing_renderer_interface", &"incomplete"),
		"缺接口没有严格报告"
	)

	# The adapter translates the generic environment amount and transparently
	# passes the existing FireflyField cluster API. Its ambient ID is arbitrary.
	var adapter_registry := AmbientRegistry.new()
	adapter_registry.name = "FireflyAdapterRegistry"
	root.add_child(adapter_registry)
	_expect(
		adapter_registry.register_species(
			&"night_glow_insect",
			{
				"renderer_script": FIREFLY_ADAPTER_PATH,
				"renderer_profile": {"max_visible": 4, "max_lights": 0},
			}
		),
		"Firefly adapter 动态注册失败"
	)
	var adapter: Node = adapter_registry.get_renderer(&"night_glow_insect")
	_expect(adapter != null, "Firefly adapter 没有实例化")
	_expect(
		adapter_registry.add_cluster(
			&"night_glow_insect",
			Vector2i(9, 3),
			host,
			Vector2.ZERO,
			2,
			9876
		),
		"Firefly adapter 没有透传 add_cluster"
	)
	_expect(int(adapter.call("get_registered_count")) == 1, "Firefly cluster 未注册")
	_expect(
		adapter_registry.set_environment_amount(&"night_glow_insect", 1.0),
		"Firefly adapter 没有接受通用环境量"
	)
	_expect(
		adapter_registry.refresh_field(&"night_glow_insect"),
		"Firefly adapter 没有透传 refresh_field"
	)
	_expect(int(adapter.call("get_active_count")) == 2, "通用环境量没有激活萤火虫")
	_expect(
		adapter_registry.remove_cell(&"night_glow_insect", Vector2i(9, 3)),
		"Firefly adapter 没有透传 remove_cell"
	)
	_expect(int(adapter.call("get_registered_count")) == 0, "萤火虫 cell 未移除")

	registry.queue_free()
	adapter_registry.queue_free()
	host.queue_free()

	if failures.is_empty():
		print("AMBIENT_REGISTRY_CONTRACT_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
