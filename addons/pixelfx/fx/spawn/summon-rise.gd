# The rubble, dust, grit, embers and smoke recipe is adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/spawn/summon-rise.js@aede4ab2dcbf7898e206280174ccb192f4228e9d
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Summon rise",
	"desc": "A rune circle burns into the floor, the ground bursts, and a horned brute heaves up out of it through dust and rubble, lit from below, until its eyes flare.",
	"tags": ["spawn", "summon", "demon", "rise", "runes", "dust", "rubble", "ground", "one-shot"],
	"size": [176, 116],
	"origin": [88, 94],
	"duration": 4.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#1a0608", "#3d0c0c", "#7a1a10", "#c0381a", "#f06a1e", "#ffae3a", "#ffe08a", "#ffffff"],
		"body": ["#060409", "#0e0913", "#170f1e", "#211628", "#2d2036"],
		"horn": ["#0c080c", "#201820", "#352a32", "#4e3f48", "#6e5c64"],
		"stone": ["#1a1424", "#2b2639", "#4a4263", "#6c6488", "#9a91b4"],
		"seed": 9,
	},
}

static var SOOT := Px.hex("#2a1e2a")
const IGN := 0.5
const RUNES := 0.78
const BREAK := 1.05
const EYES := 2.3
const FADE := 3.4
const SY := 0.3
const R0 := 36.0
const R1 := 27.0

# the brute, built part by part so overlapping forms keep their own edges. Parts front to back: 1 head,
# 2 horns, 3 arms, 4 shoulders, 5 chest, 6 waist, 7 legs, 8 tail. Each pixel keeps the frontmost part over it, that
# part's surface direction (from its own blurred shape), and whether it sits on a crease over a part behind.
const PARTS := ["head", "horns", "arms", "shoulders", "chest", "waist", "legs", "tail"]
const BW := 46
const BH := 46
const BC := 22.5

# the closures of beast() over its `cur` part, as functions taking it
static func _put(cur: Array, x: float, y: float) -> void:
	var xi := Px.roundi(x)
	var yi := Px.roundi(y)
	if xi >= 0 and yi >= 0 and xi < BW and yi < BH:
		cur[yi * BW + xi] = 1

static func _ell(cur: Array, cx: float, cy: float, rx: float, ry: float) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_put(cur, x, y)

static func _stroke(cur: Array, pts: Array, r0: float, r1: float) -> void:
	var L := []
	var total := 0.0
	for i in range(1, pts.size()):
		L.append(Px.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]))
		total += L[i - 1]
	var acc := 0.0
	for i in range(1, pts.size()):
		var n := ceilf(L[i - 1] * 3.0) + 1.0
		var j := 0
		while j <= n:
			var u := j / n
			var r: float = r0 + (r1 - r0) * ((acc + L[i - 1] * u) / total)
			_ell(cur, pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * u, pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * u, r, r)
			j += 1
		acc += L[i - 1]

# surface direction per part: the gradient of the part blurred on its own
static func _blur(src: Array) -> PackedFloat32Array:
	var W := BW
	var H := BH
	var N := W * H
	var a := PackedFloat32Array(src)
	var b := PackedFloat32Array()
	b.resize(N)
	for pass_ in 2:
		for y in H:
			for x in W:
				var s := 0.0
				for d in range(-2, 3):
					s += a[y * W + x + d] if (x + d >= 0 and x + d < W) else 0.0
				b[y * W + x] = s / 5.0
		for y in H:
			for x in W:
				var s := 0.0
				for d in range(-2, 3):
					s += b[(y + d) * W + x] if (y + d >= 0 and y + d < H) else 0.0
				a[y * W + x] = s / 5.0
	return a

