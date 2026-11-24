#!/usr/bin/env bash
# One-shot pipeline: character image -> 45deg/side view -> 3x3 safe-area grid -> looping action video.
# Run from the project root (needs .libtv/project.json, i.e. `libtv project use <uuid>` done).
#
#   bash .agents/skills/character-action-loop-3x3/scripts/generate.sh \
#     --image path/to/char.png --name thief --char 盗贼 --weapon 匕首 \
#     [--view 45|side] [--duration 5] [--resolution 480P] [--model "Wan 3.0"] \
#     [--fill 0.5] [--ground 0.78] [--xoff -0.05] [--outdir assets/actions/thief] [--skip-view view.png]
set -euo pipefail
S="$(cd "$(dirname "$0")" && pwd)"
T="$S/../templates"

IMAGE=""; NAME=""; CHAR="角色"; WEAPON="武器"; VIEW="45"; DURATION=5; RES="480P"
MODEL="Wan 3.0"; FILL=0.5; GROUND=0.78; XOFF=-0.05; OUTDIR=""; SKIP_VIEW=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMAGE="$2"; shift 2;;   --name) NAME="$2"; shift 2;;
    --char) CHAR="$2"; shift 2;;     --weapon) WEAPON="$2"; shift 2;;
    --view) VIEW="$2"; shift 2;;     --duration) DURATION="$2"; shift 2;;
    --resolution) RES="$2"; shift 2;; --model) MODEL="$2"; shift 2;;
    --fill) FILL="$2"; shift 2;;     --ground) GROUND="$2"; shift 2;;
    --xoff) XOFF="$2"; shift 2;;     --outdir) OUTDIR="$2"; shift 2;;
    --skip-view) SKIP_VIEW="$2"; shift 2;;
    *) echo "unknown arg $1"; exit 1;;
  esac
done
[[ -n "$NAME" ]] || { echo "--name required"; exit 1; }
[[ -n "$IMAGE" || -n "$SKIP_VIEW" ]] || { echo "--image or --skip-view required"; exit 1; }
OUTDIR="${OUTDIR:-.tmp/action_loop/$NAME}"; mkdir -p "$OUTDIR"
TS=$(date +%m%d%H%M%S)   # node names must be unique on the canvas
url_of() { python3 -c "import json,sys;d=json.loads(open(sys.argv[1]).read().strip().splitlines()[-1]);print(d['data']['url'][0])" "$1"; }

if [[ "$VIEW" == "side" ]]; then
  VIEW_TXT="标准侧面"; VIEW_DETAIL="身体完全朝向画面右侧（纯右侧视角，90度侧身）"; VIEW_SHORT="朝右侧身"
else
  VIEW_TXT="3/4斜侧面"; VIEW_DETAIL="身体朝向画面右前方，约45度斜侧视角（能同时看到脸部正面和侧面）"; VIEW_SHORT="45度斜侧身朝右前方"
fi

# 1) view image
if [[ -n "$SKIP_VIEW" ]]; then
  cp "$SKIP_VIEW" "$OUTDIR/view.png"
else
  REF="${NAME}_ref_$TS"; VIEWN="${NAME}_view_$TS"
  libtv upload "$REF" -t image -f "$IMAGE" >/dev/null
  P=$(sed -e "s|{REFS}|{{Node \"$REF\"}}|" -e "s|{VIEW}|$VIEW_TXT|" -e "s|{VIEW_DETAIL}|$VIEW_DETAIL|" "$T/view_prompt.txt")
  echo "[1/4] generating $VIEW_TXT view ..."
  libtv node create "$VIEWN" -t image -s "model=Lib Image 2.6 Pro" -s modeType=image2image \
    -s ratio=1:1 -s resolution=2K -s quality=high --left "$REF" --prompt "$P" --run > "$OUTDIR/view.json"
  curl -sL -o "$OUTDIR/view.png" "$(url_of "$OUTDIR/view.json")"
fi

# 2) grid with safe area
echo "[2/4] building 3x3 grid ..."
python3 "$S/make_grid.py" "$OUTDIR/view.png" "$OUTDIR/grid.png" --n 3 --size 1440 --fill "$FILL" --ground "$GROUND" --xoff "$XOFF"

# 3) video (Wan 3.0 mixed2video; its frames2video mode fails server-side as of 2026-11)
GRIDN="${NAME}_grid_$TS"; ANIMN="${NAME}_anim_$TS"
libtv upload "$GRIDN" -t image -f "$OUTDIR/grid.png" >/dev/null
VP=$(sed -e "s|{FIRST}|$GRIDN|" -e "s|{VIEW_SHORT}|$VIEW_SHORT|g" -e "s|{CHAR}|$CHAR|" -e "s|{WEAPON}|$WEAPON|g" "$T/video_prompt.txt")
echo "[3/4] generating ${DURATION}s video with $MODEL ..."
EXTRA=()
[[ "$MODEL" == Wan* ]] && EXTRA=(-s enableSound=off)
libtv node create "$ANIMN" -t video -s "model=$MODEL" -s modeType=mixed2video -s count=1 -s ratio=1:1 \
  -s resolution="$RES" -s duration="$DURATION" "${EXTRA[@]}" --left "$GRIDN" --prompt "$VP" --run > "$OUTDIR/anim.json"
curl -sL -o "$OUTDIR/anim.mp4" "$(url_of "$OUTDIR/anim.json")"

# 4) post-process
echo "[4/4] post-processing ..."
python3 "$S/postprocess.py" "$OUTDIR/anim.mp4" "$OUTDIR"
echo "done -> $OUTDIR (view.png grid.png anim.mp4 seamless.mp4 timeline.png)"
