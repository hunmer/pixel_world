# The arcs (forking bolts re-struck every frame, inked with halo, body, core and light), their flicker and the
# zaps that strike the floor in a spray of sparks follow Sprite Fusion's open-source lightning and energy orb
# (https://www.spritefusion.com/pixel-art-vfx/lightning), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/tesla-coil.js@0096de912155bb4faa52eb338a9abfa42b75fedd
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Tesla coil",
	"desc": "A copper coil under a steel torus throws branching arcs that lash out in volleys and now and then strike the floor in a spray of sparks, lighting the metal and the ground.",
	"tags": ["lightning", "electric", "tesla", "machine", "prop", "loop"],
	"size": [224, 136],
	"origin": [112, 120],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": Lib.VOLT,
		"sparks": Lib.PLASMA,
		"copper": ["#2a120c", "#5a2814", "#8e4a1e", "#c4772f", "#eaa65a", "#ffd9a0"],
		"steel": ["#0f121c", "#1f2433", "#353d52", "#556078", "#7f8ba3", "#b8c3d6", "#f2f6ff"],
		"seed": 4,
	},
}

const FPS := 30.0
const N := 72
const P := N / FPS
const TY := -57.0
const RR := 12.0
const TR := 3.6
const SY := 0.45
const CTOP := -50.0
const CBOT := -12.0
static var IRON := Px.ramp(["#120f18", "#1e1a27", "#2c2637", "#3f374d", "#5a5068"])
static var ASH := Px.hex("#5b5566")
# an arc's brightness over the frames it lives: struck, flickered, re-struck, gone
const FL := [1.0, 0.7, 0.95, 0.55, 0.85, 0.45, 0.7, 0.35]


# the loop's events, frame by frame: volleys of arcs off the torus, and two zaps to the floor
static func plan(seed: float) -> Dictionary:
	var r := Px.rng(seed, 1)
	var arcs := []
	var strikes := []
	for vn: Array in [[2, 3], [20, 3], [30, 1], [38, 3], [56, 3], [66, 1]]:
		var v: int = vn[0]
		var n: int = vn[1]
		var j := 0
		while j < n + r.int_(0, 1):
			var side := 1 if r.chance(0.5) else -1
			var front := r.chance(0.55)
			var a := r.range(0.15, 1.1)
			var phi := (a if front else -a) if side > 0 else (PI - a if front else PI + a)
			var th0 := r.range(-1.15, 0.35)
			var f0 := (v + j * r.int_(2, 4)) % N
			var ln := r.int_(3, 7)
			var th1 := th0 + r.range(-0.6, 0.6)
			var L := r.range(24.0, 52.0)
			arcs.append({"f0": f0, "len": ln, "side": side, "phi": phi, "front": front, "th0": th0, "th1": th1, "L": L})
			j += 1
	for fs: Array in [[14, 1], [47, -1]]:
		var f0: int = fs[0]
		var side: int = fs[1]
		strikes.append({"f0": f0, "side": side, "x": side * r.range(38.0, 56.0), "phi": 0.4 if side > 0 else PI - 0.4})
	return {"arcs": arcs, "strikes": strikes}


static func ageOf(f: int, f0: int) -> int:
	return (((f - f0) % N) + N) % N


static func root(phi: float, up: float = 0.0) -> Array:
	return [cos(phi) * (RR + TR * 0.6), TY + sin(phi) * RR * SY - up]


