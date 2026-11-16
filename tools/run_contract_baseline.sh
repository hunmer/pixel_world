#!/usr/bin/env bash
# run_contract_baseline.sh — 全量契约基线（兼容包装：内部委托 tools/run_contracts.py）。
# Usage: tools/run_contract_baseline.sh [output_dir]   (default: /tmp/contract_baseline_<ts>)
#
# 兼容性保留：
#   - 参数 [output_dir]、环境变量 GODOT / CONTRACT_TIMEOUT 语义不变；
#   - <out>/<name>.log 逐契约日志、summary.tsv 的 4 列 name/exit_code/seconds/status 不变；
#   - 逐契约单行输出 "[status] name (exit=N, Ns)" 不变。
# 差异（改进）：
#   - 状态新增 environment-skip / executor-error（旧脚本把它们误记为 fail/timeout）；
#   - --run-env-skip 使旧基线"什么都跑"的语义保持，但已知环境项挂/超时不再计为真实失败；
#   - 退出码：存在真实 fail/timeout/executor-error 时为 1（旧脚本恒 0）。
# 新推荐（跳过环境项、并发、JUnit）：见 docs/test_automation_results.md。
set -u
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/contract_baseline_$(date +%Y%m%d_%H%M%S)}"
export GODOT

cd "$ROOT"
python3 tools/run_contracts.py --all --run-env-skip --jobs 1 --out "$OUT"
code=$?
echo "logs in $OUT"
exit $code
