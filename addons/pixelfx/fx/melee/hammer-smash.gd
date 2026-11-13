# The rocks, grit, rolling dust and floor ring are adapted from Sprite Fusion's open-source explosion, and the
# dome from his ice nova (https://www.spritefusion.com/pixel-art-vfx), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/hammer-smash.js@3b3ecf833b6cc2bb9502b621925f24d145403d94
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Hammer smash",
	"desc": "A hammer drops in front in a wedge of motion: a white slam with rays, a dome of force, a dent with cracks, rocks thrown up that bounce and settle, and dust.",
	"tags": ["melee", "smash", "hammer", "heavy", "ground", "shockwave", "debris", "combat", "directional", "one-shot"],
	"size": [208, 112],
	"origin": [80, 92],
	"duration": 2.0,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#141834", "#242c5c", "#38479a", "#5a72d0", "#8fa8f0", "#c4d4ff", "#eef3ff", "#ffffff"],
		"stone": "#4a3f69",
		"seed": 9,
	},
}

# both hands low on the shaft, the head resting on the floor in front; it comes up, over and down
static var REST_ := Px.merge(Px.READY, {"weapon": "hammer", "two": true, "sa": 0.62, "fx": 11, "fy": -21, "crouch": 3})
static var TOP := Px.merge(REST_, {"x": -3, "crouch": 0, "lean": -3, "fx": 3, "fy": -41, "sa": -2.1, "ffx": 8, "ffy": -8, "fbx": -5, "toeB": true})
static var SLAM := Px.merge(REST_, {"x": -1, "crouch": 7, "lean": 6, "fx": 14, "fy": -19, "sa": 0.62, "ffx": 11, "fbx": -10})
static var act := {
	"target": {"x": 66},
	"poses": [
		[-0.72, Px.merge(REST_, {"x": -3})],
		[-0.44, Px.merge(REST_, {"x": -3, "crouch": 5, "lean": -1, "fx": 16, "fy": -28, "sa": -0.9})],
		[-0.2, TOP],
		[-0.03, Px.merge(TOP, {"y": -2})],
		[0.06, Px.merge(REST_, {"x": 0, "y": -3, "crouch": -1, "lean": 2, "fx": 13, "fy": -41, "sa": -1.2, "ffx": 11, "ffy": -8, "ghost": 1}), "snap"],
		[0.11, Px.merge(REST_, {"x": 0, "y": -1, "crouch": 3, "lean": 5, "fx": 19, "fy": -30, "sa": -0.15, "ffx": 13, "ghost": 1}), "snap"],
		[0.15, SLAM, "snap"],
		[0.62, Px.merge(SLAM, {"crouch": 6, "lean": 5})],
		[1.02, Px.merge(REST_, {"x": -2, "crouch": 5, "lean": 2, "fx": 14, "fy": -24, "sa": 0.3})],
		[1.4, Px.merge(REST_, {"x": -3})],
	],
	"hits": [{"t": 0.15, "stop": 0.2, "shake": 0.34, "amp": 3, "push": 3, "straw": 26, "y": -8}],
	"dust": [{"t": 0.15, "x": 10, "n": 8}, {"t": 0.15, "x": -12, "n": 5, "dir": -1}],
}

static var SOOT := Px.hex("#0d0a12")
static var HOT := Px.ramp(["#fff3a6", "#ffc23d", "#ff8a2a", "#c9281f"])
const DROP := 0.15  # the hammer comes over and down, gathering speed
static func head(t_: float) -> float:
	var x := Px.clamp((t_ + 0.03) / (DROP + 0.03))
	return 0.28 * x + 0.72 * x * x


var C: Array
var n: int
var R: Px.Rng
var st: Dictionary
var ps: Px.Particles
var bits: Px.Bits
var chips: Px.Bits
var lights: Px.Lights
var A: Dictionary
var U1 := 0.0
var HW := 13.0
var X: float
var lines: Array
var rays: Array
var t := 0.0
var hit := false
var Rm: float


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	n = C.size()
	R = Px.Rng.new(o.seed)
	st = Lib.stone(o.stone)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_})
	bits = Px.Bits.new({"ground": floor_})
	chips = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	# the hammer head's path: round the shoulders, from overhead down to the floor in front
	A = Lib.swing({"cx": 5.0, "cy": -25.0, "R": 32.0, "sy": 1.0, "rot": 0.0, "a0": -2.25, "dir": 1.0})
	U1 = 0.0
	while Lib.onSwing(A, A.R, U1)[1] < -0.5 and U1 < 4.0:
		U1 += 0.005
	X = Lib.onSwing(A, A.R - HW / 2.0, U1)[0]
	lines = Lib.cracks(R, X, 5, 24.0, 6.0, 0.0)
	rays = []
	var ds := [-0.95, -0.6, -0.3, -0.05, 0.22, 0.5, 0.85]
	for i in ds.size():
		var d: float = ds[i]
		rays.append({"a": -PI / 2.0 + d + R.range(-0.06, 0.06), "L": (34.0 if i == 3 else (26.0 if i == 2 or i == 4 else (18.0 if i == 1 or i == 5 else 12.0))) * R.range(0.9, 1.1)})
	# the smear: the hammer head's path as a comet, a hard white leading face, tapering to a hair behind it,
	# cooling along the taper (edges first), with speed lines trailing along the arc
	Rm = A.R - HW / 2.0


