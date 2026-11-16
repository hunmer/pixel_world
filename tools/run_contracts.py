#!/usr/bin/env python3
"""tools/run_contracts.py — 统一契约测试运行器（可选择、可并发、可诊断、可复现）。

用法（详见 --help / docs/test_automation_results.md）：
    python3 tools/run_contracts.py --list [子串]
    python3 tools/run_contracts.py --test ecology_resolver cell_state [--dry-run]
    python3 tools/run_contracts.py --group ecology --jobs 3
    python3 tools/run_contracts.py --changed [文件...]        # 无参数走 git 变更
    python3 tools/run_contracts.py --all --run-env-skip --junit

设计要点：
- 仅标准库；契约元数据来自 tests/contract_manifest.json（S1.1）。
- 状态枚举：pass / fail / timeout / environment-skip / executor-error。
- 并发只作用于 manifest 标记 parallel_safe=true 的契约（--jobs 1-4）；
  unsafe 契约在并发阶段之后严格串行执行。
- 每个契约独立进程组（os.setsid），超时 killpg(SIGKILL)，不留子进程。
- 默认先跑一次 `godot --headless --path . --import` 预热导入缓存（--no-warmup 关闭）。
- --fast-fps / --disable-render-loop 仅作用于 fast_flag_safe=true 白名单，
  其余契约照常执行并在结果里注明未加速（禁止暗中改变计时/渲染语义）。
- environment-skip 项默认不执行、直接标记（保持可见）；--run-env-skip 才真正跑，
  跑挂/超时仍记 environment-skip，跑过则记 pass（提示环境已恢复、应更新 manifest）。
- 退出码：0 = 全部 pass 或仅 environment-skip；1 = 存在 fail/timeout/executor-error；
  2 = 用法/清单错误。
- 产物：<out>/<name>.log 逐契约日志、summary.tsv（旧 4 列）、summary.json、junit.xml。
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import xml.sax.saxutils as saxutils
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "tests" / "contract_manifest.json"
DEFAULT_GODOT = os.environ.get("GODOT", "/Applications/Godot.app/Contents/MacOS/Godot")
DEFAULT_TIMEOUT = int(os.environ.get("CONTRACT_TIMEOUT", "900"))
# 状态枚举（勿改顺序，summary 报告按此统计）
STATUSES = ("pass", "fail", "timeout", "environment-skip", "executor-error")
# 视为“非失败”的状态：要么通过，要么环境受限被跳过
OKISH_STATUSES = {"pass", "environment-skip"}

# --changed 的源码根：这些目录下的未映射文件 → 保守全选；
# 根外路径（docs/、claude/、.codegraph/ 等）→ 明确“无契约映射”不选。
SOURCE_ROOTS = (
	"scripts/", "tests/", "ui/", "scenes/", "config/", "data/", "addons/", "tools/",
	"main.gd", "project.godot",
)
RES_REF_RE = re.compile(r"res://[^\"'\s)\],]+")


# ---------------------------------------------------------------------------
# 清单与数据结构
# ---------------------------------------------------------------------------

@dataclass
class Contract:
	name: str
	path: str          # res:// 路径
	group: str
	tags: list
	known_status: str  # pass / known-fail / environment-skip
	parallel_safe: bool
	fast_flag_safe: bool
	evidence: dict = field(default_factory=dict)
	gdtest_file: str = ""  # 可选：等价 gdtest 用例路径（--backend gdtest 时替代 native 执行）


def load_manifest(path: Path = MANIFEST_PATH) -> tuple[dict, list[Contract]]:
	"""读取 manifest；返回 (原始 dict, Contract 列表)。找不到/结构非法直接抛异常。"""
	if not path.is_file():
		raise FileNotFoundError(f"manifest 不存在: {path}")
	raw = json.loads(path.read_text(encoding="utf-8"))
	contracts = []
	for item in raw["contracts"]:
		path = item["path"]
		if not path.startswith("res://"):
			path = "res://" + path
		evidence = item.get("evidence", {})
		if not isinstance(evidence, dict):
			evidence = {"note": str(evidence)}
		contracts.append(Contract(
			name=item["name"],
			path=path,
			group=item["group"],
			tags=list(item.get("tags", [])),
			known_status=item.get("known_status", "pass"),
			parallel_safe=bool(item.get("parallel_safe", False)),
			fast_flag_safe=bool(item.get("fast_flag_safe", False)),
			evidence=evidence,
			gdtest_file=str(item.get("gdtest", "")),
		))
	return raw, contracts


def check_manifest_coverage(contracts: list[Contract]) -> list[str]:
	"""盘上 tests/*_contract.gd 与 manifest 的差异告警（不致命）。"""
	on_disk = sorted(p.name[: -len("_contract.gd")] for p in (REPO_ROOT / "tests").glob("*_contract.gd"))
	in_manifest = sorted(c.name for c in contracts)
	warnings = []
	for extra in set(on_disk) - set(in_manifest):
		warnings.append(f"盘上存在但 manifest 缺少: {extra}_contract.gd（请补录）")
	for missing in set(in_manifest) - set(on_disk):
		warnings.append(f"manifest 声明但文件不存在: {missing}_contract.gd（请清理）")
	return warnings


# ---------------------------------------------------------------------------
# 选择：--test / --group / --changed / --all
# ---------------------------------------------------------------------------

@dataclass
class Selection:
	names: list
	reasons: dict = field(default_factory=dict)  # name -> 选中理由（供打印）


def select_by_names(contracts: list[Contract], wanted: list[str]) -> Selection:
	"""按契约名精确选择；未知名直接抛 ValueError（→ 用法错误）。"""
	by_name = {c.name: c for c in contracts}
	for w in wanted:
		if w not in by_name:
			raise ValueError(f"未知契约名: {w}（用 --list 查看；manifest 共 {len(by_name)} 项）")
	return Selection(
		names=list(wanted),
		reasons={w: "--test 指定" for w in wanted},
	)


def select_by_group(contracts: list[Contract], groups: list[str]) -> Selection:
	"""按 group 字段或任意 tag 选择（tag: 前缀可省略，group 名优先）。"""
	all_groups = sorted({c.group for c in contracts})
	all_tags = sorted({t for c in contracts for t in c.tags})
	for g in groups:
		if g not in all_groups and g not in all_tags:
			raise ValueError(f"未知 group/tag: {g}（现有 group: {', '.join(all_groups)}）")
	names = [c.name for c in contracts if c.group in groups or any(t in groups for t in c.tags)]
	return Selection(
		names=names,
		reasons={c.name: f"group/tag={c.group}" + (f"/{','.join(t for t in c.tags if t in groups)}" if any(t in groups for t in c.tags) else "")
			for c in contracts if c.name in names},
	)


def git_changed_files(repo: Path) -> list[str]:
	"""工作树相对 git 的改动文件（已跟踪改动 + 未跟踪新增），失败抛 RuntimeError。"""
	try:
		tracked = subprocess.run(
			["git", "diff", "--name-only", "HEAD"], cwd=repo,
			capture_output=True, text=True, check=True,
		).stdout.splitlines()
		untracked = subprocess.run(
			["git", "ls-files", "--others", "--exclude-standard"], cwd=repo,
			capture_output=True, text=True, check=True,
		).stdout.splitlines()
	except (subprocess.CalledProcessError, FileNotFoundError) as exc:
		raise RuntimeError(f"git 变更查询失败: {exc}") from exc
	seen, out = set(), []
	for rel in tracked + untracked:
		rel = rel.strip()
		if rel and rel not in seen:
			seen.add(rel)
			out.append(rel)
	return out


def build_reference_graph(repo: Path) -> dict[str, set[str]]:
	"""全仓 res:// 引用图：文件 → 其引用的仓库内文件集合（含 uid:// 解析）。"""
	repo = repo.resolve()  # macOS /var -> /private/var symlink 归一
	uid_to_path = {}
	for uid_file in repo.rglob("*.uid"):
		try:
			uid = uid_file.read_text(encoding="utf-8").strip()
		except OSError:
			continue
		if uid.startswith("uid://"):
			uid_to_path[uid] = uid_file.with_suffix("").as_posix()
	graph: dict[str, set[str]] = {}
	scan_roots = ["scripts", "tests", "ui", "scenes", "config", "data", "addons", "tools"]
	scan_files = [repo / "main.gd", repo / "project.godot"]
	for root in scan_roots:
		base = repo / root
		if not base.is_dir():
			continue
		for pattern in ("*.gd", "*.tscn", "*.json", "*.cfg", "*.tres"):
			scan_files.extend(base.rglob(pattern))
	for f in scan_files:
		if not f.is_file() or ".godot" in f.parts:
			continue
		try:
			content = f.read_text(encoding="utf-8", errors="ignore")
		except OSError:
			continue
		rel = f.relative_to(repo).as_posix()
		refs = set()
		for ref in RES_REF_RE.findall(content):
			rel_ref = ref[len("res://"):]
			target = (repo / rel_ref).resolve()
			if target.is_file():
				refs.add(target.relative_to(repo).as_posix())
		for m in re.finditer(r"uid://[A-Za-z0-9]+", content):
			rel_ref = uid_to_path.get(m.group(0))
			if rel_ref and (repo / rel_ref).is_file():
				refs.add(rel_ref)
		graph[rel] = refs
	return graph


def tests_reaching(graph: dict[str, set[str]], test_files: list[str]) -> dict[str, set[str]]:
	"""每个测试文件的依赖闭包：test 及其（传递）引用的所有文件。沿正向引用边走。"""
	reach: dict[str, set[str]] = {}
	for test in test_files:
		seen, stack = {test}, [test]
		while stack:
			cur = stack.pop()
			for child in graph.get(cur, ()):  # cur 引用的文件
				if child not in seen:
					seen.add(child)
					stack.append(child)
		reach[test] = seen
	return reach


def select_by_changed(
	contracts: list[Contract], changed: list[str], repo: Path = REPO_ROOT,
) -> Selection:
	"""--changed 影响分析：改动文件 → 受影响契约。

	规则（打印在输出里）：
	- 命中某契约可达闭包（含契约文件自身）→ 选中该契约；
	- 属于源码根（SOURCE_ROOTS）但没有任何契约引用 → 保守全选（不能证明无影响）；
	- 源码根之外（docs/、claude/、.codegraph/ 等）→ 无契约映射，不选。
	"""
	test_files = [c.path[len("res://"):] for c in contracts]
	graph = build_reference_graph(repo)
	reach = tests_reaching(graph, test_files)
	name_by_file = {c.path[len("res://"):]: c.name for c in contracts}
	reasons: dict[str, str] = {}
	selected: list[str] = []
	conservative = False
	log_lines: list[str] = []
	for rel in changed:
		rel = rel.strip()
		if not rel:
			continue
		if rel.startswith("res://"):
			rel = rel[len("res://"):]
		abs_hit = [tf for tf in test_files if rel in reach[tf]]
		if abs_hit:
			for tf in abs_hit:
				reasons[name_by_file[tf]] = f"受 {rel} 影响（引用闭包命中）"
			selected.extend(name_by_file[tf] for tf in abs_hit)
			log_lines.append(f"  {rel} -> {len(abs_hit)} 个契约")
			continue
		in_source_roots = any(rel == s or rel.startswith(s) for s in SOURCE_ROOTS)
		if in_source_roots:
			conservative = True
			log_lines.append(f"  {rel} -> 源码文件但无契约引用 → 保守全选")
		else:
			log_lines.append(f"  {rel} -> 非源码路径，无契约映射")
	if conservative:
		all_names = [c.name for c in contracts]
		reasons = {c.name: "保守全选（存在未映射的源码改动）" for c in contracts}
		selected = all_names
	# 保持 manifest 顺序，去重
	ordered = [c.name for c in contracts if c.name in set(selected)]
	reasons = {n: reasons.get(n, "changed 选择") for n in ordered}
	sel = Selection(names=ordered, reasons=reasons)
	sel_notes = "\n".join(log_lines)  # noqa: F841 — 供调用方打印
	return sel


# ---------------------------------------------------------------------------
# 执行
# ---------------------------------------------------------------------------

@dataclass
class RunResult:
	name: str
	status: str
	exit_code: Optional[int]
	seconds: float
	log: str
	command: Optional[list] = None
	reason: str = ""
	fast_flags_applied: bool = False


def build_command(
	godot: str, contract: Contract, fast_fps: Optional[int], disable_render_loop: bool,
) -> tuple[list[str], bool]:
	"""构造单个契约的 godot 命令行；返回 (argv, 是否应用了加速 flag)。"""
	argv = [godot, "--headless", "--path", "."]
	accelerated = False
	if contract.fast_flag_safe:
		if disable_render_loop:
			argv.append("--disable-render-loop")
			accelerated = True
		if fast_fps is not None:
			argv.extend(["--fixed-fps", str(fast_fps)])
			accelerated = True
	argv.extend(["--script", contract.path])
	return argv, accelerated


def build_gdtest_command(
	gdtest_exe: str, godot: str, contract: Contract, timeout: float,
) -> list[str]:
	"""构造 gdtest 后端命令：契约的 gdtest 等价用例经持久 worker 执行。

	- --timeout 为 gdtest 的单测试毫秒超时（runner 秒级超时 ×1000）；
	- -j 1：契约级并发由 runner 自身 --jobs 管理，单契约内无需再并行；
	- --no-auto-import：runner 默认已做 godot --import 预热。
	"""
	target = contract.gdtest_file
	if target.startswith("res://"):
		target = target[len("res://"):]
	return [
		gdtest_exe, "--godot-exe", godot, "--no-auto-import",
		"-j", "1", "--timeout", str(int(timeout * 1000)), target,
	]


def kill_process_group(pid: int) -> None:
	"""按进程组 SIGKILL（跨平台 best-effort）。"""
	if pid <= 0:
		return
	if os.name == "nt":  # pragma: no cover - Windows 分支（本仓库主用 macOS）
		subprocess.run(["taskkill", "/T", "/F", "/PID", str(pid)], capture_output=True)
		return
	try:
		os.killpg(pid, signal.SIGKILL)
	except ProcessLookupError:
		pass
	except PermissionError:  # pragma: no cover
		try:
			os.kill(pid, signal.SIGKILL)
		except ProcessLookupError:
			pass


def run_contract(
	contract: Contract,
	godot: str,
	timeout: float,
	out_dir: Path,
	fast_fps: Optional[int] = None,
	disable_render_loop: bool = False,
	verbose: bool = False,
	cwd: Optional[Path] = None,
	backend: str = "native",
	gdtest_exe: str = "",
) -> RunResult:
	"""执行单个契约：独立进程组 + 超时 killpg。永不抛异常（失败 → executor-error）。

	backend="gdtest" 时，有 gdtest 等价用例映射的契约走 gdtest 持久 worker；
	其余契约回落 native（并在 reason 里注明）。
	"""
	log_path = out_dir / f"{contract.name}.log"
	native_note = ""
	use_gdtest = backend == "gdtest" and bool(contract.gdtest_file)
	if backend == "gdtest" and not use_gdtest:
		native_note = "（backend=gdtest 但该契约无 gdtest 映射，回落 native）"
	if use_gdtest:
		command = build_gdtest_command(gdtest_exe, godot, contract, timeout)
		accelerated = False
	else:
		command, accelerated = build_command(godot, contract, fast_fps, disable_render_loop)
	start = time.monotonic()
	try:
		proc = subprocess.Popen(
			command,
			cwd=str(cwd or REPO_ROOT),
			stdout=subprocess.PIPE,
			stderr=subprocess.STDOUT,
			text=True,
			start_new_session=os.name != "nt",  # 独立进程组
		)
	except OSError as exc:
		return RunResult(
			contract.name, "executor-error", None, time.monotonic() - start, str(log_path),
			command, f"无法启动 {command[0]}: {exc}",
		)
	output = ""
	try:
		out, _ = proc.communicate(timeout=timeout)
		output = out or ""
	except subprocess.TimeoutExpired:
		kill_process_group(proc.pid)
		try:
			out, _ = proc.communicate(timeout=10)
			output = (out or "") + f"\n[runner] 超时 {timeout}s，进程组已被 SIGKILL"
		except subprocess.TimeoutExpired:  # pragma: no cover - killpg 后极少发生
			pass
		elapsed = time.monotonic() - start
		log_path.write_text(output, encoding="utf-8")
		if verbose and output:
			sys.stdout.write(f"[{contract.name}] {output}")
		return RunResult(
			contract.name, "timeout", 124, elapsed, str(log_path), command,
			f"超过 {timeout}s 被杀（进程组 SIGKILL，退出码按旧约定记 124）", accelerated,
		)
	except KeyboardInterrupt:  # pragma: no cover
		kill_process_group(proc.pid)
		raise
	elapsed = time.monotonic() - start
	log_path.write_text(output, encoding="utf-8")
	if verbose and output:
		sys.stdout.write(f"[{contract.name}] {output}")
	if proc.returncode == 0:
		status = "pass"
	else:
		status = "fail"
	reason = native_note
	return RunResult(
		contract.name, status, proc.returncode, elapsed, str(log_path), command, reason, accelerated,
	)


def run_warmup_import(godot: str, cwd: Optional[Path] = None, timeout: float = 300.0) -> tuple[bool, str]:
	"""跑一次 godot --import 预热，避免并发首跑各自抢导入锁。"""
	argv = [godot, "--headless", "--path", ".", "--import"]
	start = time.monotonic()
	proc = None
	try:
		proc = subprocess.Popen(
			argv, cwd=str(cwd or REPO_ROOT), stdout=subprocess.PIPE,
			stderr=subprocess.STDOUT, text=True, start_new_session=os.name != "nt",
		)
		out, _ = proc.communicate(timeout=timeout)
	except (OSError, subprocess.TimeoutExpired) as exc:
		if proc is not None and proc.poll() is None:
			kill_process_group(proc.pid)
			try:
				proc.communicate(timeout=10)
			except subprocess.TimeoutExpired:  # pragma: no cover
				pass
		return False, f"预热 --import 失败: {exc}"
	if proc.returncode != 0:
		return False, f"预热 --import 退出码 {proc.returncode}: {(out or '')[-500:]}"
	return True, f"预热 --import 完成（{time.monotonic() - start:.0f}s）"


def classify_env_skip(result: RunResult, contract: Contract) -> RunResult:
	"""--run-env-skip 模式下，environment-skip 项跑挂不记真实失败。"""
	if contract.known_status == "environment-skip" and result.status in ("fail", "timeout"):
		result.reason = (
			f"environment-skip 项按 manifest 预期在当前环境不可用"
			f"（实际 exit={result.exit_code}，日志保留供诊断）"
		)
		result.status = "environment-skip"
	elif contract.known_status == "environment-skip" and result.status == "pass":
		result.reason = "environment-skip 项在本环境通过 —— 环境可能已恢复，请更新 manifest"
	return result


def execute_selection(
	contracts: list[Contract],
	selection: Selection,
	args,
) -> tuple[list[RunResult], list[str]]:
	"""执行选中契约：阶段一并发 parallel_safe，阶段二串行 unsafe。返回 (结果, 头部日志行)。"""
	by_name = {c.name: c for c in contracts}
	chosen = [by_name[n] for n in selection.names]
	header: list[str] = []

	# environment-skip 默认不执行
	to_run = []
	env_skip_stub: list[RunResult] = []
	for c in chosen:
		if c.known_status == "environment-skip" and not args.run_env_skip:
			env_skip_stub.append(RunResult(
				c.name, "environment-skip", -1, 0.0, "",
				None, f"manifest 标记 environment-skip（{c.evidence.get('reason', '')}）"
				"未执行；--run-env-skip 可强制执行", False,
			))
		else:
			to_run.append(c)

	runner_kwargs = dict(
		godot=args.godot, timeout=args.timeout, out_dir=Path(args.out),
		fast_fps=args.fast_fps, disable_render_loop=args.disable_render_loop,
		verbose=args.verbose, backend=args.backend, gdtest_exe=args.gdtest,
	)

	results: list[RunResult] = []
	if to_run and not args.no_warmup:
		ok, msg = run_warmup_import(args.godot)
		header.append(msg)
		if not ok:
			results.append(RunResult(
				"warmup", "executor-error", None, 0.0, "", None, msg, False,
			))
			return results + env_skip_stub, header

	parallel = [c for c in to_run if c.parallel_safe]
	serial = [c for c in to_run if not c.parallel_safe]
	if serial and args.jobs > 1:
		header.append(f"串行阶段：{len(serial)} 个 parallel_safe=false 契约单独跑（{', '.join(c.name for c in serial)}）")

	def work(c: Contract) -> RunResult:
		res = run_contract(c, **runner_kwargs)
		return classify_env_skip(res, c)

	if args.jobs > 1 and len(parallel) > 1:
		with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
			results.extend(pool.map(work, parallel))
	else:
		results.extend(work(c) for c in parallel)
	for c in serial:
		results.append(work(c))
	results.extend(env_skip_stub)
	# 按 manifest 顺序稳定输出
	order = {n: i for i, n in enumerate(selection.names)}
	results.sort(key=lambda r: order.get(r.name, 1 << 30))
	return results, header


# ---------------------------------------------------------------------------
# 报告
# ---------------------------------------------------------------------------

def write_summary_tsv(out_dir: Path, results: list[RunResult]) -> Path:
	"""旧 4 列：name / exit_code / seconds / status（与 run_contract_baseline.sh 历史格式一致）。"""
	path = out_dir / "summary.tsv"
	with path.open("w", encoding="utf-8") as fh:
		fh.write("name\texit_code\tseconds\tstatus\n")
		for r in results:
			code = "" if r.exit_code is None else str(r.exit_code)
			fh.write(f"{r.name}\t{code}\t{r.seconds:.1f}\t{r.status}\n")
	return path


def write_summary_json(out_dir: Path, results: list[RunResult], meta: dict, contracts: list[Contract]) -> Path:
	path = out_dir / "summary.json"
	by_name = {c.name: c for c in contracts}
	payload = {
		"meta": meta,
		"results": [
			{
				"name": r.name,
				"path": by_name[r.name].path if r.name in by_name else None,
				"group": by_name[r.name].group if r.name in by_name else "meta",
				"known_status": by_name[r.name].known_status if r.name in by_name else None,
				"parallel_safe": by_name[r.name].parallel_safe if r.name in by_name else None,
				"fast_flag_safe": by_name[r.name].fast_flag_safe if r.name in by_name else None,
				"status": r.status,
				"exit_code": r.exit_code,
				"seconds": round(r.seconds, 2),
				"log": r.log or None,
				"command": r.command,
				"reason": r.reason or None,
				"fast_flags_applied": r.fast_flags_applied,
			}
			for r in results
		],
		"summary": {
			"total": len(results),
			**{s: sum(1 for r in results if r.status == s) for s in STATUSES},
		},
	}
	path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
	return path


def write_junit(out_dir: Path, results: list[RunResult], meta: dict) -> Path:
	path = out_dir / "junit.xml"
	total = len(results)
	fails = sum(1 for r in results if r.status in ("fail", "timeout", "executor-error"))
	skips = sum(1 for r in results if r.status == "environment-skip")
	cases = []
	for r in results:
		body = ""
		if r.status == "fail":
			body = f'<failure type="assert">{saxutils.escape(r.reason or (r.log or ""))[:2000]}</failure>'
		elif r.status == "timeout":
			body = f'<failure type="timeout">{saxutils.escape(r.reason)}</failure>'
		elif r.status == "executor-error":
			body = f'<error type="executor">{saxutils.escape(r.reason)}</error>'
		elif r.status == "environment-skip":
			body = f'<skipped>{saxutils.escape(r.reason)}</skipped>'
		cases.append(
			f'\t<testcase classname="pixel_world.{r.status}" name="{saxutils.escape(r.name)}" time="{r.seconds:.2f}">\n'
			f"{body}\n\t</testcase>" if body
			else f'\t<testcase classname="pixel_world.pass" name="{saxutils.escape(r.name)}" time="{r.seconds:.2f}"/>'
		)
	xml = (
		'<?xml version="1.0" encoding="UTF-8"?>\n'
		f'<testsuites name="pixel_world_contracts" tests="{total}" failures="{fails}" '
		f'skipped="{skips}" time="{meta.get("total_seconds", 0):.1f}">\n'
		f'<testsuite name="contract" tests="{total}" failures="{fails}" skipped="{skips}">\n'
		+ "\n".join(cases)
		+ "\n</testsuite>\n</testsuites>\n"
	)
	path.write_text(xml, encoding="utf-8")
	return path


def print_result_line(r: RunResult) -> None:
	"""沿用旧脚本的单行格式：[status] name (exit=N, Ns)。"""
	code = "?" if r.exit_code is None else str(r.exit_code)
	print(f"[{r.status}] {r.name} (exit={code}, {r.seconds:.0f}s)")
	if r.reason:
		print(f"    {r.reason}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_arg_parser() -> argparse.ArgumentParser:
	p = argparse.ArgumentParser(
		prog="run_contracts.py",
		description="pixel_world 契约测试统一运行器（元数据见 tests/contract_manifest.json）",
		formatter_class=argparse.RawDescriptionHelpFormatter,
	)
	p.add_argument("--test", nargs="+", metavar="NAME", help="按契约名选择（--list 查看）")
	p.add_argument("--group", nargs="+", metavar="GROUP|TAG", help="按 group 或 tag 选择")
	p.add_argument("--changed", nargs="*", metavar="FILE", help="按改动文件选择；无参数时自动取 git 工作树变更")
	p.add_argument("--all", action="store_true", help="选择全部契约")
	p.add_argument("--list", nargs="?", const="", metavar="子串", default=None,
				   help="列出契约（可带子串过滤）后退出；与其他选择 flag 互斥")
	p.add_argument("--dry-run", action="store_true", help="只打印将要执行的命令，不执行")
	p.add_argument("--jobs", type=int, default=1, metavar="N", help="并发数 1-4（默认 1；仅并发 parallel_safe 契约）")
	p.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, metavar="秒",
				   help=f"单契约超时（默认 CONTRACT_TIMEOUT 或 {DEFAULT_TIMEOUT}s）")
	p.add_argument("--out", default=None, metavar="目录", help="日志/汇总输出目录（默认 /tmp/contract_run_时间戳）")
	p.add_argument("--fast-fps", type=int, default=None, metavar="N", help="对 fast_flag_safe 契约附加 --fixed-fps N")
	p.add_argument("--disable-render-loop", action="store_true", help="对 fast_flag_safe 契约附加 --disable-render-loop")
	p.add_argument("--run-env-skip", action="store_true", help="实际执行 environment-skip 项（默认跳过并标记）")
	p.add_argument("--junit", action="store_true", help="额外输出 <out>/junit.xml")
	p.add_argument("--no-warmup", action="store_true", help="跳过跑前的 godot --import 预热")
	p.add_argument("--verbose", action="store_true", help="转发契约 stdout 到终端")
	p.add_argument("--backend", choices=["native", "gdtest"], default="native",
				   help="执行后端：native=每契约独立 godot --script（默认）；gdtest=有 gdtest 映射的契约走 gdtest 持久 worker（试点，见 tests/gdtest/）")
	p.add_argument("--gdtest", default=os.environ.get("GDTEST", "gdtest"), metavar="路径",
				   help="gdtest 可执行文件（--backend gdtest 时用；默认 GDTEST 环境变量或 PATH 上的 gdtest）")
	p.add_argument("--godot", default=DEFAULT_GODOT, metavar="路径", help="godot 可执行文件（默认 GODOT 环境变量或官方 .app 路径）")
	p.add_argument("--repo", default=str(REPO_ROOT), metavar="目录", help="项目根（默认脚本所在仓库根）")
	return p


def do_list(contracts: list[Contract], pattern: str) -> int:
	rows = [c for c in contracts if pattern in c.name or pattern in c.group or any(pattern in t for t in c.tags)]
	print(f"{'name':<34} {'group':<22} {'known_status':<17} {'par':<4} {'fast':<5} tags")
	for c in rows:
		par = "yes" if c.parallel_safe else "NO"
		fast = "yes" if c.fast_flag_safe else "NO"
		print(f"{c.name:<34} {c.group:<22} {c.known_status:<17} {par:<4} {fast:<5} {','.join(c.tags)}")
	print(f"\n共 {len(rows)} / {len(contracts)} 项（par=可并发, fast=可用加速 flag；探针默认不跑）")
	return 0


def resolve_selection(args, contracts: list[Contract]) -> tuple[Selection, list[str]]:
	notes: list[str] = []
	flags = [
		("test", args.test),
		("group", args.group),
		("changed", args.changed if args.changed is not None else None),
		("all", args.all),
	]
	active = [
		name for name, val in flags
		if val or (name == "changed" and args.changed is not None)
	]
	if args.list is not None:
		return Selection([]), notes
	if not active:
		raise ValueError("必须给出选择：--test / --group / --changed / --all 之一（或 --list）")
	sels: list[Selection] = []
	if args.test:
		sels.append(select_by_names(contracts, args.test))
	if args.group:
		sels.append(select_by_group(contracts, args.group))
	if args.changed is not None:
		changed = args.changed
		if not changed:
			changed = git_changed_files(Path(args.repo))
			notes.append(f"--changed 无参数，git 工作树变更 {len(changed)} 个文件:")
			for f in changed:
				notes.append(f"  {f}")
		sel = select_by_changed(contracts, changed, repo=Path(args.repo))
		sels.append(sel)
	if args.all:
		sels.append(Selection([c.name for c in contracts], {c.name: "--all" for c in contracts}))
	merged: dict[str, str] = {}
	for s in sels:
		for n, r in s.reasons.items():
			merged.setdefault(n, r)
	names = [c.name for c in contracts if c.name in merged]
	return Selection(names, merged), notes


def main(argv: Optional[list[str]] = None) -> int:
	args = build_arg_parser().parse_args(argv)
	if not 1 <= args.jobs <= 4:
		print("用法错误: --jobs 必须在 1-4 之间", file=sys.stderr)
		return 2
	if args.fast_fps is not None and args.fast_fps <= 0:
		print("用法错误: --fast-fps 必须为正整数", file=sys.stderr)
		return 2
	if args.backend == "gdtest" and shutil.which(args.gdtest) is None:
		print(f"用法错误: --backend gdtest 需要 gdtest 可执行（--gdtest 路径或 GDTEST 环境变量），未找到: {args.gdtest}",
			  file=sys.stderr)
		return 2
	try:
		raw, contracts = load_manifest()
	except (FileNotFoundError, json.JSONDecodeError, KeyError) as exc:
		print(f"manifest 错误: {exc}", file=sys.stderr)
		return 2
	for w in check_manifest_coverage(contracts):
		print(f"警告: {w}", file=sys.stderr)

	if args.list is not None:
		return do_list(contracts, args.list)

	try:
		selection, notes = resolve_selection(args, contracts)
	except ValueError as exc:
		print(f"用法错误: {exc}", file=sys.stderr)
		return 2
	except RuntimeError as exc:
		print(f"执行错误: {exc}", file=sys.stderr)
		return 1
	if not selection.names:
		print("选择为空：没有任何契约被选中（--changed 的路径全部无契约映射？）")
		return 0
	for note in notes:
		print(note)
	print(f"选中 {len(selection.names)} 个契约，jobs={args.jobs}, timeout={args.timeout}s, godot={args.godot}")
	if args.dry_run:
		for n in selection.names:
			c = next(x for x in contracts if x.name == n)
			if args.backend == "gdtest" and c.gdtest_file:
				cmd = build_gdtest_command(args.gdtest, args.godot, c, args.timeout)
				print(f"  {' '.join(cmd)}  [backend=gdtest]  # {selection.reasons.get(n, '')}")
				continue
			cmd, accelerated = build_command(args.godot, c, args.fast_fps, args.disable_render_loop)
			env_note = " [加速flag]" if accelerated else (" [不加速: fast_flag_safe=false]" if (args.fast_fps or args.disable_render_loop) else "")
			backend_note = " [backend=gdtest 无映射, native]" if args.backend == "gdtest" else ""
			skip_note = " [environment-skip, 不执行]" if c.known_status == "environment-skip" and not args.run_env_skip else ""
			print(f"  {' '.join(cmd)}{env_note}{backend_note}{skip_note}  # {selection.reasons.get(n, '')}")
		return 0

	out_dir = Path(args.out) if args.out else Path(tempfile.mkdtemp(prefix="contract_run_"))
	out_dir.mkdir(parents=True, exist_ok=True)
	started = time.monotonic()
	results, header = execute_selection(contracts, selection, args)
	total_seconds = time.monotonic() - started
	for line in header:
		print(line)
	for r in results:
		print_result_line(r)

	counts = {s: sum(1 for r in results if r.status == s) for s in STATUSES}
	meta = {
		"godot": args.godot,
		"jobs": args.jobs,
		"timeout": args.timeout,
		"backend": args.backend,
		"gdtest": args.gdtest if args.backend == "gdtest" else None,
		"fast_fps": args.fast_fps,
		"disable_render_loop": args.disable_render_loop,
		"run_env_skip": args.run_env_skip,
		"selected": len(selection.names),
		"out_dir": str(out_dir),
		"total_seconds": round(total_seconds, 1),
		"runner": "tools/run_contracts.py",
	}
	tsv = write_summary_tsv(out_dir, results)
	jsn = write_summary_json(out_dir, results, meta, contracts)
	print("\n汇总: " + ", ".join(f"{s}={counts[s]}" for s in STATUSES if counts[s]))
	print(f"日志目录: {out_dir}")
	print(f"汇总: {tsv} | {jsn}")
	if args.junit:
		junit = write_junit(out_dir, results, meta)
		print(f"JUnit: {junit}")
	bad = counts["fail"] + counts["timeout"] + counts["executor-error"]
	return 1 if bad else 0


if __name__ == "__main__":
	sys.exit(main())