static func beast() -> Dictionary:
	var W := BW
	var H := BH
	var N := W * H
	var C := BC
	var parts := []
	for k in PARTS.size():
		var m := []
		m.resize(N)
		m.fill(0)
		parts.append(m)
	var HEAD: Array = parts[0]
	var HORNS: Array = parts[1]
	var ARMS: Array = parts[2]
	var SHOULDERS: Array = parts[3]
	var CHEST: Array = parts[4]
	var WAIST: Array = parts[5]
	var LEGS: Array = parts[6]
	var TAIL: Array = parts[7]
	for s in [-1.0, 1.0]:
		var X := func(d: float) -> float: return C + s * d
		var cur := HORNS
		_stroke(cur, [[X.call(4.0), 11.0], [X.call(8.0), 8.0], [X.call(12.0), 6.5], [X.call(15.0), 4.0], [X.call(16.0), 1.5], [X.call(15.2), 0.0]], 2.3, 0.45)
		cur = SHOULDERS
		_ell(cur, X.call(10.0), 16.0, 7.0, 5.0)
		_ell(cur, X.call(8.5), 19.5, 5.5, 4.2)
		cur = ARMS
		_stroke(cur, [[X.call(14.5), 16.5], [X.call(17.5), 22.0], [X.call(18.5), 28.0]], 4.0, 3.2)
		_stroke(cur, [[X.call(18.5), 28.0], [X.call(19.0), 33.0], [X.call(19.2), 36.5]], 3.4, 2.8)
		_ell(cur, X.call(19.2), 37.8, 3.0, 2.3)
		_stroke(cur, [[X.call(17.2), 39.0], [X.call(16.6), 41.8]], 0.9, 0.4)
		_stroke(cur, [[X.call(19.2), 39.5], [X.call(19.3), 42.6]], 0.9, 0.4)
		_stroke(cur, [[X.call(21.2), 38.8], [X.call(22.0), 41.4]], 0.9, 0.4)
		cur = LEGS
		_stroke(cur, [[X.call(5.5), 31.0], [X.call(8.0), 37.0], [X.call(7.5), 42.0]], 4.0, 3.0)
		_ell(cur, X.call(8.5), 44.3, 4.2, 1.7)
	_stroke(TAIL, [[C, 30.0], [C + 0.5, 36.0], [C + 2.5, 41.5], [C + 7.0, 44.6], [C + 12.5, 44.2], [C + 14.5, 42.5]], 2.3, 0.6)
	_ell(CHEST, C, 22.5, 8.2, 7.5)
	_ell(WAIST, C, 29.5, 6.2, 4.5)
	_ell(HEAD, C, 12.5, 5.2, 4.6)
	_ell(HEAD, C, 16.0, 4.2, 2.8)
	var part := PackedByteArray()
	part.resize(N)
	for i in N:
		for k in parts.size():
			if parts[k][i]:
				part[i] = k + 1
				break
	var on := func(x: int, y: int) -> bool: return x >= 0 and y >= 0 and x < W and y < H and part[y * W + x] > 0
	var amb := PackedFloat32Array()
	amb.resize(N)
	var down := PackedFloat32Array()
	down.resize(N)
	var rim := PackedFloat32Array()
	rim.resize(N)
	var crease := PackedByteArray()
	crease.resize(N)
	for k in parts.size():
		var Bl := _blur(parts[k])
		var at := func(x: int, y: int) -> float: return Bl[y * W + x] if (x >= 0 and y >= 0 and x < W and y < H) else 0.0
		for y in H:
			for x in W:
				var i := y * W + x
				if part[i] != k + 1:
					continue
				var gx: float = at.call(x + 1, y) - at.call(x - 1, y)
				var gy: float = at.call(x, y + 1) - at.call(x, y - 1)
				var g := Px.hypot(gx, gy)
				if not g:
					g = 1e-6
				var ox := -gx / g
				var oy := -gy / g
				var e := Px.clamp(g / 0.28)
				# a dim cool light from above and the left rounds each form; undersides fall into shadow
				amb[i] = 0.42 + e * (0.4 * maxf(0.0, -oy) + 0.14 * maxf(0.0, -ox) - 0.3 * maxf(0.0, oy) - 0.08 * maxf(0.0, ox))
				# less light reaches up into the gap between the legs, so it doesn't read as a lit doorway
				down[i] = e * maxf(0.0, oy) * (0.3 if (absf(x + 0.5 - C) < 7.0 and y > 27) else 1.0)
				# a crease where this part's edge lies over a part behind it
				for dd in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					var dx: int = dd[0]
					var dy: int = dd[1]
					var j := (y + dy) * W + x + dx
					if on.call(x + dx, y + dy) and part[j] > k + 1:
						crease[i] = 1
	# the underlight's rim: the bottom of the whole silhouette, two pixels deep; less in the gap between the legs
	for y in H:
		for x in W:
			if not on.call(x, y):
				continue
			var k := 1.0 if not on.call(x, y + 1) else (0.5 if not on.call(x, y + 2) else 0.0)
			rim[y * W + x] = k * 0.3 if (absf(x + 0.5 - C) < 7.0 and y > 27) else k
	var outline := []
	for y in range(-1, H + 1):
		for x in range(-1, W + 1):
			if not on.call(x, y) and (on.call(x - 1, y) or on.call(x + 1, y) or on.call(x, y - 1) or on.call(x, y + 1)):
				outline.append([x, y])
	var eyes := []
	var tusks := []
	for s in [-1.0, 1.0]:
		eyes.append([Px.round(C + s * 2.2 - 0.5), 12.0])
		eyes.append([Px.round(C + s * 3.2 - 0.5), 12.0])
		tusks.append([Px.round(C + s * 3.4 - 0.5), 16.0])
		tusks.append([Px.round(C + s * 3.6 - 0.5), 15.0])
	return {"w": W, "h": H, "part": part, "amb": amb, "down": down, "rim": rim, "crease": crease, "outline": outline, "eyes": eyes, "tusks": tusks, "glints": [[Px.round(C - 2.7 - 0.5) - W / 2.0, 12.0 - H], [Px.round(C + 2.7 - 0.5) - W / 2.0, 12.0 - H]]}