# the coil: an iron plinth, two thick primary turns, the secondary wound in copper wire, catching arc light
static func drawCoil(p: Px.Painter, Cu: Array, lit: Array, C: Array) -> void:
	var n := Cu.size()
	p.shade(-14.0, -8.0, 14.0, 0.0, func(x, y, o):
		if x < -13.0 or x > 13.0 or y < -7.0:
			return
		var edge: int = 2 if x < -12.0 else (0 if x > 12.0 else 1)
		o.c = IRON[4] if y < -6.0 else (IRON[3] if y < -5.0 else (IRON[0] if y > -1.0 else IRON[2 if edge + 1 > 2 else edge + (1 if y < -3.0 else 0)])))
	for rx in [-10, 10]:
		p.px(rx, -4.0, IRON[4])
		p.px(rx, -3.0, IRON[0])
	turn(p, Cu, n, -10.5, false)
	turn(p, Cu, n, -13.5, false)
	# the secondary: wire on every other row, lit from the left, a bright band down the front, arc light on the rims
	p.shade(-6.0, CTOP, 6.0, CBOT, func(x, y, o):
		if x < -5.0 or x > 5.0:
			return
		var u: float = (x + 5.5) / 11.0
		var nx := u * 2.0 - 1.0
		var wire := (floori(y) & 1) == 0
		var l := 0.62 - 0.55 * nx - 0.35 * nx * nx + (0.3 if absf(nx + 0.35) < 0.12 else 0.0)
		if not wire:
			l -= 0.32
		o.c = Cu[int(Px.clamp(Px.round(l * (n - 1)), 0.0, n - 1.0))]
		if wire and ((nx < -0.75 and lit[0] > 0.25) or (nx > 0.75 and lit[1] > 0.25)):
			o.c = (C[6] if lit[0] > 0.6 else C[4]) if nx < 0.0 else (C[6] if lit[1] > 0.6 else C[4]))
	p.line(-5.0, CTOP - 1.0, 5.0, CTOP - 1.0, IRON[3])
	p.line(-4.0, CTOP - 2.0, 4.0, CTOP - 2.0, IRON[2])
	turn(p, Cu, n, -10.5, true)
	turn(p, Cu, n, -13.5, true)


static func turn(p: Px.Painter, Cu: Array, n: int, y: float, front: bool) -> void:
	var a := 0.0
	while a < TAU:
		if (sin(a) >= 0.0) != front:
			a += 0.04
			continue
		var x := cos(a) * 10.0
		var yy := y + sin(a) * 2.2
		var l := 0.5 - 0.4 * cos(a) + (0.25 if front else -0.2)
		p.px(x, yy, Cu[int(Px.clamp(Px.round(l * (n - 1)), 0.0, n - 1.0))])
		p.px(x, yy + 1.0, Cu[int(Px.clamp(Px.round(l * (n - 1)) - 2.0, 0.0, n - 1.0))])
		a += 0.04


# the torus, solved once: for every pixel, the normal of the nearest point of a ring tube seen from a little above
static var TORUS: Variant = null
static func torusMap() -> Dictionary:
	if TORUS:
		return TORUS
	var sa := SY
	var ca := sqrt(1.0 - SY * SY)
	var X0 := -ceili(RR + TR) - 1
	var Y0 := floori(TY - RR * SY - TR) - 2
	var W := 2 * -X0 + 2
	var H := ceili(TY + RR * SY + TR) + 3 - Y0
	var z := PackedFloat32Array()
	z.resize(W * H)
	z.fill(-1e9)
	var n := PackedFloat32Array()
	n.resize(W * H * 3)
	for i in 480:
		var phi := (i / 480.0) * TAU
		var cp := cos(phi)
		var sp := sin(phi)
		for j in 96:
			var psi := (j / 96.0) * TAU
			var cs := cos(psi)
			var ss := sin(psi)
			var rr := RR + TR * cs
			var X := rr * cp
			var Y := TR * ss
			var Z := rr * sp
			var px := floori(X) - X0
			var py := floori(TY - Y * ca + Z * sa) - Y0
			var d := Z * ca + Y * sa
			if px < 0 or py < 0 or px >= W or py >= H:
				continue
			var k := py * W + px
			if d > z[k]:
				z[k] = d
				n[k * 3] = cs * cp
				n[k * 3 + 1] = ss
				n[k * 3 + 2] = cs * sp
	TORUS = {"X0": X0, "Y0": Y0, "W": W, "H": H, "z": z, "n": n, "ca": ca, "sa": sa}
	return TORUS


static func norm(x: float, y: float, z: float) -> Array:
	var l := Px.hypot(x, y, z)
	return [x / l, y / l, z / l]
static var KEY := norm(-0.55, 0.75, 0.45)


