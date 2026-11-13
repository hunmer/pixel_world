# port-of: src/fx/critters/snake.js@d9fc950685332b36a9f76633d83e5214dcca7d76
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P

static var meta := {
	"name": "Snake",
	"desc": "A snake slithers along the floor, head raised: humps rise and roll back down its patterned body to the tail, dust puffs where it touches down, its forked tongue flicks.",
	"tags": ["critter", "snake", "reptile", "ground", "loop"],
	"size": [136, 56],
	"origin": [68, 48],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#081410", "#123a1e", "#1d5e2a", "#2f8a36", "#5cb848", "#a8e070", "#e8ffc0"],
		"belly": ["#4a3a14", "#b08a34", "#f0d878"],
		"seed": 1,
	},
}

static var D: float = meta.duration
const HEAD := 30.0
const LEN := 70.0
static var GRID := Lib.Grid.new(-44, -24, 88, 26)
static var SWARM := Lib.Swarm.new()
static var TONGUE := Px.hex("#e8304a")
static var DUST := Px.hex("#8a7f92")
const K := TAU / 30.0
static var W := (TAU * 2.0) / D


# the body's centre height u px behind the head: humps rolling back toward the tail, the neck raised to the head
static func lift(u: float, t: float) -> float:
	var wave := maxf(0.0, sin(K * u - W * t)) ** 0.85
	var env := Px.smooth(8.0, 18.0, u) * (1.0 - Px.smooth(LEN - 14.0, LEN - 2.0, u))
	var neck := 6.0 * (1.0 - u / 12.0) ** 2 if u < 12.0 else 0.0
	return 7.0 * wave * env + neck


static func radius(u: float) -> float:
	return 3.3 if u < 6.0 else Px.lerp(3.4, 0.6, ((u - 6.0) / (LEN - 6.0)) ** 1.3)


# the head's bob with the rhythm, and the tongue's flicks: two bursts of three a loop
static func bob(t: float) -> float:
	return 0.8 * sin(W * t)


static func tongue(t: float) -> float:
	for t0 in [0.3, 1.5]:
		var k: float = (t - t0) / 0.5
		if k >= 0.0 and k < 1.0:
			return maxf(0.0, sin(k * PI * 3.0)) ** 0.6
	return 0.0


static func snake(g: Lib.Grid, C: Array, B: Array, t: float) -> void:
	g.clear()
	var hb := bob(t)
	# the body, column by column from the tail to the neck: lit along its back, a gold belly, dark diamonds, glints on the humps
	var u := LEN
	while u >= 2.0:
		var x := HEAD - u
		var r0 := radius(u)
		var cy := -r0 - lift(u, t) + (hb * (1.0 - u / 12.0) if u < 12.0 else 0.0)
		var hump := lift(u, t)
		# keep the body as thick across its slope as along the floor
		var slope := (lift(u + 0.5, t) - lift(u - 0.5, t))
		var r := r0 * sqrt(1.0 + slope * slope)
		var y := floorf(cy - r)
		while y <= ceilf(cy + r):
			var v := (y + 0.5 - cy) / r
			if absf(v) > 1.0:
				y += 1.0
				continue
			var c: int = C[4] if v < -0.5 else (C[3] if v < 0.1 else (C[2] if v < 0.45 else (B[1] if v < 0.8 else B[0])))
			var dm := absf(fmod(u + 2.0, 7.0) - 3.5) / 3.5 + absf(v + 0.25) / 0.55
			if dm < 0.85 and v < 0.35 and u > 4.0:
				c = C[1] if dm < 0.5 else C[2]
			if v < -0.62 and hump > 4.5 and dm >= 0.85:
				c = C[6] if hump > 6.0 else C[5]
			if v > 0.45 and v < 0.8 and floori(u) % 3 == 0:
				c = B[2]
			g.setc(x, y, c)
			y += 1.0
		u -= 0.5
	# the head: a blunt wedge raised off the floor, lit on top, an eye with a slit pupil, a nostril, a mouth line
	var hx := HEAD + 2.0
	var hy := -9.5 + hb
	g.shade(hx - 5.0, hy - 4.0, hx + 6.0, hy + 4.0, func(x, y):
		var dx: float = (x - hx) / (5.6 if x > hx else 4.6)
		var dy: float = (y - hy) / (3.6 - maxf(0.0, x - hx) * 0.18)
		if dx * dx + dy * dy > 1.0:
			return 0
		if dy > 0.55:
			return B[1]
		return (C[5] if dx < 0.3 else C[4]) if dy < -0.3 else C[3])
	g.line(hx - 1.0, hy + 1.5, hx + 5.0, hy + 1.2, C[1])
	g.setc(hx + 1.0, hy - 2.0, C[0])
	g.setc(hx + 2.0, hy - 2.0, B[2])
	g.setc(hx + 1.0, hy - 1.0, B[2])
	g.setc(hx + 2.0, hy - 1.0, C[0])
	g.setc(hx + 1.0, hy - 3.0, C[6])
	g.setc(hx + 5.0, hy - 1.0, C[1])
	g.outline(C[0])


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var B := Px.fit(o.belly, 3)
	var hb := bob(t)
	# the tongue darts out, forked, and flicks back
	var e := tongue(t)
	var tx := HEAD + 7.5
	var ty := -8.2 + hb
	if e > 0.05:
		var L := 7.0 * e
		var wig := sin(t * 60.0) * 0.6 * e
		p.line(tx, ty, tx + L, ty + wig, TONGUE)
		if L > 3.0:
			p.px(tx + L + 1.0, ty + wig - 1.0, TONGUE)
			p.px(tx + L + 1.0, ty + wig + 1.0, TONGUE)
	var g := GRID
	snake(g, C, B, t)
	g.draw(p)
	# dust scuffed along the floor where each hump presses back down, drifting off low and thin
	var sw: Lib.Swarm = SWARM.begin(t)
	Px.cycle(t, D, 26, o.seed * 7 + 1, func(r): return r.range(0.6, 1.1), func(age, L, r):
		var born := Px.wrap(t - age, D)
		var m: int = r.int_(0, 2)
		var u := (PI + W * born + m * TAU) / K
		if u < 18.0 or u > LEN - 10.0:
			return
		var x: float = HEAD - u + r.range(-2.0, 2.0) - r.range(6.0, 16.0) * age
		sw.add(P.SMOKE, x, -0.5 - age * r.range(3.0, 8.0), 0.0, 0.0, age, L, DUST, r.range(1.8, 3.4)))
	sw.draw(p)
	# a glint in its eye
	p.glow(HEAD + 3.5, -11.0 + hb, 4.0, B[2], 0.35)


static func drawBack(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)

	# a shadow along its length, softer under the humps
	var u := 2.0
	while u <= LEN:
		var h := lift(u, t)
		var r := radius(u)
		Lib.shadow(p, HEAD - u, -0.2, 2.2 + r * 0.4, 1.2, C[0], 0.5 * (1.0 - Px.clamp(h / 10.0)) + 0.1)
		u += 2.0
	Lib.shadow(p, HEAD + 2.0, -0.2, 5.0, 1.2, C[0], 0.35)