static var BEAST := beast()

# rune glyphs: little strokes in (along, across) units, set round the circle between its two rings
const GLYPHS := [
	[[[0, -2], [0, 2]], [[-1.5, -1], [1.5, 1]]],
	[[[-1.5, 2], [0, -2], [1.5, 2]], [[-0.8, 0.4], [0.8, 0.4]]],
	[[[-1.5, -2], [-1.5, 2], [1.5, 2]], [[0, -2], [1.5, -0.5]]],
	[[[0, -2], [0, 2]], [[0, -2], [1.6, -0.6], [0, 0.6]]],
	[[[-1.5, -2], [1.5, 2]], [[1.5, -2], [-1.5, 2]], [[-1.5, 0], [1.5, 0]]],
	[[[-1.4, -2], [1.4, -2], [-1.4, 2], [1.4, 2]]],
]


var C: Array
var SH: Array
var HR: Array
var ST: Array
var DUST: int
var R: Px.Rng
var ps: Px.Particles
var RUB: Array
var rocks: Px.Bits
var lights: Px.Lights
var runes: Array
var cracks: Array = []
var t := 0.0
var done := {}


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	SH = Px.fit(o.body, 5)
	HR = Px.fit(o.horn, 5)
	ST = Px.fit(o.stone, 5)
	DUST = Px.mix(ST[2], Px.hex("#7a6c78"), 0.45)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[6], C[5], C[4], C[3]]})
	# rubble: the floor's own stone, its faces lit warm by the fire underneath
	RUB = [ST[0], ST[1], Px.mix(ST[2], C[2], 0.3), Px.mix(ST[3], C[4], 0.3), Px.mix(ST[4], C[5], 0.35)]
	rocks = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	runes = Px.arr(12, func(i): return {"a": (i / 12.0) * TAU + 0.13, "g": GLYPHS[(i * 5 + 2) % GLYPHS.size()]})
	# cracks radiating from the middle of the circle, on the floor plane
	for i in 7:
		var a := (i / 7.0) * TAU + R.range(-0.25, 0.25)
		var r := 3.0
		var pts := [[0.0, 0.0]]
		var len := R.range(R1 * 0.6, R1 * 1.05)
		while r < len:
			r += R.range(2.0, 4.0)
			a += R.range(-0.3, 0.3)
			pts.append([cos(a) * r, sin(a) * r * SY])
		cracks.append(pts)


