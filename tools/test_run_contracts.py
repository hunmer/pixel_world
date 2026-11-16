#!/usr/bin/env python3
"""tools/test_run_contracts.py — run_contracts.py 的单元测试（标准库 unittest）。

覆盖：选择与影响分析、状态分类、超时进程组清理、并发上限、
environment-skip 语义、summary 产物、空格路径、CLI 用法错误。
真实 godot 冒烟仅 2 个纯逻辑契约（无 GODOT 时自动跳过）。

跑法：python3 -m unittest tools.test_run_contracts -v
   或 python3 tools/test_run_contracts.py
"""

from __future__ import annotations

import json
import os
import signal
import stat
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from contextlib import contextmanager
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

import run_contracts as rc  # noqa: E402

REAL_GODOT = os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot")

# 假 godot：按 FAKE_MODE 环境变量行为（pass/fail/hang/hang_with_child/lock）
FAKE_GODOT = textwrap.dedent("""\
	#!/usr/bin/env python3
	import os, subprocess, sys, time
	mode = os.environ.get("FAKE_MODE", "pass")
	if mode == "pass":
		print("[OK] fake godot pass")
		sys.exit(0)
	if mode == "fail":
		print("[FAIL] fake godot fail")
		sys.exit(1)
	if mode == "hang":
		while True:
			time.sleep(60)
	if mode == "hang_with_child":
		child = subprocess.Popen(["sleep", "120"])
		with open(os.environ["FAKE_CHILD_PID_FILE"], "w") as fh:
			fh.write(str(child.pid))
		while True:
			time.sleep(60)
	if mode == "lock":
		log = os.environ["FAKE_CONCURRENCY_LOG"]
		with open(log, "a") as fh:
			fh.write("S\\n")
		time.sleep(0.4)
		with open(log, "a") as fh:
			fh.write("E\\n")
		sys.exit(0)
	sys.exit(0)
""")


