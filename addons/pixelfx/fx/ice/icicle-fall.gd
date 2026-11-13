# The break recipe (a white frame, the ice flung apart as shards with ice dust and glints) is adapted from
# Sprite Fusion's open-source ice (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ice/icicle-fall.js@108d204e2082c457a439f08e00fc53cf01e7b5df
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE
const GRAVITY := Px.GRAVITY

static var meta := {
	"name": "Icicle fall",
	"desc": "An icicle drips and trembles, snaps off its frosted root, drops, stabs the floor and bursts into skidding shards, splinters and rolling frost.",
	"tags": ["ice", "icicle", "fall", "trap", "shatter", "one-shot"],
	"size": [152, 120],
	"origin": [76, 100],
	"duration": 2.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "seed": 4},
}

const ROOT := -80.0  # where it hangs, how long, how wide at the root
const LEN := 36.0
const W := 12.0
const DRIP := 0.16
const TREMBLE := 0.3
const SNAP := 0.6
const FREE := SNAP + 0.04
static var FALL_T := sqrt((2.0 * (-ROOT - LEN)) / GRAVITY)
static var IMPACT := FREE + FALL_T


# the icicle: a rippled taper hanging from (x, top), lit down its left side with a bright core streak, rings of
# light at the ripples, deep on the right, a dark rim. white flashes it; cut hides the top rows (snapped root).
static func icicle(p: Px.Painter, C: Array, x: float, top: float, len: float, w: float, opts: Dictionary = {}) -> void:
	var hw := func(u: float) -> float: return (w / 2.0) * pow(1.0 - u, 0.75) * (1.0 + 0.14 * sin(u * 13.0 + 0.5)) * (1.15 if u < 0.08 else 1.0) + 0.3
	var tilt: float = opts.tilt if opts.get("tilt") != null else 0.0
	var cut: float = opts.cut if opts.get("cut") != null else 0.0
	var white: bool = true if opts.get("white") else false
	var glint: float = opts.glint if opts.get("glint") != null else -1.0
	p.shade(x - w / 2.0 - 4.0, top - 1.0, x + w / 2.0 + 4.0 + absf(tilt) * len, top + len + 1.0, func(px: float, py: float, o) -> void:
		var u := (py - top) / len
		var cx := x + tilt * len * u + 0.7 * sin(u * 6.0 + 1.0)
		var s := px - cx
		if u < cut or u > 1.0:
			return
		var h: float = hw.call(u)
		if absf(s) > h + 1.0:
			return
		if absf(s) > h:
			o.c = C[1]
			return
		if white:
			o.c = WHITE
			return
		var q := s / h
		var ring := sin(u * 13.0 + 0.5) > 0.7
		var c: int = WHITE if u > 0.88 else (C[6] if q < -0.72 else ((C[7] if ring else C[5]) if q < -0.2 else ((C[7] if u < 0.72 else C[6]) if q < 0.18 else (C[2] if q > 0.8 else (C[5] if (absf(q - 0.45) < 0.1 and u > 0.15 and u < 0.6) else (C[4] if q < 0.6 else C[3]))))))
		if glint >= 0.0 and q < 0.25 and absf(u - glint) < 0.06:
			c = WHITE
		o.c = c)


var C: Array
var R: Px.Rng
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var panes: Lib.Panes
# the rime it hangs from: a frosted crust with stubs of older icicles
var rime: Array = []
var t := 0.0
var snapped := false
var landed := false
var dripped := false
var y := 0.0


func splinter(x: float, y_: float, vx: float, n: int) -> void:
	for i in n:
		bits.add({"kind": B.SHARD, "x": x + R.range(-2.0, 2.0), "y": y_ - 1.0, "vx": vx * 0.5 + R.range(-45.0, 45.0), "vy": -R.range(30.0, 100.0), "g": 0.8, "drag": 0.6, "bounce": 0.35, "life": R.range(0.4, 0.75), "a": R.range(0.0, TAU), "va": R.range(-18.0, 18.0), "s": R.range(1.2, 2.4), "c": C[R.int_(4, 7)]})


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]], "haze": C[5]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	panes = Lib.Panes.new({
		"ground": floor_,
		"onLand": func(q: Dictionary, x: float, y_: float, v: float) -> void:
			if v < 100.0:
				return
			ps.spawn(P.VAPOUR, x, y_ - 1.0, R.range(-15.0, 15.0), -R.range(2.0, 8.0), R.range(0.4, 0.6), C[6], R.range(1.4, 2.2))
			splinter(x, y_, q.vx, 2),
		"onCrumble": func(q: Dictionary) -> void: splinter(q.x, 0.0, q.vx, 3),
	})
	rime = []
	for x in range(-18, 19):
		var h := Px.rand(x, o.seed, 2)
		var d := absf(x) / 18.0
		rime.append({"x": x, "h": 1.0 + Px.round((0.6 + h * 1.8) * (1.0 - d * 0.7)), "stub": 2.0 + Px.round(Px.rand(x, 5) * 5.0 * (1.0 - d * 0.5)) if (h < 0.3 and absi(x) > 7) else 0.0})