# the rise: two heaves with a sag between, a little overshoot at the top
func rise(tt: float) -> float:
	if tt < BREAK:
		return 0.0
	var a := Px.Ease.outCubic(Px.clamp((tt - BREAK) / 0.4)) * 0.56
	var sag := 0.04 * sin(PI * Px.clamp((tt - BREAK - 0.42) / 0.3))
	var b := Px.Ease.outBack(Px.clamp((tt - BREAK - 0.62) / 0.45), 1.4) * 0.44
	return a - sag + b


# the circle's fire: lights up, flares at the break and when the eyes open, dies in the fade
func heat(tt: float) -> float:
	var e1 := tt - BREAK
	var e2 := tt - EYES
	return Px.smooth(0.0, IGN, tt) * (1.0 - Px.smooth(FADE, FADE + 0.8, tt)) * (1.0 - 0.25 * Px.smooth(EYES + 0.2, EYES + 0.9, tt)) * (0.85 + 0.15 * Px.noise(tt * 9.0, 3) + 0.5 * Px.exp(-(e1 * e1) / 0.02) + 0.3 * Px.exp(-(e2 * e2) / 0.01))


# a life that ends before the effect does
func left(a: float, b: float) -> float:
	return maxf(0.05, minf(R.range(a, b), meta.duration - 0.1 - t))


func once(k: String, at: float) -> bool:
	if not done.get(k, false) and t >= at:
		done[k] = true
		return true
	return false


func topEdge() -> Array:
	var off: float = BEAST.h * (1.0 - rise(t))
	var pts := []
	var part: PackedByteArray = BEAST.part
	for x in BEAST.w:
		for y in BEAST.h:
			if part[y * BEAST.w + x]:
				var ly: float = y - BEAST.h + off
				if ly < 0.0:
					pts.append([x - BEAST.w / 2.0, ly])
				break
	return pts


