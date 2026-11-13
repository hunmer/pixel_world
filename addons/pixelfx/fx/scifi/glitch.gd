# port-of: src/fx/scifi/glitch.js@55da9344b2f859b41d3970892c50d8daec636bf6
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Glitch",
	"desc": "The hero's signal breaks up in bursts: an RGB split, slices torn sideways, rows smeared out, junk blocks and dead pixels, then snaps back clean.",
	"tags": ["scifi", "glitch", "digital", "corrupt", "hologram", "status", "loop"],
	"size": [88, 64],
	"origin": [44, 54],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#14101f", "#3b1f5c", "#ff2e63", "#ff7aa8", "#2ef2ff", "#b4fbff", "#ffffff"], "seed": 7},
}

static var TWITCH_A := {"turn": 0.3, "lean": 3, "crouch": 1, "fx": 13, "fy": -31, "bx": 6, "by": -14, "hx": 1}
static var TWITCH_B := {"turn": 1.2, "lean": -3, "crouch": 0, "fx": -9, "fy": -14, "bx": 14, "by": -31, "hx": -1}
static var FINE := {}
static var act := {
	"onBody": true,
	"poses": [
		[0, FINE],
		[0.3, TWITCH_A, "snap"],
		[0.37, TWITCH_B, "snap"],
		[0.44, TWITCH_A, "snap"],
		[0.53, FINE, "snap"],
		[1.1, TWITCH_B, "snap"],
		[1.23, FINE, "snap"],
		[1.7, TWITCH_A, "snap"],
		[1.8, Px.merge(TWITCH_B, {"crouch": 3}), "snap"],
		[1.9, TWITCH_A, "snap"],
		[2, TWITCH_B, "snap"],
		[2.07, FINE, "snap"],
		[2.4, FINE],
	],
}

const FPS := 30
static var NF := Px.roundi(meta.duration * FPS)
# the bursts: [first frame, last frame, how hard]
const BURSTS := [[9, 16, 0.8], [33, 37, 0.5], [51, 62, 1.0]]


# the effect draws the hero itself, clean or broken
static func actorAlpha(_t: float, _o: Dictionary) -> float:
	return 0.0


