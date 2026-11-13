#!/bin/bash
# gen_turnarounds.sh — 用 Lib Image 2.6 Pro 批量生成剩余 7 角色三视图（成人比例约束版）
set -u
export PATH="/Users/Zhuanz/.libtv:$PATH"
cd "$(dirname "$0")/../.."
BASE=assets/units

STYLE="IMPORTANT proportions: semi-realistic anime adult, realistic adult head-to-body ratio (about 1:7.5), long limbs, adult body structure. STRICTLY NOT chibi, NOT super-deformed, NOT big-head style, no oversized round child eyes. Clean lineart, flat cel shading with hard shadow edges, consistent identical design across all three views, professional anime production reference sheet, plain white background."

gen() { # $1=key $2=desc
	local key="$1" dir="$BASE/$1"
	mkdir -p "$dir"
	local node="${key}_三视图"
	echo "=== $key ==="
	libtv node create "$node" -t image \
		--prompt "Character design reference sheet, anime cel-shading style: three-view turnaround of ONE character — front view, side profile view, back view — standing full-body, aligned on one horizontal baseline. $2 $STYLE" \
		--set "model=Lib Image 2.6 Pro" --set ratio=16:9 --run >/dev/null 2>&1
	local url
	url=$(libtv node "$node" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const u=JSON.parse(s).data.url;console.log(Array.isArray(u)?u[0]:"")}catch(e){}})')
	if [ -z "$url" ]; then echo "  FAIL: no url"; return 1; fi
	curl -fsSL -o "$dir/${key}_turnaround.png" "$url" && echo "  OK: $dir/${key}_turnaround.png"
}

gen hero "Character: young man of 24, apparent age mid-20s, short dark chestnut-brown hair, grey-blue eyes, a old knife scar on his left brow. Wearing silver-white light plate armor of a merchant-league knight order, a family crest brooch on his chest (only relic of his burned home). Lean build, not bulky. Calm, responsible, quietly resolute expression of a young commander."
gen veteran "Character: veteran soldier man of 38, apparent age late 30s, military-cut short golden-blond hair, dark green eyes, an old scar running across his right cheek down to the neck. Tall and heavily muscled. Wearing polished old-issue heavy plate armor of a league city-state, well maintained, slightly worn. Upright stern disciplined posture of a career centurion."
gen mercenary "Character: mercenary archer man of 26, messy dark-brown hair, brown eyes always half-lidded, stubble on chin. Wearing faded washed-out leather armor, a longbow slung diagonally across his back, a coin pouch and wine flask at his belt, his left index finger slightly crooked from years of drawing the bowstring. Cynical relaxed smirk, worldly carefree stance."
gen pegasus "Character: pegasus knight young woman of 21, apparent age early 20s, light golden hair in a long braid, emerald green eyes. Wearing silver-white light cavalry armor with a distinctive feathered wing cloak of pegasus knights, a small silver earring on her right ear. Energetic, hot-headed, confident bright expression. (No mount — character only.)"
gen priest "Character: army priest man appearing about 40, short grey-white hair, unusually calm amber eyes. Wearing plain white long robes, a rosary of magic beads at his waist, carrying an old staff he never draws. Fine silver magic lines on both hands. Gentle warm smile that never reaches his eyes, serene detached bearing."
gen hierarch "Character: theocratic hierarch man of 65, apparent age senior, long silver-white hair neatly combed back, pale gold eyes with a faint crystalline gleam. Wearing a white-and-gold robe embroidered with golden thread, holding an ornate staff studded with many small glowing elf crystals. Kind fatherly warm sincere smile — sincere, which makes him more terrifying. Imposing serene bearing of a supreme religious ruler."
gen demon "Character: demon-possessed warrior emperor man of 55, apparent age senior but powerfully built, steel-grey short hair swept back, ice-blue eyes with faint red rim around the pupils. Huge wall-like muscular frame in full pitch-black heavy armor of an empire, double-headed eagle on the shoulder pauldrons darkened by blood rust, a cracked burn-scar demon contract mark on his left chest spreading like vines. Cold severe iron-willed expression of a tragic tyrant."
echo "ALL DONE"