func update(dt: float) -> void:
	t += dt
	var h := heat(t)
	# the rings smoulder: embers and thin smoke off the lines, sparks at the burning front
	if t < IGN:
		var ph := (t / IGN) * PI
		for s in [-1.0, 1.0]:
			var a: float = PI / 2.0 + s * ph
			var y := sin(a) * R0 * SY
			if R.chance(0.5):
				if y < -0.5:
					ps.spawn(P.SPARK, cos(a) * R0, y, R.range(-40.0, 40.0), -R.range(40.0, 130.0), R.range(0.2, 0.45))
				else:
					ps.spawn(P.EMBER, cos(a) * R0, y, R.range(-20.0, 20.0), -R.range(30.0, 70.0), R.range(0.3, 0.6), C[6], 1.4)
	if t > 0.2 and t < FADE + 0.6 and R.chance(0.2 * h):
		var a := R.range(0.0, TAU)
		var r: float = R.pick([R0, R1, R0])
		ps.spawn(P.EMBER, cos(a) * r, sin(a) * r * SY, R.range(-10.0, 10.0), -R.range(20.0, 50.0), left(0.8, 1.6), C[5], R.range(1.0, 1.8))
	if t > 0.15 and R.chance(0.4 * minf(1.0, h)):
		var a := R.range(0.0, TAU)
		var r := R0 if R.chance(0.7) else R1
		if (absf(fmod(a - PI / 2.0 + PI * 3.0, TAU) - PI) < (t / IGN) * PI) if t < IGN else true:
			ps.spawn(P.FIRE, cos(a) * r, sin(a) * r * SY - 0.5, R.range(-4.0, 4.0), -R.range(6.0, 16.0), R.range(0.18, 0.4), 0, R.range(0.8, 1.6) * minf(1.0, h), 0.0, PF.SMOKES if R.chance(0.25) else 0)
	if t > 0.3 and t < FADE + 0.4 and R.chance(0.05 * h):
		var a := R.range(0.0, TAU)
		ps.spawn(P.SMOKE, cos(a) * R0 * 0.9, sin(a) * R0 * SY - 1.0, R.range(-4.0, 4.0), -R.range(12.0, 24.0), left(1.4, 2.2), 0, R.range(2.2, 3.4))
	if once("ign", IGN):
		lights.add(0.0, -4.0, 60.0, C[4], 0.55, 0.5)
	if once("runes", RUNES):
		lights.add(0.0, -4.0, 50.0, C[5], 0.5, 0.35)
	# the rumble: grit jumps on the floor, dust stirs
	if t > RUNES and t < BREAK and R.chance(0.35):
		ps.spawn(P.GRIT, R.range(-R1, R1), -0.5, R.range(-20.0, 20.0), -R.range(40.0, 120.0), R.range(0.5, 0.9), R.pick([ST[2], ST[3], ST[4]]), 1.0)
	if t > RUNES and t < BREAK and R.chance(0.1):
		ps.spawn(P.DUST, R.range(-R1, R1), -1.0, R.range(-12.0, 12.0), -R.range(4.0, 12.0), R.range(0.4, 0.7), DUST, R.range(1.5, 2.5))
	# the break: the floor bursts open
	if once("break", BREAK):
		lights.add(0.0, -18.0, 64.0, C[4], 0.9, 0.6)
		lights.add(0.0, -8.0, 26.0, C[6], 0.8, 0.14)
		for i in 18:
			rocks.add({"kind": B.CHUNK, "x": R.range(-14.0, 14.0), "y": -2.0, "vx": R.range(-75.0, 75.0), "vy": -R.range(170.0, 320.0), "g": 1.0, "drag": 0.7, "bounce": 0.32, "life": R.range(1.6, 2.4), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": R.range(1.3, 3.0), "ramp": RUB})
		for i in 60:
			var u := R.range(-1.0, 1.0)
			var a := -PI / 2.0 + u * 0.7
			var sp := R.range(80.0, 230.0) * (1.0 - 0.4 * absf(u))
			ps.spawn(P.GRIT, u * 10.0, -1.0, cos(a) * sp, sin(a) * sp, R.range(1.0, 1.8), R.pick([ST[2], ST[3], ST[3], ST[4]]), 2.0 if R.chance(0.4) else 1.0)
		for i in 12:
			var s := R.sign()
			ps.spawn(P.SMOKE, s * R.range(2.0, 14.0), -R.range(1.0, 5.0), s * R.range(35.0, 100.0), -R.range(4.0, 24.0), R.range(1.2, 2.0), DUST, R.range(3.5, 6.0), R.range(0.0, 0.1), PF.BIG)
		for i in 4:
			var s := R.sign()
			ps.spawn(P.SMOKE, s * R.range(10.0, 18.0), -R.range(2.0, 8.0), s * R.range(10.0, 30.0), -R.range(40.0, 90.0), R.range(1.4, 2.2), DUST, R.range(4.0, 6.5), R.range(0.0, 0.12), PF.BIG)
		for i in 24:
			var a := -PI / 2.0 + R.range(-1.1, 1.1)
			var sp := R.range(150.0, 360.0)
			ps.spawn(P.SPARK, R.range(-6.0, 6.0), -2.0, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.65))
	# the heave: earth slides off its shoulders, dust rolls out round its feet
	var rv := rise(t) - rise(t - dt)
	if t > BREAK and t < BREAK + 1.2 and rv > 0.0:
		if R.chance(minf(0.9, rv * 140.0)):
			var e := topEdge()
			if e.size():
				var xy: Array = R.pick(e)
				ps.spawn(P.GRIT, xy[0], xy[1], R.range(-25.0, 25.0), -R.range(10.0, 60.0), R.range(0.8, 1.4), R.pick([ST[2], ST[3], ST[4]]), 2.0 if R.chance(0.3) else 1.0)
		if R.chance(minf(0.8, rv * 70.0)):
			var s := R.sign()
			ps.spawn(P.SMOKE, s * R.range(10.0, 22.0), -R.range(1.0, 4.0), s * R.range(30.0, 80.0), -R.range(2.0, 12.0), R.range(1.0, 1.8), DUST, R.range(3.0, 5.5), 0.0, PF.BIG)
	if once("heave2", BREAK + 0.64):
		lights.add(0.0, -10.0, 56.0, C[4], 0.6, 0.4)
		for i in 8:
			rocks.add({"kind": B.CHUNK, "x": R.sign() * R.range(10.0, 22.0), "y": -2.0, "vx": R.sign() * R.range(25.0, 70.0), "vy": -R.range(90.0, 180.0), "g": 1.0, "drag": 0.7, "bounce": 0.3, "life": R.range(1.2, 1.8), "a": R.range(0.0, TAU), "va": R.range(-12.0, 12.0), "s": R.range(1.2, 2.4), "ramp": RUB})
	# the eyes flare
	if once("eyes", EYES):
		for gl in BEAST.glints:
			var ex: float = gl[0]
			var ey: float = gl[1]
			lights.add(ex, ey, 14.0, C[6], 0.7, 0.3)
			for i in 5:
				ps.spawn(P.SPARK, ex, ey, R.range(-90.0, 90.0), R.range(-90.0, 20.0), R.range(0.15, 0.35))
		for i in 10:
			var s := R.sign()
			ps.spawn(P.DUST, s * R.range(8.0, 20.0), -1.0, s * R.range(30.0, 80.0), -R.range(3.0, 10.0), R.range(0.4, 0.8), DUST, R.range(1.5, 3.0))
	if t > FADE + 0.05 and t < FADE + 0.75 and R.chance(0.45):
		var x := R.int_(4, BEAST.w - 5)
		var y := R.int_(2, BEAST.h - 4)
		if BEAST.part[y * BEAST.w + x]:
			var lx: float = x - BEAST.w / 2.0
			var ly: float = y - BEAST.h
			ps.spawn(P.SMOKE, lx, ly, R.range(-6.0, 6.0), -R.range(10.0, 26.0), left(0.9, 1.5), SOOT, R.range(2.0, 3.4))
			if R.chance(0.3):
				ps.spawn(P.EMBER, lx, ly, R.range(-10.0, 10.0), -R.range(15.0, 40.0), left(0.6, 1.2), C[4], 1.0)
	rocks.update(dt)
	for b in rocks.list:
		if b.rest and not b.get("dusted", false):
			b.dusted = true
			for i in 2:
				ps.spawn(P.DUST, b.x + R.range(-1.5, 1.5), -0.5, R.sign() * R.range(6.0, 30.0), -R.range(2.0, 12.0), R.range(0.3, 0.6), DUST, R.range(1.2, 2.4))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var h := heat(t)
	if h <= 0.01:
		return
	# the warm pool on the floor
	p.glow(0.0, -2.0, 52.0, C[4], 0.28 * h)
	p.glow(0.0, -22.0, 72.0, C[4], 0.1 * h)
	p.glow(0.0, -1.0, 22.0, C[5], 0.2 * h)
	# the cracks open under it and glow
	var ck := Px.smooth(RUNES, BREAK, t) * (1.0 - Px.smooth(FADE, FADE + 0.7, t))
	if ck > 0.0:
		for pts in cracks:
			for i in range(1, pts.size()):
				var u := i / float(pts.size())
				if u > ck * 1.1:
					break
				var cool := Px.smooth(BREAK + 0.1, BREAK + 1.1, t)
				var ci := Px.round(6.0 - u * 2.0 - cool * 2.6)
				p.line(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], C[int(Px.clamp(ci, 2.0, 6.0))], 1.0)
	# the rings: burnt in from the front round to the back, flickering
	var n := 220
	var prog := Px.clamp(t / IGN) * PI
	for j in n:
		var a := (j / float(n)) * TAU
		var d := absf(fmod(a - PI / 2.0 + PI * 3.0, TAU) - PI)
		if d > prog:
			continue
		var fresh := prog - d < 0.25 and t < IGN + 0.1
		var f := Px.noise(a * 6.0 + t * 5.0, 4) * 0.5 + 0.5
		var k := h * (0.7 + 0.5 * f)
		var ca := cos(a)
		var sa := sin(a)
		p.dot(ca * R0, sa * R0 * SY, WHITE if fresh else (C[6] if k > 0.95 else (C[5] if k > 0.6 else (C[4] if k > 0.35 else C[3]))))
		p.dot(ca * (R0 + 2.2), sa * (R0 + 2.2) * SY, C[4] if k > 0.8 else C[3], 0.9)
		if t > RUNES - 0.15:
			p.dot(ca * R1, sa * R1 * SY, C[5] if k > 0.9 else (C[4] if k > 0.5 else C[3]), Px.smooth(RUNES - 0.15, RUNES + 0.05, t))
		if j % 11 == 0:
			p.glow(ca * R0, sa * R0 * SY, 9.0, C[4], 0.22 * k)
	# the runes between the rings
	var rk := Px.smooth(RUNES - 0.1, RUNES + 0.15, t)
	if rk > 0.0:
		for r in runes:
			var k: float = h * rk * (0.75 + 0.35 * Px.noise(t * 4.0 + r.a * 5.0, 8))
			var mid := (R0 + R1) / 2.0 + 0.5
			var ta := [-sin(r.a), cos(r.a)]
			var na := [cos(r.a), sin(r.a)]
			var proj := func(uv: Array) -> Array:
				var u: float = uv[0]
				var v: float = uv[1]
				return [(na[0] * mid + ta[0] * u * 1.1 + na[0] * v), (na[1] * mid + ta[1] * u * 1.1 + na[1] * v) * SY]
			for stroke in r.g:
				for i in range(1, stroke.size()):
					var p0: Array = proj.call(stroke[i - 1])
					var p1: Array = proj.call(stroke[i])
					p.line(p0[0], p0[1], p1[0], p1[1], C[6] if k > 0.9 else (C[5] if k > 0.55 else C[4]), minf(1.0, k * 1.5))
	# the hole the brute climbs out of: a glowing gash
	var hole := Px.smooth(BREAK - 0.05, BREAK + 0.15, t) * (1.0 - Px.smooth(BREAK + 0.95, BREAK + 1.5, t))
	if hole > 0.0:
		var hw := 15.0 * hole
		p.shade(-hw - 1.0, -1.0, hw + 1.0, 4.0, func(x, y, out):
			var d := Px.hypot(x / hw, (y - 0.5) / 3.2)
			if d > 1.0:
				return
			out.c = C[4] if d > 0.86 else (C[1] if d > 0.62 else C[0]))
		p.glow(0.0, 0.0, 24.0, C[5], 0.3 * hole * h)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var r := rise(t)
	var off: float = BEAST.h * (1.0 - r)
	var h := heat(t)
	var fade := Px.smooth(FADE + 0.1, FADE + 0.8, t)
	if r > 0.0:
		var W: int = BEAST.w
		var H: int = BEAST.h
		var x0 := -W / 2.0
		var oy := off - H
		var k := minf(1.0, h)
		var gone := func(x: float, y: float) -> bool: return fade > 0.0 and fade > 0.06 + 0.86 * (0.55 * (1.0 - y / H) + 0.45 * Px.rand(x, y, 3))
		# a dark edge all round, so the bulk reads against the night
		for xy in BEAST.outline:
			var x: int = xy[0]
			var y: int = xy[1]
			if y + oy < 0.0 and not gone.call(x, mini(H - 1, maxi(0, y))):
				p.px(x0 + x, y + oy, SH[0])
		var part: PackedByteArray = BEAST.part
		var amb: PackedFloat32Array = BEAST.amb
		var crease: PackedByteArray = BEAST.crease
		var rim: PackedFloat32Array = BEAST.rim
		var down: PackedFloat32Array = BEAST.down
		for y in H:
			var ly := y + oy
			if ly >= 0.0:
				break
			# the fire below lights the undersides: rims strongest by the floor, broad planes higher up
			var upRim := Px.exp(ly / 17.0) * k
			var upPlane := Px.exp(ly / 19.0) * k
			for x in W:
				var i := y * W + x
				var pt := part[i]
				if not pt or gone.call(x, y):
					continue
				var ramp: Array = HR if pt == 2 else SH
				var a := amb[i]
				var si := 0 if crease[i] else (4 if a > 0.74 else (3 if a > 0.56 else (2 if a > 0.36 else 1)))
				if pt == 2 and si > 0:
					si = mini(4, si + (2 if y < 3 else 1))  # horns are paler, tips palest
				# rims can run hot; the broad planes only ever warm up to deep red
				var Lr := rim[i] * upRim
				var Lp := down[i] * upPlane * 0.6
				var c: int = ramp[si]
				if Lr > 0.7:
					c = C[5]
				elif Lr > 0.48:
					c = C[4]
				elif Lr > 0.3 or Lp > 0.42:
					c = C[3]
				elif Lr > 0.17 or Lp > 0.26:
					c = Px.mix(C[2], ramp[si], 0.3)
				elif Lr > 0.08 or Lp > 0.12:
					c = Px.mix(ramp[si], C[1], 0.6)
				p.px(x0 + x, ly, c)
		# tusks catch the light; the eye sockets smoulder until the eyes open
		for xy in BEAST.tusks:
			var x: float = xy[0]
			var y: float = xy[1]
			if y + oy < 0.0 and not gone.call(x, y):
				p.px(x0 + x, y + oy, Px.mix(HR[4], C[4], 0.35 * k))
		for xy in BEAST.eyes:
			var x: float = xy[0]
			var y: float = xy[1]
			if y + oy < 0.0 and not gone.call(x, y):
				p.px(x0 + x, y + oy, (WHITE if t < EYES + 0.1 else C[6]) if t > EYES - 0.05 else (C[2] if t > BREAK + 0.5 else SH[0]))
		# the eyes: a flare as they open, then a steady burn that outlasts the body
		if t > EYES - 0.05:
			var ke := (1.0 - Px.smooth(FADE + 0.6, FADE + 1.0, t)) * (0.85 + 0.15 * sin(t * 13.0))
			for gl in BEAST.glints:
				var ex: float = gl[0]
				var ey0: float = gl[1]
				var ey := ey0 + off
				if ey >= 0.0:
					continue
				p.glow(ex + 0.5, ey, 6.0, C[5], 0.5 * ke)
				var g := (t - EYES) / 0.3
				if g > 0.0 and g < 1.0:
					var L := 9.0 * pow(1.0 - g, 1.5)
					p.line(ex - L, ey, ex + L, ey, func(u): return WHITE if absf(u - 0.5) < 0.18 else (C[6] if absf(u - 0.5) < 0.35 else C[5]))
					if g < 0.4:
						p.line(ex, ey - 2.0 * (1.0 - g), ex, ey + 2.0 * (1.0 - g), C[6])
				elif fade > 0.6 and ke > 0.05:
					p.px(ex, ey, C[6])
		# the light that rakes up its front
		p.glow(0.0, -6.0, 30.0, C[4], 0.25 * h * r)
	rocks.draw(p)
	ps.draw(p, "front")
	lights.draw(p)
