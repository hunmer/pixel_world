# The charge recipe (motes spiralling in, pulse rings collapsing onto a layered ball with flickering rays, short
# crackling sparks) is adapted from Sprite Fusion's open-source energy charge
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/spell-charge.js@c59d187dbba27d6926385f9977b1758587605eb0
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

const D := 1.6
const HX := 15.0
const HY := -22.0
const RINGS := 4
const RT := 0.5

static var meta := {
	"name": "Spell charge",
	"desc": "Energy gathers in the caster's hand: streaks and motes spiral in, rings collapse into a swelling orb that crackles with arcs, ready to fire.",
	"tags": ["arcane", "charge", "spell", "orb", "cast", "magic", "loop"],
	"size": [120, 86],
	"origin": [44, 80],
	"duration": D,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Px.PAL.arcane, "seed": 5},
}

static var HOLD := Px.merge(Px.READY, {"x": -3, "crouch": 4, "lean": 2, "fx": 18, "fy": -22, "bx": 11, "by": -17, "ffx": 10, "fbx": -8})
static var act := {
	"poses": [
		[-0.46, Px.merge(Px.READY, {"x": -3})],
		[-0.12, Px.merge(HOLD, {"crouch": 3})],
		[0, HOLD],
		[0.4, Px.merge(HOLD, {"crouch": 5})],
		[0.8, Px.merge(HOLD, {"lean": 3})],
		[1.2, Px.merge(HOLD, {"crouch": 5})],
		[1.6, HOLD],
	],
}

# each ring is born at k * D / RINGS and lands RT later; the times it lands, wrapped into the loop
static var landings := Px.arr(RINGS, func(k): return (k * D) / RINGS + RT)
static func sinceLast(t: float) -> float:
	return landings.map(func(l): return fmod(fmod(t - l, D) + D, D)).min()


static func orb(p: Px.Painter, C: Array, x: float, y: float, r: float, t: float, ph: float) -> void:
	# rays flickering round the ball, turning three steps a loop
	for i in 8:
		var a := (i / 8.0) * TAU + ph * (TAU / 8.0) * 3.0
		var l := (1.5 + 4.5 * absf(Px.loopNoise(ph, 3.0, i * 7 + 1))) * (0.7 if i % 2 else 1.0)
		var x0 := x + cos(a) * (r + 1.2)
		var y0 := y + sin(a) * (r + 1.2)
		p.line(x0, y0, x0 + cos(a) * l, y0 + sin(a) * l, func(u: float) -> int: return C[6] if u < 0.4 else (C[4] if i % 2 else C[5]), func(u: float) -> float: return 1.0 if u < 0.6 else 1.6 - u)
	# the ball: a violet rim, a bright body lit from the top left, a big white heart
	p.circle(x, y, r + 1.3, C[4])
	p.circle(x, y, r + 0.3, C[5])
	p.circle(x - r * 0.12, y - r * 0.12, r * 0.8, C[6])
	p.circle(x, y, r * 0.5, WHITE)
	# filaments crackling out from the heart through the body to the shell, new ones every other frame
	var R := Px.rng(floorf(t * 15.0), 77)
	for i in 3:
		var a := R.range(0.0, TAU)
		var pts: Array = Lib.arc(R, x + cos(a) * r * 0.4, y + sin(a) * r * 0.4, x + cos(a + R.range(-0.6, 0.6)) * (r + 0.6), y + sin(a + R.range(-0.6, 0.6)) * (r + 0.6), {"jag": 0.45, "forks": 0.0})[0].pts
		p.polyline(pts, func(u: float) -> int: return WHITE if u < 0.6 else C[6])
	# a glint on the shell
	p.px(x - r * 0.5, y - r * 0.62, WHITE)