func wedge(p: Px.Painter) -> void:
	var h := head(t)
	var U := U1 * h
	var after := Px.smooth(DROP, DROP + 0.07, t)
	var lagU := maxf(0.0, U - (0.3 + 1.05 * h))
	var T := lagU + (U - lagU) * after * 0.8
	if U - T < 0.03 or after >= 1.0:
		return
	var len := (U - T) * Rm
	var HW_ := HW
	var Rm_ := Rm
	var C_ := C
	var n_ := n
	Lib.smear(p, A, T, U, HW + 1.0, func(u, r, out):
		var lead: float = (U - u) * Rm_
		var f := lead / len
		var w := HW_ * (1.0 if lead < 3.0 else pow(1.0 - (lead - 3.0) / maxf(1.0, len - 3.0), 0.85)) * (1.0 - after * 0.5)
		var off: float = (r - Rm_) / (w / 2.0 + 0.01)
		if w < 0.6 or absf(off) > 1.0:
			return
		var ci := 0.0 if lead < 2.0 else Px.round(1.0 + f * 3.4 + absf(off) * 1.4 - (1.0 if off > 0.55 else 0.0) + after * 3.0)
		if ci > n_ - 3:
			return
		out.c = C_[n_ - 1 - int(maxf(0.0, ci))])
	# speed lines trail the head along the arc, dotted out at their ends
	if after < 0.6:
		for dlL: Array in [[-HW / 2.0 - 2.0, 3.0, 26.0], [-HW / 2.0 - 5.0, 9.0, 16.0], [HW / 2.0 + 2.0, 2.0, 30.0], [HW / 2.0 + 5.0, 8.0, 18.0], [-1.0, len + 2.0, 14.0], [3.0, len + 4.0, 9.0]]:
			var dr: float = dlL[0]
			var l0: float = dlL[1]
			var L: float = dlL[2]
			var r := Rm + dr
			var d := l0
			while d < l0 + L * (1.0 - after):
				var u := U - d / r
				var k := (d - l0) / L
				if u < 0.0:
					break
				var xy := Lib.onSwing(A, r, u)
				p.dot(xy[0], xy[1], C[6] if k < 0.25 else (C[5] if k < 0.6 else C[4]), (1.0 - k) * (1.0 - after))
				d += 0.5
	var hxy := Lib.onSwing(A, Rm, U)
	p.glow(hxy[0], hxy[1], 34.0, C[4], 0.5 * (1.0 - Px.smooth(DROP - 0.03, DROP, t)))