# r(...n) = rand(S, f, ...n)
static func r(S: float, f: int, a: Variant, b: Variant = Px.NA) -> float:
	return Px.rand(S, f, a, b)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 7)
	var A: Dictionary = o.actor
	var S: float = o.seed
	var RED: int = C[2]
	var CYAN: int = C[4]
	var f := floori(t * FPS + 1e-6) % NF
	var Ax: int = A.x
	var Ay: int = A.y
	var Aw: int = A.w
	var Ah: int = A.h
	var data: PackedByteArray = A.mask.data
	var pixels: PackedInt32Array = A.pixels
	var burst: Variant = null
	for bb: Array in BURSTS:
		if f >= bb[0] and f <= bb[1]:
			burst = bb
			break
	var k: float = burst[2] if burst else 0.0
	# what this frame's corruption is
	var split: float = Px.round(1.0 + r(S, f, 1) * 3.0 * k) * (-1.0 if r(S, f, 2) < 0.5 else 1.0) if burst else 0.0
	var tears := []
	if burst:
		var nt := 1 + floori(r(S, f, 3) * 4.0 * k)
		for i in nt:
			tears.append([Ay + floori(r(S, f, 4, i) * Ah), 1 + floori(r(S, f, 5, i) * 5.0), Px.round((r(S, f, 6, i) - 0.5) * 16.0 * k), r(S, f, 7, i)])
	# a lone row slips now and then even when it's calm
	if not burst and r(S, f, 8) < 0.07:
		tears.append([Ay + floori(r(S, f, 9) * Ah), 1, -2.0 if r(S, f, 10) < 0.5 else 2.0, 1.0])
	var interlace: bool = burst != null and r(S, f, 11) < 0.3
	var roll: int = -2 - floori(r(S, f, 13) * 2.0) if (burst != null and r(S, f, 12) < 0.15) else 0
	var poster: bool = burst != null and r(S, f, 14) < 0.15 * k
	var tearAt := func(y: int) -> Variant:
		for tr: Array in tears:
			if y >= tr[0] and y < tr[0] + tr[1]:
				return [tr[2], tr[3]]
		return null
	# the calm signal: a faint bar rolling down the body
	var bar: float = Ay + fmod((t / meta.duration) * 2.0 * (Ah + 12), Ah + 12) - 6.0

	# the split: the red and cyan ghosts first, offset either side
	if split:
		for my in Ah:
			for mx in Aw:
				if not data[my * Aw + mx]:
					continue
				var y := Ay + my + roll
				var tr: Variant = tearAt.call(Ay + my)
				var dx: float = tr[0] if tr else 0.0
				p.px(Ax + mx + dx - split, y, RED)
				p.px(Ax + mx + dx + split, y, CYAN)
	# the body itself, row by row: torn, interlaced, rolled, posterised, tinted where the bar passes
	for my in Ah:
		var ry := Ay + my
		var y := ry + roll
		if interlace and (my & 1):
			continue
		var tr: Variant = tearAt.call(ry)
		var dx: float = tr[0] if tr else 0.0
		var tint: int = (RED if tr[1] < 0.18 else CYAN) if (tr and tr[1] < 0.35) else 0
		var near := absf(ry - bar)
		for mx in Aw:
			var c := pixels[my * Aw + mx]
			if not c:
				continue
			var col := c
			if poster:
				col = C[5] if Px.luma(c) > 0.32 else C[1]
			elif tint:
				col = Px.mix(c, tint, 0.6)
			elif near < 1.0:
				col = Px.mix(c, C[5], 0.35)
			p.px(Ax + mx + dx, y, col)
		# a torn row smears its edge pixel out sideways, fading
		if tr and absf(dx) > 2.0 and Px.rand(S, f, ry) < 0.6:
			var right := dx > 0.0
			var fi := -1
			for i in Aw:
				if (data[my * Aw + Aw - 1 - i] if right else data[my * Aw + i]):
					fi = i
					break
			var mx := Aw - 1 - fi if right else fi
			if mx >= 0 and mx < Aw:
				var c := pixels[my * Aw + mx]
				var L := 4 + floori(Px.rand(S, f, ry, 1) * 10.0)
				for i in range(1, L + 1):
					p.dot(Ax + mx + dx + (i if right else -i), y, c, 1.0 - i / float(L + 1))
	# a roll leaves the top slice repeated at the bottom
	if roll:
		for my in -roll:
			for mx in Aw:
				var c := pixels[my * Aw + mx]
				if c and ((mx + my) & 1):
					p.px(Ax + mx, Ay + Ah + roll + my, Px.mix(c, C[1], 0.5))
	# junk blocks round the body
	if burst:
		var nj := 2 + floori(r(S, f, 20) * 5.0 * k)
		for i in nj:
			var w := 2 + floori(r(S, f, 21, i) * 9.0)
			var h := 1 + floori(r(S, f, 22, i) * 3.0)
			var x := Ax - 6 + floori(r(S, f, 23, i) * (Aw + 12))
			var y := Ay + floori(r(S, f, 24, i) * Ah)
			var c: int = [WHITE, RED, CYAN, C[5], C[3]][floori(r(S, f, 25, i) * 5.0)]
			if r(S, f, 26, i) < 0.4:
				for yy in h:
					for xx in w:
						p.px(x + xx, y + yy, c if (xx + yy) & 1 else C[0])
			else:
				p.rect(x, y, w, h, c)
	# dead pixels thrown off by a burst, drifting and blinking out
	for bb: Array in BURSTS:
		var a: int = bb[0]
		var b: int = bb[1]
		var kk: float = bb[2]
		var age := (f - a + NF) % NF
		if age > b - a + 8:
			continue
		var i := 0
		while i < 10.0 * kk:
			var life := 4 + floori(Px.rand(S, a, i) * 6.0)
			var at := floori(Px.rand(S, a, i, 1) * (b - a + 1))
			var q := age - at
			if q < 0 or q > life or (q > life / 2.0 and (q & 1)):
				i += 1
				continue
			var x0 := Ax + Px.rand(S, a, i, 2) * Aw
			var y0 := Ay + Px.rand(S, a, i, 3) * Ah
			var side := -1.0 if Px.rand(S, a, i, 4) < 0.5 else 1.0
			p.px(x0 + side * q * (1.0 + Px.rand(S, a, i, 5) * 2.0), y0 - q * 0.5, [WHITE, RED, CYAN][i % 3])
			i += 1
	# light: a cold flicker in the bursts, the split's colors glowing at its edges
	if burst:
		if f == burst[0]:
			p.glow(Ax + Aw / 2.0, Ay + Ah / 2.0, 26.0, C[5], 0.4)
		p.glow(Ax + Aw / 2.0 - split * 4.0, Ay + Ah / 2.0, 18.0, RED, 0.18 * k)
		p.glow(Ax + Aw / 2.0 + split * 4.0, Ay + Ah / 2.0, 18.0, CYAN, 0.18 * k)
	if absf(bar - (Ay + Ah / 2.0)) < Ah / 2.0 + 3.0:
		p.glowLine(Ax - 2.0, bar, Ax + Aw + 2.0, bar, 4.0, C[4], 0.12)