# steel shaded by a key light from the upper left, a hard specular, dark inner faces, the arcs' light on the sides
static func drawTorus(p: Px.Painter, St: Array, C: Array, lit: Array) -> void:
	var T := torusMap()
	var m := St.size()
	var HALF := norm(KEY[0], KEY[1] + T.sa, KEY[2] + T.ca)
	var TW: int = T.W
	var TH: int = T.H
	var TX0: int = T.X0
	var TY0: int = T.Y0
	var Tz: PackedFloat32Array = T.z
	var Tn: PackedFloat32Array = T.n
	var on := func(x: int, y: int) -> bool: return x >= 0 and y >= 0 and x < TW and y < TH and Tz[y * TW + x] > -1e8
	for y in TH:
		for x in TW:
			var k := y * TW + x
			if Tz[k] < -1e8:
				continue
			var nx := Tn[k * 3]
			var ny := Tn[k * 3 + 1]
			var nz := Tn[k * 3 + 2]
			var dif := maxf(0.0, nx * KEY[0] + ny * KEY[1] + nz * KEY[2])
			var spec := pow(maxf(0.0, nx * HALF[0] + ny * HALF[1] + nz * HALF[2]), 28.0)
			var inner := 0.75 if (nx * (x + TX0 + 0.5) + nz * 0.0 < 0.0 and absf(x + TX0 + 0.5) < RR) else 1.0
			var c: int = St[m - 1] if spec > 0.55 else St[int(Px.clamp(floorf((0.12 + 0.8 * dif * inner + spec) * (m - 1.01)), 0.0, m - 2.0))]
			for sl: Array in [[-1.0, lit[0]], [1.0, lit[1]]]:
				var s: float = sl[0]
				var l: float = sl[1]
				var r := maxf(0.0, s * nx * 0.85 + ny * 0.25 + nz * 0.45) * minf(1.0, l)
				if r > 0.88:
					c = C[6]
				elif r > 0.62:
					c = Px.mix(c, C[5], 0.6)
				elif r > 0.38:
					c = Px.mix(c, C[4], 0.3)
			if not on.call(x, y + 1) and ny < 0.3:
				c = St[0]
			p.px(x + TX0, y + TY0, c)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var Cu := Px.fit(o.copper, 6)
	var St := Px.fit(o.steel, 7)
	var S := Px.ramp(o.sparks)
	var f := floori(t * FPS + 1e-6) % N
	var pl := plan(o.seed)
	var arcs: Array = pl.arcs
	var strikes: Array = pl.strikes
	var lit := [0.0, 0.0]
	var live := arcs.filter(func(a): return ageOf(f, a.f0) < a.len)
	for a: Dictionary in live:
		lit[1 if a.side > 0 else 0] += FL[ageOf(f, a.f0)] * 0.6
	for s: Dictionary in strikes:
		var a := ageOf(f, s.f0)
		if a < 6:
			lit[1 if s.side > 0 else 0] += 1.0
	var act := minf(1.0, (lit[0] + lit[1]) * 0.5)

	# the floor: a cold pool of light under the coil, scorches and smoke where zaps landed
	p.glow(0.0, -10.0, 58.0, C[3], 0.14 + 0.25 * act)
	p.ellipse(0.0, 0.5, 15.0, 1.6, IRON[0])
	for s: Dictionary in strikes:
		var age := Px.wrap(t - s.f0 / FPS, P)
		Lib.scorch(p, s.x, 0.0, 7.0, pow(Px.clamp(1.0 - age / 1.1), 1.3), 1.0 - Px.clamp((age - 1.4) / 0.6))
		for j in 2:
			var u := (age - 0.12 - j * 0.18) / 1.2
			if u > 0.0 and u < 1.0:
				Lib.puff(p, s.x + (3.0 if j else -2.0) + u * 5.0 * s.side, -3.0 - u * 16.0 - j * 2.0, 2.6 + j, u, Px.mix(ASH, C[2], 0.3))

	# arcs off the back of the torus go behind the coil
	for a: Dictionary in live:
		if not a.front:
			drawArc(p, C, o, f, a)
	drawCoil(p, Cu, lit, C)
	drawTorus(p, St, C, lit)
	# corona: a faint violet fuzz crawling over the torus
	var rc := Px.rng(o.seed, 9, f)
	for i in 6:
		var phi := rc.range(0.0, TAU)
		var d := rc.range(1.0, 3.0)
		var x := cos(phi) * (RR + TR + d)
		var y := TY + sin(phi) * (RR * SY + TR + d * 0.7)
		p.px(x, y, C[5] if rc.chance(0.3) else C[3])
		if rc.chance(0.4):
			p.px(x + cos(phi), y + sin(phi) * 0.6, C[2])
		p.glow(x, y, 4.0, C[3], 0.3)
	# brush discharge: short streamers hiss off the rim every frame
	for i in 2:
		var phi := rc.range(0.0, TAU)
		var x0 := cos(phi) * (RR + TR * 0.8)
		var y0 := TY + sin(phi) * (RR * SY + TR * 0.6)
		var a := atan2(sin(phi) * 0.6 - 0.5, cos(phi)) + rc.range(-0.5, 0.5)
		var l := rc.range(4.0, 10.0)
		Lib.crackle(p, Lib.zigzag(rc, x0, y0, x0 + cos(a) * l, y0 + sin(a) * l, 0.4, 0.4), rc.range(0.35, 0.65), C, 0.3)
	p.glow(0.0, TY, 34.0, C[3], 0.18 + 0.3 * act)
	for a: Dictionary in live:
		if a.front:
			drawArc(p, C, o, f, a)

	# zaps to the floor: a full bolt, a flash where it lands, sparks thrown and bouncing
	for s: Dictionary in strikes:
		var age := ageOf(f, s.f0)
		if age < 6:
			var k: float = [1.0, 0.75, 1.0, 0.6, 0.85, 0.4][age]
			var xy := root(s.phi, -2.0)
			var x0: float = xy[0]
			var y0: float = xy[1]
			var r := Px.rng(o.seed, 41, s.f0, f)
			Lib.stroke(p, Lib.zigzag(r, x0, y0, s.x, 0.0, 0.22, 0.55), k, C, 0.95 if age == 0 else 0.8, {"hero": age == 0})
			p.circle(s.x, -1.0, 3.0 * k + 1.5, C[2])
			p.circle(s.x, -1.0, 3.0 * k + 0.5, C[5])
			p.circle(s.x, -1.0, 2.0 * k, WHITE)
			p.glow(s.x, -10.0, 40.0, C[4], 0.55 * k)
			p.glow(s.x, -3.0, 12.0, C[6], 0.5 * k)
			if age < 2:
				p.glow(0.0, -50.0, 120.0, C[3], 0.25 * k)
		var st := Px.wrap(t - s.f0 / FPS, P)
		for j in 18:
			var r := Px.rng(o.seed, 51, s.f0, j)
			var life := r.range(0.3, 0.65)
			if st >= life:
				continue
			var a := -PI / 2.0 + r.range(-1.3, 1.3)
			var sp := r.range(50.0, 190.0)
			var fl := Lib.flight(s.x, -1.0, cos(a) * sp, sin(a) * sp, st, {"floor": 0.0})
			Lib.spark(p, fl[0], fl[1], fl[2], fl[3], 1.0 - st / life, S)
	# sparks spat off the arc tips as they strike
	for a: Dictionary in arcs:
		var age := Px.wrap(t - a.f0 / FPS, P)
		var ang: float = a.th0 if a.side > 0 else PI - a.th0
		var xy := root(a.phi)
		var x0: float = xy[0]
		var y0: float = xy[1]
		for j in 3:
			var r := Px.rng(o.seed, 61, a.f0, j)
			var life := r.range(0.15, 0.35)
			if age >= life:
				continue
			var tx: float = x0 + cos(ang) * a.L * 0.75
			var ty: float = y0 + sin(ang) * a.L * 0.75
			var b := ang + r.range(-0.9, 0.9)
			var sp := r.range(50.0, 150.0)
			var fl := Lib.flight(tx, ty, cos(b) * sp, sin(b) * sp, age, {"floor": 0.0})
			Lib.spark(p, fl[0], fl[1], fl[2], fl[3], 1.0 - age / life, S)


static func drawArc(p: Px.Painter, C: Array, o: Dictionary, f: int, a: Dictionary) -> void:
	var age := ageOf(f, a.f0)
	var u := age / float(maxi(1, a.len - 1))
	var th: float = a.th0 + (a.th1 - a.th0) * Px.Ease.outQuad(u)
	var ang: float = th if a.side > 0 else PI - th
	var xy := root(a.phi)
	var x0: float = xy[0]
	var y0: float = xy[1]
	var L: float = a.L * (0.75 if age == 0 else 1.0)
	var r := Px.rng(o.seed, 21, a.f0, f)
	Lib.stroke(p, Lib.zigzag(r, x0, y0, x0 + cos(ang) * L, y0 + sin(ang) * L, 0.32, 0.75), FL[age], C, 0.6, {"light": 0.4})
	p.glow(x0, y0, 10.0, C[5], 0.5 * FL[age])
