#!/usr/bin/env bash
# run_contract_baseline.sh — run every tests/*_contract.gd headless, record name/exit/duration.
# Usage: tools/run_contract_baseline.sh [output_dir]   (default: /tmp/contract_baseline_<ts>)
set -u
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/contract_baseline_$(date +%Y%m%d_%H%M%S)}"
TIMEOUT="${CONTRACT_TIMEOUT:-900}"
mkdir -p "$OUT"

cd "$ROOT"
LOG="$OUT/summary.tsv"
echo -e "name\texit_code\tseconds\tstatus" > "$LOG"

for f in tests/*_contract.gd; do
	name="$(basename "$f" _contract.gd)"
	start=$(date +%s)
	"$GODOT" --headless --path . --script "res://$f" >"$OUT/$name.log" 2>&1 &
	pid=$!
	( sleep "$TIMEOUT"; kill -TERM $pid 2>/dev/null ) &
	wd=$!
	wait $pid
	code=$?
	kill -TERM $wd 2>/dev/null; wait $wd 2>/dev/null
	[ $code -eq 143 ] && code=124
	end=$(date +%s)
	dur=$((end - start))
	if [ $code -eq 124 ]; then st="timeout"; else st="fail"; [ $code -eq 0 ] && st="pass"; fi
	echo -e "$name\t$code\t$dur\t$st" >> "$LOG"
	echo "[$st] $name (exit=$code, ${dur}s)"
done

echo "---- summary ----"
awk -F'\t' 'NR>1{c[$4]++}END{for(k in c)print k,c[k]}' "$LOG"
echo "logs in $OUT"
