#!/bin/bash
# split_voices.sh — 按 1s 静音把 *_battle_voices_ja.wav 切成 7 条独立语音，保留源文件
set -euo pipefail
cd "$(dirname "$0")/../../assets/audio/voice"
OUT=cut
mkdir -p "$OUT"

CHARS="elf_companion hero veteran mercenary pegasus priest hierarch demon"
# 表情顺序与生成模板一致
declare -a EMOS=(attack hurt confused laugh shy cry panic)

for c in $CHARS; do
  src="${c}_battle_voices_ja.wav"   # 源命名：elf_companion 前缀 voice_，其余也是 voice_
  src="voice_${src}"
  [ -e "$src" ] || { echo "MISS $src"; continue; }
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src")
  # silencedetect：阈值 -35dB，最短 0.45s（中间停顿约 1s；语音内短促换气应低于此时长）
  sil=$(ffmpeg -hide_banner -i "$src" -af silencedetect=noise=-35dB:d=0.45 -f null - 2>&1 | grep -E 'silence_(start|end)')
  # 解析静音区间 → 语音段 [start,end]
  segs=()
  starts=() ends=()
  s=""
  while read -r line; do
    case "$line" in
      *silence_start*) s=${line##*silence_start: };;
      *silence_end*)
        e=${line##*silence_end: }; e=${e%% *}
        starts+=("$s"); ends+=("$e")
        ;;
    esac
  done <<< "$sil"
  # 语音段：文件头→首个静音开始；每静音结束→下一静音开始；末静音结束→文件尾
  idx=0
  total=${#starts[@]}
  for i in "${!EMOS[@]}"; do
    emo=${EMOS[$i]}
    if [ "$i" -eq 0 ]; then a=0; else a=${ends[$((i-1))]}; fi
    b=${starts[$i]:-$dur}
    awk -v a="$a" -v b="$b" 'BEGIN{exit !(b-a>0.3)}' || { echo "  SKIP $c/$emo (seg too short a=$a b=$b)"; continue; }
    idx=$((idx+1))
    dst="$OUT/voice_${c}_${emo}.wav"
    ffmpeg -hide_banner -loglevel error -ss "$a" -to "$b" -i "$src" -c copy "$dst"
    d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dst")
    echo "  $dst  ${d}s"
  done
done