func update(dt: float) -> void:
	t += dt
	if not hit and t >= DROP:
		hit = true
		lights.add(X, -5.0, 16.0, WHITE, 0.35, 0.08)
		lights.add(X, -10.0, 64.0, C[4], 0.42, 0.6)
		# rocks thrown up out of the dent: they tumble, land, bounce and settle
		for i in 15:
			var s := R.sign()
			bits.add({"kind": B.CHUNK, "x": X + s * R.range(0.0, 5.0), "y": -2.0, "vx": s * R.range(20.0, 105.0), "vy": -R.range(110.0, 300.0), "g": 1.0, "drag": 0.35, "bounce": 0.38, "life": R.range(1.25, 1.65), "a": R.range(0.0, TAU), "va": R.range(-16.0, 16.0), "s": R.pick([1.0, 1.0, 2.0, 2.0, 3.0])})
		# hot chips struck off the stone: they bounce, settle and cool through the ramp
		for i in 11:
			var a := -PI / 2.0 + R.range(-1.2, 1.2)
			var sp := R.range(90.0, 230.0)
			chips.add({"kind": B.SHARD, "x": X + R.range(-4.0, 4.0), "y": -2.0, "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 0.9, "drag": 0.5, "bounce": 0.35, "life": R.range(0.9, 1.5), "s": 1.0})
		for i in 40:
			var a := -PI / 2.0 + R.range(-1.1, 1.1)
			var sp := R.range(50.0, 210.0)
			ps.spawn(P.GRIT, X + R.range(-4.0, 4.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(0.9, 1.5), R.pick([st.light, st.body, st.body, st.shade]), 2.0 if R.chance(0.4) else 1.0)
		# force motes skid out along the floor, sparks off the stone
		for i in 14:
			var s := -1.0 if i % 2 else 1.0
			var sp := R.range(120.0, 260.0)
			ps.spawn(P.MOTE, X + s * 6.0, -R.range(1.0, 4.0), s * sp, -R.range(0.0, 30.0), R.range(0.18, 0.34), C[6] if R.chance(0.5) else C[5], 0.8, R.range(0.02, 0.05))
		for i in 24:
			var a := -PI / 2.0 + R.range(-1.4, 1.4)
			var sp := R.range(150.0, 380.0)
			ps.spawn(P.SPARK, X + cos(a) * 6.0, -2.0 + sin(a) * 4.0, cos(a) * sp, sin(a) * sp - 30.0, R.range(0.12, 0.42), 0, 1.0, R.range(0.035, 0.08))
		# dust rolls out both ways along the floor, and a puff lifts off the dent
		for i in 20:
			var s := -1.0 if i % 2 else 1.0
			ps.spawn(P.SMOKE, X + s * R.range(2.0, 10.0), -R.range(2.0, 7.0), s * R.range(40.0, 125.0), -R.range(2.0, 14.0), R.range(0.95, 1.5), st.dust, R.range(6.0, 9.0), R.range(0.02, 0.08), PF.BIG)
		for i in 7:
			ps.spawn(P.SMOKE, X + R.range(-6.0, 6.0), -R.range(3.0, 9.0), R.range(-20.0, 20.0), -R.range(30.0, 80.0), R.range(1.0, 1.4), st.dust, R.range(5.0, 7.5), R.range(0.04, 0.14), PF.BIG)
		for i in 8:
			ps.spawn(P.DUST, X + R.range(-6.0, 6.0), -R.range(1.0, 4.0), R.range(-70.0, 70.0), -R.range(8.0, 30.0), R.range(0.35, 0.7), st.dust, R.range(2.0, 3.5))
	bits.update(dt)
	chips.update(dt)
	# settled rocks catch the light now and then
	if hit and t > DROP + 0.4 and t < DROP + 1.2 and R.chance(0.08):
		var b: Variant = null
		if bits.list.size():
			b = R.pick(bits.list)
		else:
			R.next()  # JS picks undefined from an empty list, but still draws a number
		if b != null and b.rest:
			ps.spawn(P.STAR, b.x + R.range(-1.0, 1.0), b.y - 1.5 - b.s, 0.0, -2.0, R.range(0.25, 0.45), HOT[0] if R.chance(0.5) else WHITE, R.range(0.6, 1.6))
	# rocks that land kick up a little dust
	for b: Dictionary in bits.list:
		if b.rest and not b.get("dusted", false):
			b.dusted = true
			for i in 3:
				ps.spawn(P.DUST, b.x + R.range(-1.5, 1.5), -0.5, R.sign() * R.range(8.0, 35.0), -R.range(2.0, 14.0), R.range(0.3, 0.6), st.dust, R.range(1.3, 2.6))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var q := t - DROP
	if q >= 0.0:
		# the dent: the floor's top knocked down into a shallow pit, its surface lit at the bottom, chipped lips
		var fade := 1.0 - Px.smooth(1.3, 1.7, q)
		for x in range(-11, 12):
			var u := x / 10.0
			var d := 0.0 if absi(x) > 10 else Px.round(3.2 * (1.0 - u * u) + (Px.rand(x, 4) - 0.5) * 0.8)
			var y := 0
			while y < d:
				p.dot(X + x, y, SOOT if y == 0 else st.dark, fade)
				y += 1
			if d > 0.0:
				p.dot(X + x, d, st.light if absi(x) < 7 else st.body, fade)
			if absi(x) >= 8:
				p.dot(X + x, -1.0, st.body if absi(x) >= 10 else st.light, fade)
			if absi(x) == 9 and Px.rand(x, 7) < 0.7:
				p.dot(X + x, -2.0, st.body, fade)
		# the floor ring's far half
		var k := q / 0.5
		if k < 1.0:
			Px.band(p, X, 0.5, 6.0 + 50.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 2.0 * (1.0 - k)), 1.15 - k, [st.body, C[3], C[5], C[7]], func(g): return sin(g) < 0.0)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var q := t - DROP
	wedge(p)
	if q >= 0.0:
		# cracks split out of the dent: a white flash, then dark lines that fade with the dent
		var fade := 1.0 - Px.smooth(1.3, 1.7, q)
		for c: Dictionary in lines:
			var reach := 30.0 * Px.Ease.outCubic(Px.clamp((q - c.at * 0.06) / 0.08)) * (0.3 if c.fork else 1.0)
			if reach > 0.0:
				Lib.along(c.pts, reach, func(x0, y0, x1, y1):
					if q >= 0.12:
						p.line(x0, y0 + 3.0, x1, y1 + 3.0, st.shade, fade)
					p.line(x0, y0 + 2.0, x1, y1 + 2.0, WHITE if q < 0.05 else (C[5] if q < 0.12 else SOOT), fade))
		# the near half of the floor ring
		var k := q / 0.5
		if k < 1.0:
			Px.band(p, X, 0.5, 6.0 + 50.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 2.0 * (1.0 - k)), 1.15 - k, [st.body, C[3], C[5], C[7]], func(g): return sin(g) >= 0.0)
		# the dome of force swells off the floor, thins to dots and fades
		var d := (q - 0.045) / 0.4
		if d >= 0.0 and d < 1.0:
			# solid steps through the shell (white rim, two blues inside); it dissolves as a whole at the end
			var r := 12.0 + 30.0 * Px.Ease.outCubic(d)
			var th := maxf(1.0, 3.6 * pow(1.0 - d, 0.8))
			var a := 1.0 if d < 0.6 else (1.0 - d) / 0.4
			var X_ := X
			var C_ := C
			p.shade(X - r - 1.0, -r - 1.0, X + r + 1.0, 0.0, func(x, y, out):
				var e := r - Px.hypot(x - X_, y)
				if e < 0.0 or e > th or y > -0.5:
					return
				var v := e / th
				out.c = (WHITE if v < 0.6 else C_[6]) if d < 0.1 else ((WHITE if d < 0.45 else C_[6]) if v < 0.34 else (C_[5] if v < 0.67 else C_[4]))
				out.a = a)
			for i in 7:
				var g := -PI * (0.08 + (i / 6.0) * 0.84)
				p.glow(X + cos(g) * r, sin(g) * r, 14.0, C[4], 0.36 * (1.0 - d))
		# rays of light shoot up out of the slam
		if q < 0.2:
			for ry: Dictionary in rays:
				var d1: float = ry.L * Px.Ease.outCubic(minf(1.0, q / 0.05))
				var d0: float = ry.L * Px.smooth(0.04, 0.2, q)
				var ca := cos(ry.a)
				var sa := sin(ry.a)
				if d1 - d0 < 1.0:
					continue
				var C_ := C
				p.line(X + ca * (2.0 + d0), -1.0 + sa * (2.0 + d0), X + ca * d1, -1.0 + sa * d1, func(u): return WHITE if u < 0.5 else (C_[6] if u < 0.8 else C_[5]))
				p.glowLine(X + ca * d0, -1.0 + sa * d0, X + ca * d1, -1.0 + sa * d1, 4.0, C[5], 0.18 * (1.0 - q / 0.2))
		# the white slam: a flat flash on the floor for two frames
		if q < 0.07:
			var hot := q < 0.035
			var rx := 16.0 if hot else 12.0
			var ry := 3.0 if hot else 2.0
			p.ellipse(X, 0.0, rx + 2.0, ry + 1.0, C[6] if hot else C[5])
			p.ellipse(X, 0.0, rx, ry, WHITE if hot else C[7])
		if q < 0.2:
			var pop := exp(-q / 0.05)
			p.glow(X, -5.0, 26.0, C[5], 0.3 * pop)
		# the struck stone stays warm for a moment
		p.glow(X, -1.0, 16.0, HOT[2], 0.28 * exp(-q / 0.35))
	for b: Dictionary in bits.list:
		Lib.rock(p, b, st)
	for b: Dictionary in chips.list:
		var k: float = b.life / b.max
		var c: int = HOT[0] if k > 0.7 else (HOT[1] if k > 0.45 else (HOT[2] if k > 0.25 else HOT[3]))
		p.dot(b.x, b.y, c, minf(1.0, k * 4.0))
		if not b.rest:
			p.dot(b.x - b.vx * 0.012, b.y - b.vy * 0.012, HOT[3], minf(1.0, k * 4.0))
		p.glow(b.x, b.y, 4.0, c, 0.35 * k)
	ps.draw(p, "front")
	lights.draw(p)