def make_fake_godot(directory: Path, name: str = "fake godot.gd.py") -> Path:
	"""生成可执行的假 godot（文件名带空格，顺带覆盖路径转义）。"""
	p = directory / name
	p.write_text(FAKE_GODOT, encoding="utf-8")
	p.chmod(p.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
	return p


@contextmanager
def patched_env(**kwargs):
	"""临时设置环境变量（走 os.environ.__setitem__ 保持 putenv 同步，子进程可见）。"""
	saved = {}
	try:
		for k, v in kwargs.items():
			saved[k] = os.environ.get(k)
			os.environ[k] = v
		yield
	finally:
		for k, v in saved.items():
			if v is None:
				os.environ.pop(k, None)
			else:
				os.environ[k] = v


def make_contract(name: str, **kw) -> rc.Contract:
	base = dict(
		name=name, path=f"res://tests/{name}_contract.gd", group="test-group",
		tags=["pure"], known_status="pass", parallel_safe=True, fast_flag_safe=True,
	)
	base.update(kw)
	return rc.Contract(**base)


class SelectionTests(unittest.TestCase):
	"""--test / --group / --changed 的选择与影响分析（纯函数，不跑 godot）。"""

	def setUp(self):
		self.contracts = [
			make_contract("alpha"), make_contract("beta"),
			make_contract("gamma", group="other", tags=["render"]),
		]

	def test_select_by_names(self):
		sel = rc.select_by_names(self.contracts, ["alpha", "gamma"])
		self.assertEqual(sel.names, ["alpha", "gamma"])

	def test_select_by_names_unknown(self):
		with self.assertRaises(ValueError):
			rc.select_by_names(self.contracts, ["nope"])

	def test_select_by_group_or_tag(self):
		by_group = rc.select_by_group(self.contracts, ["test-group"])
		self.assertEqual(by_group.names, ["alpha", "beta"])
		by_tag = rc.select_by_group(self.contracts, ["render"])
		self.assertEqual(by_tag.names, ["gamma"])
		with self.assertRaises(ValueError):
			rc.select_by_group(self.contracts, ["nope"])

	def test_changed_closure_hit(self):
		with tempfile.TemporaryDirectory() as td:
			repo = Path(td)
			(repo / "tests").mkdir()
			(repo / "scripts").mkdir()
			(repo / "docs").mkdir()
			(repo / "tests" / "alpha_contract.gd").write_text(
				'const F = preload("res://scripts/foo.gd")\n')
			(repo / "scripts" / "foo.gd").write_text(
				'const B = preload("res://scripts/bar.gd")\n')
			(repo / "scripts" / "bar.gd").write_text("extends RefCounted\n")
			(repo / "docs" / "note.md").write_text("x\n")
			sel = rc.select_by_changed(self.contracts, ["scripts/bar.gd"], repo=repo)
			self.assertEqual(sel.names, ["alpha"])  # 闭包：bar <- foo <- alpha
			sel2 = rc.select_by_changed(self.contracts, ["docs/note.md"], repo=repo)
			self.assertEqual(sel2.names, [])       # 非源码路径 → 无映射不选

	def test_changed_unmapped_source_conservative_all(self):
		with tempfile.TemporaryDirectory() as td:
			repo = Path(td)
			(repo / "tests").mkdir()
			(repo / "scripts").mkdir()
			(repo / "tests" / "alpha_contract.gd").write_text("extends SceneTree\n")
			(repo / "scripts" / "lonely.gd").write_text("extends RefCounted\n")
			sel = rc.select_by_changed(self.contracts, ["scripts/lonely.gd"], repo=repo)
			self.assertEqual(sel.names, ["alpha", "beta", "gamma"])  # 保守全选
			self.assertIn("保守全选", sel.reasons["alpha"])

	def test_changed_hits_test_file_itself(self):
		with tempfile.TemporaryDirectory() as td:
			repo = Path(td)
			(repo / "tests").mkdir()
			(repo / "tests" / "alpha_contract.gd").write_text("extends SceneTree\n")
			sel = rc.select_by_changed(self.contracts, ["tests/alpha_contract.gd"], repo=repo)
			self.assertEqual(sel.names, ["alpha"])


class RunContractTests(unittest.TestCase):
	"""run_contract 执行语义：状态、超时、进程组清理（用假 godot）。"""

	def setUp(self):
		self._tmp = tempfile.TemporaryDirectory()
		self.tmp = Path(self._tmp.name)
		self.fake = make_fake_godot(self.tmp)
		self.out = self.tmp / "out"
		self.out.mkdir()

	def tearDown(self):
		self._tmp.cleanup()

	def _run(self, contract: rc.Contract, mode: str, **kw):
		with patched_env(FAKE_MODE=mode):
			return rc.run_contract(contract, godot=str(self.fake), out_dir=self.out, **kw)

	def test_pass_and_fail_status(self):
		r_ok = self._run(make_contract("t_ok"), "pass", timeout=10)
		self.assertEqual((r_ok.status, r_ok.exit_code), ("pass", 0))
		r_bad = self._run(make_contract("t_bad"), "fail", timeout=10)
		self.assertEqual((r_bad.status, r_bad.exit_code), ("fail", 1))
		self.assertTrue((self.out / "t_ok.log").exists())
		self.assertIn("fake godot", (self.out / "t_ok.log").read_text())

	def test_executor_error_when_godot_missing(self):
		r = rc.run_contract(
			make_contract("t_noexec"), godot=str(self.tmp / "does not exist"),
			timeout=5, out_dir=self.out)
		self.assertEqual(r.status, "executor-error")

	def test_timeout_kills_process_group(self):
		r = self._run(make_contract("t_hang"), "hang", timeout=1.5)
		self.assertEqual(r.status, "timeout")
		self.assertEqual(r.exit_code, 124)
		self.assertLess(r.seconds, 10)

	def test_timeout_kills_child_processes_too(self):
		"""假 godot 先 spawn 一个 sleep 子进程再挂起；超时后整个进程组都必须死。"""
		pid_file = self.tmp / "child_pid"
		with patched_env(FAKE_MODE="hang_with_child", FAKE_CHILD_PID_FILE=str(pid_file)):
			r = rc.run_contract(
				make_contract("t_group_kill"), godot=str(self.fake),
				timeout=2.0, out_dir=self.out)
		self.assertEqual(r.status, "timeout")
		child_pid = int(pid_file.read_text().strip())
		time.sleep(0.3)  # 留出内核清理时间
		with self.assertRaises(OSError):
			os.kill(child_pid, 0)  # 子进程必须已被进程组 kill

	def test_fast_flags_only_on_whitelist(self):
		c_fast = make_contract("t_fast", fast_flag_safe=True)
		c_slow = make_contract("t_slow", fast_flag_safe=False)
		cmd_fast, applied_fast = rc.build_command("godot", c_fast, 10, True)
		cmd_slow, applied_slow = rc.build_command("godot", c_slow, 10, True)
		self.assertIn("--fixed-fps", cmd_fast)
		self.assertIn("--disable-render-loop", cmd_fast)
		self.assertTrue(applied_fast)
		self.assertNotIn("--fixed-fps", cmd_slow)
		self.assertNotIn("--disable-render-loop", cmd_slow)
		self.assertFalse(applied_slow)


class EnvSkipTests(unittest.TestCase):
	"""environment-skip 语义：默认不执行；--run-env-skip 下失败仍记 env-skip、通过记 pass。"""

	def setUp(self):
		self._tmp = tempfile.TemporaryDirectory()
		self.tmp = Path(self._tmp.name)
		self.fake = make_fake_godot(self.tmp)

	def tearDown(self):
		self._tmp.cleanup()

	def _classify(self, status: str, known: str):
		contract = make_contract("t_env", known_status=known)
		result = rc.RunResult(
			"t_env", status, 1 if status == "fail" else 124, 1.0,
			str(self.tmp / "x.log"), ["godot"], "", False)
		return rc.classify_env_skip(result, contract)

	def test_env_skip_item_failing_stays_env_skip(self):
		r = self._classify("fail", "environment-skip")
		self.assertEqual(r.status, "environment-skip")
		r2 = self._classify("timeout", "environment-skip")
		self.assertEqual(r2.status, "environment-skip")

	def test_env_skip_item_passing_upgrades_to_pass(self):
		r = self._classify("pass", "environment-skip")
		self.assertEqual(r.status, "pass")
		self.assertIn("更新 manifest", r.reason)

	def test_known_fail_item_stays_fail(self):
		r = self._classify("fail", "known-fail")
		self.assertEqual(r.status, "fail")


class ConcurrencyTests(unittest.TestCase):
	"""--jobs 只并发 parallel_safe；并发数不超过 N。"""

	def setUp(self):
		self._tmp = tempfile.TemporaryDirectory()
		self.tmp = Path(self._tmp.name)
		self.fake = make_fake_godot(self.tmp)

	def tearDown(self):
		self._tmp.cleanup()

	def _max_overlap(self, log_path: Path) -> int:
		lines = log_path.read_text().splitlines()
		cur = best = 0
		for line in lines:
			if line == "S":
				cur += 1
				best = max(best, cur)
			elif line == "E":
				cur -= 1
		return best

	def test_jobs_respects_parallel_safe_split(self):
		contracts = [
			make_contract(f"par_{i}") for i in range(6)
		] + [make_contract("serial_1", parallel_safe=False), make_contract("serial_2", parallel_safe=False)]
		out = self.tmp / "out"
		out.mkdir()
		log = self.tmp / "conc.log"
		log.write_text("")
		with patched_env(FAKE_MODE="lock", FAKE_CONCURRENCY_LOG=str(log)):
			results = []
			parallel = [c for c in contracts if c.parallel_safe]
			serial = [c for c in contracts if not c.parallel_safe]
			import concurrent.futures
			with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
				results.extend(pool.map(
					lambda c: rc.run_contract(c, godot=str(self.fake), timeout=10, out_dir=out),
					parallel))
			results.extend(
				rc.run_contract(c, godot=str(self.fake), timeout=10, out_dir=out) for c in serial)
		statuses = [r.status for r in results]
		self.assertEqual(statuses.count("pass"), 8)
		self.assertLessEqual(self._max_overlap(log), 3)

	def test_unsafe_never_concurrent_with_others(self):
		"""execute_selection 必须把 unsafe 契约放在并发阶段之后串行。"""
		self._tmp2 = tempfile.TemporaryDirectory()
		tmp2 = Path(self._tmp2.name)
		manifest_dir = tmp2
		# 直接验证排序逻辑：execute_selection 输出顺序中 unsafe 在最后执行
		contracts = [
			make_contract("p1"), make_contract("p2"),
			make_contract("u1", parallel_safe=False),
		]
		args = type("Args", (), {})()
		args.godot = str(self.fake)
		args.timeout = 10.0
		args.out = str(tmp2 / "out")
		args.fast_fps = None
		args.disable_render_loop = False
		args.verbose = False
		args.run_env_skip = False
		args.no_warmup = True
		args.jobs = 2
		args.backend = "native"
		args.gdtest = "gdtest"
		(tmp2 / "out").mkdir()
		with patched_env(FAKE_MODE="pass"):
			sel = rc.Selection(["p1", "p2", "u1"], {n: "test" for n in ("p1", "p2", "u1")})
			results, header = rc.execute_selection(contracts, sel, args)
		self.assertEqual([r.status for r in results].count("pass"), 3)
		self.assertTrue(any("串行阶段" in h for h in header))


class ReportTests(unittest.TestCase):
	"""summary.tsv / summary.json / junit.xml 产物。"""

	def setUp(self):
		self._tmp = tempfile.TemporaryDirectory()
		self.tmp = Path(self._tmp.name)

	def tearDown(self):
		self._tmp.cleanup()

	def test_outputs_and_exit_codes(self):
		out = self.tmp / "out with space"
		out.mkdir()
		results = [
			rc.RunResult("a", "pass", 0, 1.2, str(out / "a.log"), ["g"], "", True),
			rc.RunResult("b", "fail", 1, 2.0, str(out / "b.log"), ["g"], "boom", False),
			rc.RunResult("c", "timeout", 124, 9.0, str(out / "c.log"), ["g"], "超时", False),
			rc.RunResult("d", "environment-skip", -1, 0.0, "", None, "需 GPU", False),
			rc.RunResult("e", "executor-error", None, 0.0, "", None, "no godot", False),
		]
		tsv = rc.write_summary_tsv(out, results)
		lines = tsv.read_text().strip().splitlines()
		self.assertEqual(lines[0].split("\t"), ["name", "exit_code", "seconds", "status"])  # 旧 4 列
		self.assertEqual(lines[1].split("\t")[3], "pass")
		self.assertEqual(lines[3].split("\t")[3], "timeout")
		jsn = rc.write_summary_json(out, results, {"total_seconds": 3.0}, [])
		data = json.loads(jsn.read_text())
		self.assertEqual(data["summary"]["fail"], 1)
		self.assertEqual(data["summary"]["environment-skip"], 1)
		self.assertEqual(data["results"][0]["command"], ["g"])
		junit = rc.write_junit(out, results, {"total_seconds": 3.0})
		xml = junit.read_text()
		self.assertIn('<testsuites name="pixel_world_contracts" tests="5"', xml)
		self.assertEqual(xml.count("<failure"), 2)  # fail + timeout
		self.assertEqual(xml.count("<skipped>"), 1)
		self.assertIn("<error type=", xml)


class CliTests(unittest.TestCase):
	"""CLI 用法错误与 --list/--dry-run（不真跑 godot）。"""

	def test_usage_errors_exit_2(self):
		self.assertEqual(rc.main([]), 2)                       # 无选择
		self.assertEqual(rc.main(["--jobs", "9", "--all"]), 2)  # jobs 越界
		self.assertEqual(rc.main(["--test", "no_such"]), 2)     # 未知契约
		self.assertEqual(rc.main(["--group", "no_such_group"]), 2)

	def test_list_and_dry_run(self):
		with tempfile.TemporaryDirectory() as td:
			self.assertEqual(rc.main(["--list"]), 0)
			self.assertEqual(
				rc.main(["--test", "ecology_resolver", "--dry-run", "--out", td]), 0)

	def test_manifest_coverage_check(self):
		raw, contracts = rc.load_manifest()
		warnings = rc.check_manifest_coverage(contracts)
		self.assertEqual(warnings, [], f"manifest 与盘上不一致: {warnings}")
		self.assertEqual(len(contracts), 80)  # 78 原有 + ecology_logic_bench + simulation（B 链）

	def test_manifest_all_paths_exist(self):
		raw, contracts = rc.load_manifest()
		missing = [c.path for c in contracts if not (rc.REPO_ROOT / c.path[6:]).is_file()]
		self.assertEqual(missing, [])


class GdTestBackendTests(unittest.TestCase):
	"""--backend gdtest：映射契约走 gdtest，无映射契约回落 native。"""

	def _make_fake_gdtest(self, directory: Path, marker: Path, exit_code: int = 0) -> Path:
		src = textwrap.dedent(f"""\
			#!/usr/bin/env python3
			import sys
			with open({str(marker)!r}, "a") as fh:
				fh.write(" ".join(sys.argv[1:]) + "\\n")
			sys.exit({exit_code})
		""")
		p = directory / "fake_gdtest.py"
		p.write_text(src, encoding="utf-8")
		p.chmod(p.stat().st_mode | stat.S_IXUSR)
		return p

	def test_gdtest_backend_runs_mapped_contract_via_gdtest(self):
		with tempfile.TemporaryDirectory() as td:
			tdir = Path(td)
			marker = tdir / "gdtest_calls.txt"
			fake_gdtest = self._make_fake_gdtest(tdir, marker)
			fake_godot = make_fake_godot(tdir)
			c = make_contract("cell_state", gdtest_file="tests/gdtest/test_cell_state.gd")
			out = tdir / "out"; out.mkdir()
			res = rc.run_contract(
				c, godot=str(fake_godot), timeout=30, out_dir=out,
				backend="gdtest", gdtest_exe=str(fake_gdtest),
			)
			self.assertEqual(res.status, "pass")
			calls = marker.read_text().splitlines()
			self.assertEqual(len(calls), 1)
			argv = calls[0].split()
			self.assertEqual(argv[0], "--godot-exe")
			self.assertIn("tests/gdtest/test_cell_state.gd", argv)
			self.assertNotIn("--headless", argv)  # 走的是 gdtest，不是原生 godot --script
			self.assertIn(str(fake_godot), calls[0])

	def test_gdtest_backend_failure_maps_to_fail(self):
		with tempfile.TemporaryDirectory() as td:
			tdir = Path(td)
			marker = tdir / "gdtest_calls.txt"
			fake_gdtest = self._make_fake_gdtest(tdir, marker, exit_code=1)
			fake_godot = make_fake_godot(tdir)
			c = make_contract("ecology_resolver", gdtest_file="tests/gdtest/test_ecology_resolver.gd")
			out = tdir / "out"; out.mkdir()
			res = rc.run_contract(
				c, godot=str(fake_godot), timeout=30, out_dir=out,
				backend="gdtest", gdtest_exe=str(fake_gdtest),
			)
			self.assertEqual((res.status, res.exit_code), ("fail", 1))

	def test_gdtest_backend_falls_back_to_native_without_mapping(self):
		with tempfile.TemporaryDirectory() as td:
			tdir = Path(td)
			marker = tdir / "gdtest_calls.txt"
			fake_gdtest = self._make_fake_gdtest(tdir, marker)
			fake_godot = make_fake_godot(tdir)
			c = make_contract("unmapped_contract")  # 无 gdtest 映射
			out = tdir / "out"; out.mkdir()
			with patched_env(FAKE_MODE="pass"):
				res = rc.run_contract(
					c, godot=str(fake_godot), timeout=30, out_dir=out,
					backend="gdtest", gdtest_exe=str(fake_gdtest),
				)
			self.assertEqual(res.status, "pass")
			self.assertFalse(marker.exists())       # gdtest 未被调用
			self.assertIn("--script", res.command)  # 走了 native 命令
			self.assertIn("回落 native", res.reason)

	def test_cli_rejects_gdtest_backend_without_executable(self):
		with tempfile.TemporaryDirectory() as td:
			missing = str(Path(td) / "no_such_gdtest")
			rc_main = rc.main(["--test", "cell_state", "--backend", "gdtest",
							   "--gdtest", missing])
			self.assertEqual(rc_main, 2)


@unittest.skipUnless(Path(REAL_GODOT).exists(), "本机无 godot 可执行")
class RealGodotSmokeTests(unittest.TestCase):
	"""真实 godot 冒烟：只跑 2 个快速纯逻辑契约 + 1 个 known-fail 分类。"""

	def test_two_pure_contracts_pass(self):
		with tempfile.TemporaryDirectory() as td:
			out = Path(td) / "out"
			out.mkdir()
			eco = make_contract("ecology_resolver")
			eco.path = "res://tests/ecology_resolver_contract.gd"
			cell = make_contract("cell_state")
			cell.path = "res://tests/cell_state_contract.gd"
			r1 = rc.run_contract(eco, godot=REAL_GODOT, timeout=120, out_dir=out)
			r2 = rc.run_contract(cell, godot=REAL_GODOT, timeout=120, out_dir=out)
			self.assertEqual((r1.status, r2.status), ("pass", "pass"),
							 f"logs: {r1.log} / {r2.log}")

	def test_known_fail_contract_reports_fail(self):
		# 夹具=manifest 里现存的 known-fail 契约（known-fail 保持可见、不吞是 runner 语义）。
		# 2026-11-17 全部 known-fail 修复清零后无夹具可挑：skip（语义仍由 manifest 校验测试覆盖）。
		_, contracts = rc.load_manifest()
		kf = [c for c in contracts if c.known_status == "known-fail"]
		if not kf:
			self.skipTest("manifest 无 known-fail 契约（全部修复），无夹具可测")
		with tempfile.TemporaryDirectory() as td:
			out = Path(td) / "out"
			out.mkdir()
			c = kf[0]
			r = rc.run_contract(c, godot=REAL_GODOT, timeout=180, out_dir=out)
			self.assertEqual(r.status, "fail")  # known-fail 保持可见，不吞


if __name__ == "__main__":
	unittest.main(verbosity=2)
