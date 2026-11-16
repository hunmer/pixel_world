## ecology_logic_bench_contract.gd — 生态解析纯逻辑基准契约
##
## 1) 基准可运行且结果合理（catalog 非空、命中数>0、吞吐在宽松上限内）；
## 2) 基准自身确定：同规模两次运行 checksum 必须一致；
## 3) 规模放大不劣化（4096 的单次耗时不比 512 大一个数量级）。
## 性能上限刻意放宽（2ms/resolve），这是基准台账不是硬性 SLA；
## 回归观察以 docs/test_automation_results.md 的记录为准。

extends SceneTree

const EcologyLogicBench := preload("res://tests/benches/ecology_logic_bench.gd")

const SMALL_SIZE := 512
const LARGE_SIZE := 4096
const US_PER_RESOLVE_CEILING := 2000.0
const SCALE_DEGRADE_FACTOR := 10.0

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var first: Dictionary = EcologyLogicBench.run(SMALL_SIZE)
	if first.has("error"):
		push_error(String(first["error"]))
		quit(1)
		return
	_report("small_1st", first)

	var second: Dictionary = EcologyLogicBench.run(SMALL_SIZE)
	_report("small_2nd", second)
	var large: Dictionary = EcologyLogicBench.run(LARGE_SIZE)
	_report("large", large)

	# 1) 合理性
	_expect(int(first["biome_count"]) > 0, "catalog biome 为空，基准没有吃到真实数据")
	_expect(int(first["community_count"]) > 0, "catalog community 为空，基准没有吃到真实数据")
	_expect(int(first["non_empty_hits"]) > 0, "全部 resolve 未命中任何 community，配方表失效")
	_expect(
		float(first["us_per_resolve"]) < US_PER_RESOLVE_CEILING,
		"单次 resolve 耗时 %.1fus 超过放宽上限 %.0fus" % [float(first["us_per_resolve"]), US_PER_RESOLVE_CEILING]
	)
	# 2) 确定性（同规模两次 checksum 一致）
	_expect(
		int(first["checksum"]) == int(second["checksum"]),
		"基准不确定：同规模两次 checksum 不一致（%d != %d）" % [int(first["checksum"]), int(second["checksum"])]
	)
	# 3) 规模放大不劣化一个数量级
	_expect(
		float(large["us_per_resolve"]) < float(first["us_per_resolve"]) * SCALE_DEGRADE_FACTOR,
		"规模放大劣化：4096 的单次耗时 %.1fus 超过 512 的 %.1fus × %.0f"
		% [float(large["us_per_resolve"]), float(first["us_per_resolve"]), SCALE_DEGRADE_FACTOR]
	)

	if not failures.is_empty():
		for failure: String in failures:
			push_error(failure)
		quit(1)
		return
	print("ECOLOGY_LOGIC_BENCH_CONTRACT_OK")
	quit(0)


func _report(label: String, result: Dictionary) -> void:
	print(
		"BENCH|ecology_logic|%s|iterations=%d|us_per_resolve=%.1f|checksum=%d|non_empty=%d"
		% [
			label,
			int(result["iterations"]),
			float(result["us_per_resolve"]),
			int(result["checksum"]),
			int(result["non_empty_hits"]),
		]
	)