func top() -> float:
	return ROOT + (0.0 if t < FREE else 0.5 * GRAVITY * pow(t - FREE, 2.0))


func update(dt: float) -> void:
	t += dt
	# a drop of meltwater swells at the tip and falls
	if not dripped and t >= DRIP:
		dripped = true
		bits.add({"kind": B.DRIP, "x": 0.5, "y": ROOT + LEN + 1.0, "vy": 20.0, "g": 0.9, "life": 1.2, "c": C[6]})
	# it trembles: frost sifts down from the root
	if t > TREMBLE and t < SNAP and R.chance(0.25):
		ps.spawn(P.FLAKE, R.range(-6.0, 6.0), ROOT + R.range(0.0, 3.0), R.range(-8.0, 8.0), R.range(5.0, 20.0), R.range(0.6, 1.1), WHITE if R.chance(0.5) else C[6], R.range(0.5, 1.1))
	# it snaps: a crack flashes across the root, chips and a puff burst off
	if not snapped and t >= SNAP:
		snapped = true
		lights.add(0.0, ROOT + 4.0, 24.0, WHITE, 0.6, 0.1)
		lights.add(0.0, ROOT + 4.0, 32.0, C[5], 0.4, 0.3)
		for i in 7:
			var a := R.range(0.0, TAU)
			var sp := R.range(30.0, 110.0)
			bits.add({"kind": B.SHARD, "x": R.range(-4.0, 4.0), "y": ROOT + 2.0, "vx": cos(a) * sp, "vy": sin(a) * sp - 20.0, "g": 0.8, "drag": 0.8, "bounce": 0.3, "life": R.range(0.5, 0.9), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.0, 2.0), "c": C[R.int_(5, 7)]})
		for i in 3:
			ps.spawn(P.VAPOUR, R.range(-5.0, 5.0), ROOT + 2.0, R.range(-25.0, 25.0), R.range(-5.0, 5.0), R.range(0.4, 0.7), C[6], R.range(1.6, 2.6))
		for i in 5:
			ps.spawn(P.FLAKE, R.range(-6.0, 6.0), ROOT + 2.0, R.range(-30.0, 30.0), R.range(-20.0, 20.0), R.range(0.6, 1.2), WHITE if R.chance(0.5) else C[6], R.range(0.5, 1.3))
	# falling: it sheds frost motes that hang in the air behind it
	if t > FREE and t < IMPACT and R.chance(0.5):
		var tp := top()
		ps.spawn(P.MOTE, R.range(-3.0, 3.0), tp + R.range(0.0, LEN * 0.6), R.range(-10.0, 10.0), R.range(-40.0, -10.0), R.range(0.2, 0.35), C[6] if R.chance(0.5) else C[5], 0.6)
	# it stabs the floor and bursts
	if not landed and t >= IMPACT:
		landed = true
		var tp := -LEN
		lights.add(0.0, -16.0, 46.0, WHITE, 0.85, 0.12)
		lights.add(0.0, -16.0, 58.0, C[4], 0.5, 0.5)
		# the icicle in pieces: cut across its length, then down the middle
		var parts := [[[-W / 2.0, tp], [W / 2.0, tp], [0.5, 0.0]]]
		for v: float in [0.3, 0.58, 0.8]:
			var cut := []
			for poly: Array in parts:
				cut.append_array(Lib.splitPoly(poly, 0.0, tp + LEN * v + R.range(-2.0, 2.0), R.range(-0.4, 0.4)))
			parts = cut
		var halves := []
		for poly: Array in parts:
			halves.append_array(Lib.splitPoly(poly, Lib.centroid(poly).x, Lib.centroid(poly).y, PI / 2.0 + R.range(-0.5, 0.5)) if Lib.centroid(poly).area > 22.0 else [poly])
		parts = halves
		for part: Array in parts:
			var m := Lib.centroid(part)
			var side := -1.0 if m.x < 0.5 else 1.0
			var low := Px.clamp(-m.y / LEN)
			panes.add({
				"pts": part.map(func(pt: Array) -> Array: return [pt[0] - m.x, pt[1] - m.y]), "x": m.x, "y": m.y, "vx": side * R.range(30.0, 110.0) + R.range(-15.0, 15.0), "vy": -R.range(70.0, 200.0) * (0.4 + low), "a": 0.0, "va": R.range(-12.0, 12.0), "f": R.range(-0.7, 0.7), "vf": R.range(-8.0, 8.0),
				"lit": 0.75, "g": 0.9, "drag": 0.6, "bounce": 0.35, "solid": true, "ridge": PI / 2.0, "brittle": 2, "crumble": R.range(0.15, 0.45), "life": R.range(1.0, 1.4),
			})
		for i in 52:
			var a := -PI / 2.0 + R.range(-1.25, 1.25)
			var sp := R.range(60.0, 230.0)
			bits.add({"kind": B.CHUNK if R.chance(0.15) else B.SHARD, "x": R.range(-3.0, 3.0), "y": -R.range(1.0, 10.0), "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 0.85, "drag": 0.6, "bounce": 0.32, "life": R.range(0.6, 1.2), "a": R.range(0.0, TAU), "va": R.range(-22.0, 22.0), "s": R.range(1.2, 3.0), "c": C[R.int_(4, 7)], "ramp": [C[1], C[3], C[4], C[6], C[7]]})
		for i in 10:
			var s := R.sign()
			ps.spawn(P.VAPOUR, s * R.range(0.0, 8.0), -R.range(1.0, 6.0), s * R.range(25.0, 90.0), -R.range(2.0, 14.0), R.range(0.6, 1.1), C[6], R.range(2.2, 3.8))
		for i in 12:
			ps.spawn(P.FLAKE, R.range(-6.0, 6.0), -R.range(2.0, 16.0), R.range(-70.0, 70.0), -R.range(30.0, 110.0), R.range(1.0, 1.5), WHITE if R.chance(0.6) else C[6], R.range(0.5, 1.5))
		for i in 6:
			ps.spawn(P.STAR, R.range(-24.0, 24.0), -R.range(4.0, 34.0), R.range(-10.0, 10.0), -R.range(4.0, 14.0), R.range(0.4, 0.8), WHITE if R.chance(0.5) else C[6], R.range(1.0, 2.2))
	if landed and t < IMPACT + 0.9 and R.chance(0.08) and bits.list.size():
		var b: Dictionary = R.pick(bits.list)
		ps.spawn(P.STAR, b.x, b.y - 1.0, 0.0, -3.0, R.range(0.2, 0.4), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.4))
	ps.update(dt)
	bits.update(dt)
	panes.update(dt)
	lights.update(dt)
	Lib.endBy(t, meta.duration, ps, bits, panes)


func drawBack(p: Px.Painter) -> void:
	# its shadow gathers on the floor as it comes down
	if t > TREMBLE and t < IMPACT + 0.05:
		var k := Px.seg(t, TREMBLE, FREE) * 0.35 if t < FREE else 0.35 + 0.65 * Px.seg(t, FREE, IMPACT)
		var rx := 3.0 + 7.0 * k
		var x := floorf(-rx)
		while x <= rx:
			var f := 1.0 - pow(x / rx, 2.0)
			p.blend(x + 0.5, 0.0, C[0], 0.7 * k * f)
			if absf(x) < rx * 0.7:
				p.blend(x + 0.5, 1.0, C[0], 0.45 * k * f)
			x += 1.0
	# frost splashed across the floor where it struck, melting away
	if t >= IMPACT:
		var g := Px.Ease.outCubic(Px.seg(t, IMPACT, IMPACT + 0.25))
		var out := 1.0 - Px.smooth(IMPACT + 0.8, IMPACT + 1.5, t)
		for x in range(-26, 27):
			var d := absf(x + 0.5) / 26.0
			var h := Px.rand(x, 23)
			var a := out * Px.clamp((g * 1.15 - d) / 0.15)
			if a <= 0.0:
				continue
			p.dot(x, 0.0, WHITE if (h < 0.35 or d > g - 0.12) else C[6], a)
			if h < 0.4:
				var j := 1
				while j <= Px.round((1.0 + Px.rand(x, 3) * 2.5) * (1.0 - d)):
					p.dot(x + Px.sign(x) * (1.0 if j > 1 else 0.0), -j, WHITE if j > 1 else C[5], a)
					j += 1
			var jj := 1
			while jj <= Px.round((2.0 + Px.rand(x, 7) * 3.0) * (1.0 - d * 0.6)):
				p.dot(x, jj, C[5] if jj < 2 else C[4], a * (1.1 - jj / 6.0))
				jj += 1
		var k := Px.seg(t, IMPACT, IMPACT + 0.35)
		if k < 1.0:
			Px.band(p, 0.0, 0.5, 6.0 + 34.0 * Px.Ease.outCubic(k), 0.18, maxf(1.0, 4.0 * (1.0 - k)), 1.1 - k, [C[3], C[4], C[5], C[6]], func(a: float) -> bool: return sin(a) < 0.0)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	# the rime it hangs from, fading at the end
	var ra := 1.0 - Px.smooth(meta.duration - 0.7, meta.duration - 0.2, t)
	for r: Dictionary in rime:
		# a lumpy crust: white on top, pale below, a deep underside; little icicles hang off it
		var j := 0
		while j < r.h + 1.0:
			p.dot(r.x, ROOT - 1.0 - j, WHITE if j == r.h else (C[6] if j == r.h - 1.0 else (C[3] if j == 0 else C[5])), ra)
			j += 1
		j = 0
		while j < r.stub:
			p.dot(r.x, ROOT + j, WHITE if j == r.stub - 1.0 else (C[5] if j == 0 else C[4]), ra)
			j += 1
		if r.stub > 4.0:
			p.dot(r.x + 1, ROOT, C[3], ra)
	# the snapped root: a jagged stub left behind
	if snapped:
		var x := -W / 2.0 + 1.0
		while x <= W / 2.0 - 1.0:
			var L := 1.0 + Px.round(Px.rand(x, 77) * 2.5)
			var j := 0.0
			while j < L:
				p.dot(x, ROOT + j, (WHITE if t < SNAP + 0.15 else C[6]) if j == L - 1.0 else (C[5] if x < 0.0 else C[3]), ra)
				j += 1.0
			x += 1.0
	p.glow(0.0, ROOT, 18.0, C[4], 0.3 * ra)
	if t >= IMPACT:
		var k := Px.seg(t, IMPACT, IMPACT + 0.35)
		if k < 1.0:
			Px.band(p, 0.0, 0.5, 6.0 + 34.0 * Px.Ease.outCubic(k), 0.18, maxf(1.0, 4.0 * (1.0 - k)), 1.1 - k, [C[3], C[4], C[5], C[6]], func(a: float) -> bool: return sin(a) >= 0.0, k < 0.15)
		if t < IMPACT + 0.22:
			Px.sparkle(p, 0.5, -3.0, 10.0 * Px.Ease.outBack(minf(1.0, (t - IMPACT) / 0.05)) * (1.0 - (t - IMPACT) / 0.22), C[6], C[4], 0.7)
	if t < IMPACT:
		# the icicle: trembling before it snaps, then falling with a streak of air behind it
		var tp := top()
		var jx := ((1.0 if floori(t * 36.0) % 2 else 0.0) * Px.round(Px.seg(t, TREMBLE, SNAP) * 1.4 + 0.4)) if (t > TREMBLE and t < SNAP) else 0.0
		var falling := t >= FREE
		var sp := GRAVITY * (t - FREE) if falling else 0.0
		if falling:
			for e: Array in [[-3.0, 0.7], [0.5, 1.0], [4.0, 0.6]]:
				var dx: float = e[0]
				var k: float = e[1]
				var L := minf(30.0, sp * 0.07) * k
				if L > 2.0:
					p.line(dx, tp - L, dx, tp + 3.0, func(u: float) -> int: return C[6] if u > 0.75 else (C[4] if u > 0.4 else C[3]))
		var gl := (t - 0.04) / 0.3
		icicle(p, C, jx + 0.5, tp, LEN, W, {"white": t >= IMPACT - 0.025 or (t >= SNAP and t < SNAP + 0.03), "glint": gl if (gl >= 0.0 and gl <= 1.0) else -1.0})
		if snapped and t < SNAP + 0.12:
			p.line(-W / 2.0 - 1.0, ROOT + 1.0, W / 2.0 + 1.0, ROOT + 1.0, WHITE)
		p.glow(0.5, tp + LEN * 0.5, 20.0, C[4], 0.28)
		# the drop of meltwater swelling at the tip
		if t < DRIP:
			var s := Px.seg(t, 0.0, DRIP)
			p.dot(0.5, ROOT + LEN + 1.0, C[6], s)
			if s > 0.6:
				p.px(0.5, ROOT + LEN + 2.0, WHITE)
	panes.draw(p, C)
	bits.draw(p)
	ps.draw(p, "front")
	lights.draw(p)