static func ringAt(p: Px.Painter, C: Array, x: float, y: float, rr: float, sy: float, rot: float, q: float) -> void:
	var n := ceili(rr * TAU * 1.4)
	var c := cos(rot)
	var s := sin(rot)
	var col: int = WHITE if q > 0.85 else (C[6] if q > 0.55 else C[5])
	var a := minf(1.0, q * 3.0)
	for j in n:
		var g := (float(j) / n) * TAU
		var lx := cos(g) * rr
		var ly := sin(g) * rr * sy
		var px := x + lx * c - ly * s
		var py := y + lx * s + ly * c
		if py > -0.5:
			continue  # the floor hides the bottom of a big ring
		p.dot(px, py, col, a)
		if j % 10 == 0:
			p.glow(px, py, 5.0, C[5], 0.12 * a)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var S: float = o.seed
	var f := floori(t * 30.0)
	var since := sinceLast(t)
	var swell := exp(-pow(since / 0.07, 2.0)) + 0.5 * exp(-pow(since / 0.18, 2.0))
	var r := 6.1 + 0.5 * sin(ph * TAU * 4.0) + 1.4 * swell
	# unstable: it shivers a pixel as each ring lands
	var jit := (1.0 if f % 2 else -1.0) if swell > 0.4 else 0.0
	var x := HX + jit
	var y := HY

	# streaks spiralling in from all round, faster as they near the hand
	Px.cycle(t, D, 110, S * 3.0 + 1.0, func(g: Px.Rng) -> float: return g.range(0.2, 0.34), func(age: float, life: float, R: Px.Rng) -> void:
		# they come from the left, above and the upper right; the swirl would carry the rest into the floor
		var a0 := R.range(2.8, 5.75)
		var d0 := R.range(20.0, 52.0)
		var spin := R.range(0.6, 1.3)
		var pos := func(q: float) -> Array:
			var a := a0 + spin * q * q
			var d := d0 * (1.0 - q * q) + r
			return [HX + cos(a) * d, HY + sin(a) * d * 0.92]
		var q := age / life
		var pp: Array = pos.call(q)
		var qq: Array = pos.call(minf(1.0, q + 0.02))
		var px: float = pp[0]
		var py: float = pp[1]
		var qx: float = qq[0]
		var qy: float = qq[1]
		# their light dies as they reach the orb, so it isn't washed out by them
		Lib.streak(p, px, py, (qx - px) / (0.02 * life), (qy - py) / (0.02 * life), C[6] if R.chance(0.55) else C[5], minf(1.0, q * 4.0) * (1.0 - Px.smooth(0.9, 1.0, q)), 7.0, 0.4 * (1.0 - Px.smooth(0.6, 0.9, q))))
	# slower motes, drifting in on the same swirl
	Px.cycle(t, D, 56, S * 3.0 + 2.0, func(g: Px.Rng) -> float: return g.range(0.4, 0.7), func(age: float, life: float, R: Px.Rng) -> void:
		var a0 := R.range(2.6, 5.2)
		var d0 := R.range(12.0, 32.0)
		var spin := R.range(1.0, 2.2)
		var size := R.range(0.6, 1.0)
		var pos := func(q: float) -> Array:
			var a := a0 + spin * q
			var d := d0 * (1.0 - Px.Ease.inQuad(q)) + r
			return [HX + cos(a) * d, HY + sin(a) * d]
		var q := age / life
		var pp: Array = pos.call(q)
		var qq: Array = pos.call(minf(1.0, q + 0.02))
		var px: float = pp[0]
		var py: float = pp[1]
		var qx: float = qq[0]
		var qy: float = qq[1]
		Lib.mote(p, px, py, (qx - px) / (0.02 * life), (qy - py) / (0.02 * life), R.pick([C[5], C[6], C[6], WHITE]), size, minf(1.0, q * 3.0) * ((1.0 - q) / 0.1 if q > 0.9 else 1.0), 0.3 * (1.0 - Px.smooth(0.55, 0.85, q))))

	# rings collapsing onto the orb, each tilted its own way
	for k in RINGS:
		for off in [-D, 0.0]:
			var q: float = (t - (k * D) / RINGS - off) / RT
			if q < 0.0 or q >= 1.0:
				continue
			var rr := r + 1.5 + 22.0 * (1.0 - Px.Ease.inQuad(q))
			var shape: Array = [[1.0, 0.0], [0.38, 0.55], [1.0, 0.0], [0.42, -0.7]][k]
			ringAt(p, C, x, y, rr, shape[0], shape[1], q)

	orb(p, C, x, y, r, t, ph)

	# arcs crackling off it, new ones every other frame
	var w := floori(f / 2.0)
	var Rw := Px.rng(S, w, 3)
	var n := (1 if Rw.next() < 0.6 else 0) + (1 if swell > 0.3 else 0)
	var fresh := 0.8 if f % 2 == 0 else 0.4
	for i in n:
		var a := Rw.range(0.0, TAU)
		var L := Rw.range(5.0, 10.0) * (1.0 + swell * 0.4)
		var a1 := a + Rw.range(-0.5, 0.5)
		var x0 := x + cos(a) * (r + 0.5)
		var y0 := y + sin(a) * (r + 0.5)
		var x1 := x0 + cos(a1) * L
		var y1 := minf(-2.0, y0 + sin(a1) * L)
		Lib.drawArc(p, Lib.arc(Rw, x0, y0, x1, y1, {"jag": 0.35, "forks": 1.0 if Rw.next() < 0.5 else 0.0}), {"core": WHITE, "body": C[5], "halo": C[3], "glow": C[5]}, fresh, 0.3)
	# glints winking round it
	Px.cycle(t, D, 7, S * 3.0 + 4.0, 0.22, func(age: float, life: float, R: Px.Rng) -> void:
		var a := R.range(0.0, TAU)
		var d := R.range(r + 5.0, r + 15.0)
		var k := sin((age / life) * PI)
		Px.sparkle(p, x + cos(a) * d, y + sin(a) * d * 0.9, 1.0 + 2.5 * k, C[6], C[4], 0.4 * k))
	if since < 0.07:
		Px.sparkle(p, x, y, 4.0 + 6.0 * (1.0 - since / 0.07), C[6], C[5], 0.5)

	# light: a wide pool that lights the caster, a hot heart, the floor beneath the hand
	var pulse := 0.85 + 0.15 * sin(ph * TAU * 4.0) + 0.2 * swell
	p.glow(x, y, 46.0, C[4], 0.26 * pulse)
	p.glowRing(x, y, r + 3.0, 8.0, C[5], 0.3 * pulse)
	p.glow(x, y, r, C[6], 0.12)
	p.glow(HX, -1.0, 22.0, C[5], 0.16 * pulse)
