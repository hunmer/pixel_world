# port-of: src/fx/shadow/void-orb.js@63f0c0f52086f7a1d86b3a36c3e14ee68692ec6a
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Void orb",
	"desc": "A black orb hangs in the air, a pale rim crawling round it; a dark vortex winds into it, motes and streaks are pulled in, and light bends round its edge.",
	"tags": ["shadow", "void", "orb", "vortex", "dark", "magic", "loop"],
	"size": [168, 160],
	"origin": [84, 150],
	"duration": 3.2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOID, "seed": 5},
}

# the orb's centre and radius, the vortex's reach, the radius light bends to (Einstein ring), the loop
# matter can't orbit inside GAP: there the dark is empty but for light bent round the orb
const Y := -62.0
const R := 12.0
const VR := 48
const GAP := R + 9.0
const E := R + 4.5
const D := 3.2
const ARMS := 3.0
const K := 7.0
const WIND := (TAU * 2.0) / D
# two gulps a loop: the rim flares, the vortex brightens, a ring is drawn in
const GULPS := [0.2, 0.68]


static func wrap_(x: float) -> float:
	return x - floorf(x)


static func gulp(t: float) -> float:
	return GULPS.reduce(func(s, g): return s + exp(-pow(((wrap_(t / D - g + 0.5) - 0.5) * D) / 0.07, 2.0)), 0.0)


# specks of light behind the orb on looping paths; we see them through the lens: far off, a speck; passing
# behind, smeared into an arc hugging the rim, with a faint second image on the far side
const SOURCES := [
	{"cx": 0.0, "cy": 0.0, "rho": 6.0, "n": 1.0, "ph": 0.0, "s": 2.6, "sy": 0.75},
	{"cx": 1.0, "cy": -1.0, "rho": 8.0, "n": -1.0, "ph": 2.2, "s": 2.0, "sy": 0.6},
	{"cx": 18.0, "cy": -6.0, "rho": 24.0, "n": 1.0, "ph": 0.4, "s": 2.4, "sy": 0.7},
	{"cx": -26.0, "cy": 10.0, "rho": 30.0, "n": 1.0, "ph": 2.6, "s": 2.0, "sy": 0.55},
	{"cx": 8.0, "cy": 22.0, "rho": 20.0, "n": 2.0, "ph": 4.1, "s": 1.6, "sy": 0.8},
	{"cx": -12.0, "cy": -26.0, "rho": 34.0, "n": 1.0, "ph": 5.3, "s": 1.8, "sy": 0.6},
	{"cx": 34.0, "cy": 18.0, "rho": 16.0, "n": 2.0, "ph": 1.2, "s": 1.4, "sy": 0.9},
]

# tables round the orb, built once: radius, angle, log radius, and lumpy turbulence for the vortex
static var TAB: Variant = null


static func tables() -> Dictionary:
	if TAB != null:
		return TAB
	var n := VR * 2
	var N := n * n
	var r := PackedFloat32Array()
	r.resize(N)
	var th := PackedFloat32Array()
	th.resize(N)
	var ln := PackedFloat32Array()
	ln.resize(N)
	var nz := PackedFloat32Array()
	nz.resize(N)
	for j in n:
		for i in n:
			var x := i - VR + 0.5
			var y := j - VR + 0.5
			var k := j * n + i
			var a := atan2(y, x)
			var d := Px.hypot(x, y)
			var l := log(maxf(1.0, d))
			r[k] = d
			th[k] = a
			ln[k] = l
			nz[k] = Px.fbm(cos(a) * 2.5 + l * 2.4, sin(a) * 2.5 + l * 2.4, 17.0, 3)
	TAB = {"n": n, "r": r, "th": th, "ln": ln, "nz": nz}
	return TAB


# the vortex: three arms of dark dust winding inward, a dithered veil threaded with thin bright filaments that
# stream in along them faster than the arms turn, a lit leading edge, all heating to pale violet near the rim
static func vortex(p: Px.Painter, C: Array, t: float, g: float) -> void:
	var T := tables()
	var n: int = T.n
	var wf := (TAU * 12.0) / D
	var Tr: PackedFloat32Array = T.r
	var Tth: PackedFloat32Array = T.th
	var Tln: PackedFloat32Array = T.ln
	var Tnz: PackedFloat32Array = T.nz
	for j in n:
		for i in n:
			var k := j * n + i
			var r := Tr[k]
			if r < GAP or r > VR:
				continue
			var env := Px.smooth(VR, VR * 0.42, r) * Px.smooth(GAP, GAP + 4.0, r)
			var ph := ARMS * Tth[k] + K * Tln[k] + WIND * t + Tnz[k] * 2.6
			var cs := cos(ph)
			var A := (0.5 + 0.5 * cs) * env * (1.0 + 0.4 * g)
			if A < 0.16:
				continue
			var x := i - VR + 0.5
			var y := Y + j - VR + 0.5
			var hot := 1.0 - Px.smooth(GAP, GAP + 16.0, r)
			var fil := cos(12.0 * Tth[k] + 28.0 * Tln[k] + wf * t + Tnz[k] * 1.6)
			# streams break into dashes that run inward with them
			var dash := cos(9.0 * Tln[k] * 2.2 + 2.2 * Tth[k] + wf * 0.75 * t)
			if fil > 0.86 and A > 0.3 and dash > -0.55:
				var c: int = C[7] if hot > 0.6 else (C[6] if ((hot > 0.25 or fil > 0.97) and dash > 0.0) else C[5])
				p.px(x, y, c)
				p.light(x, y, c, 0.1 + 0.2 * hot)
				continue
			# the arm's leading edge, where it turns into the light
			if A > 0.36 and A < 0.46 and sin(ph) > 0.0:
				p.px(x, y, C[6] if hot > 0.4 else C[4])
				continue
			# the veil: translucent dark dust, denser in the arm's heart
			p.blend(x, y, C[3] if A > 0.6 else C[2], minf(0.75, (A - 0.16) * 1.4))


# what the orb's gravity does to light from behind it
static func lensing(p: Px.Painter, C: Array, t: float, g: float) -> void:
	# the Einstein ring itself, faint, brightening as it gulps
	var a := 0.0
	var st := 0.7 / E
	while a < TAU:
		var f := 0.5 + 0.5 * cos(5.0 * a - (TAU * 2.0 * t) / D) + 0.5 * g
		p.px(cos(a) * E, Y + sin(a) * E, C[5] if f > 0.85 else (C[4] if f > 0.45 else C[3]))
		a += st
	for s: Dictionary in SOURCES:
		var q: float = (TAU * s.n * t) / D + s.ph
		var sx: float = s.cx + s.rho * cos(q)
		var sy: float = s.cy + s.rho * sin(q) * s.sy
		var b := maxf(0.3, Px.hypot(sx, sy))
		var al := atan2(sy, sx)
		var root := sqrt(b * b + 4.0 * E * E)
		var images := [[(b + root) / 2.0, al, 1.0], [(root - b) / 2.0, al + PI, 0.55]]
		for img: Array in images:
			var r: float = img[0]
			var a0: float = img[1]
			var w: float = img[2]
			if r < R + 1.5:
				continue
			var mag := (r / b) * w
			var hw: float = minf(PI, (s.s * 1.6) / (2.0 * b))
			var step := 0.6 / r
			var aa := a0 - hw
			while aa <= a0 + hw + 1e-6:
				var u := absf(aa - a0) / hw if hw > 0.0 else 0.0
				var x := cos(aa) * r
				var y := Y + sin(aa) * r
				p.dot(x, y, WHITE if (u < 0.3 and mag > 0.8) else (C[7] if u < 0.65 else C[5]), minf(1.0, mag * 1.4) * (1.15 - u))
				if mag > 1.2 and u < 0.6:
					p.dot(x + cos(aa), y + sin(aa), C[6], 0.8)
				aa += step
			p.glow(cos(a0) * r, Y + sin(a0) * r, 4.0 + minf(10.0, hw * r), C[6], minf(0.5, 0.18 * mag))


# the orb: void black, a dull glint and a crescent of reflected light inside, and a pale rim crawling round
static func orb(p: Px.Painter, C: Array, t: float, g: float) -> void:
	p.shade(-R - 1.0, Y - R - 1.0, R + 1.0, Y + R + 1.0, func(x, y):
		var dx: float = x
		var dy: float = y - Y
		var d := sqrt(dx * dx + dy * dy)
		if d > R + 0.5:
			return null
		var a := atan2(dy, dx)
		if d > R - 0.6:
			var f := 0.5 * cos(3.0 * a - (TAU * 2.0 * t) / D) + 0.3 * cos(7.0 * a + (TAU * 3.0 * t) / D + 1.0) + 0.25 * cos(13.0 * a - (TAU * 5.0 * t) / D + 2.0) + g
			return WHITE if f > 0.5 else (C[6] if f > 0.05 else (C[5] if f > -0.4 else C[4]))
		if R - d < 1.4 and cos(a - 0.8) > 0.6:
			return C[2]
		if pow(dx + R * 0.42, 2.0) + pow(dy + R * 0.45, 2.0) < 1.6:
			return C[3]
		return C[0])


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var g := gulp(t)
	p.glow(0.0, -1.0, 52.0, C[4], 0.22 + 0.1 * g)
	vortex(p, C, t, g)
	lensing(p, C, t, g)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var g := gulp(t)
	var S: float = o.seed
	# dust drawn up off the floor, curving into the orb
	Px.cycle(t, D, 14, S + 2.0, func(r): return r.range(1.6, 2.4), func(age, L, r):
		var x0: float = r.range(-44.0, 44.0)
		var u := pow(age / L, 1.7)
		var sg := Px.sign(x0)
		var side := sg if sg else 1.0
		var ea: float = PI / 2.0 + side * r.range(0.3, 1.0)
		var ex := cos(ea) * R
		var ey := Y + sin(ea) * R
		var mx := x0 * 0.2
		var my: float = -18.0 - r.range(0.0, 12.0)
		var x := (1.0 - u) * (1.0 - u) * x0 + 2.0 * (1.0 - u) * u * mx + u * u * ex
		var y := (1.0 - u) * (1.0 - u) * -1.0 + 2.0 * (1.0 - u) * u * my + u * u * ey
		if age < 0.5:
			p.disc(x0, -1.5, 2.0 + age * 6.0, C[3], 0.4 * (1.0 - age / 0.5))
		p.dot(x, y, C[7] if u > 0.6 else (C[6] if u > 0.25 else C[5]), minf(1.0, age * 4.0))
		if u > 0.3:
			p.glow(x, y, 3.0, C[5], 0.25))
	# motes swirl in along the arms, faster as they fall, and spark on the rim where they're swallowed
	Px.cycle(t, D, 30, S, func(r): return r.range(1.1, 1.8), func(age, L, r):
		var th0: float = r.range(0.0, TAU)
		if sin(th0) > 0.75:
			th0 = -th0
		var r0: float = r.range(30.0, 64.0)
		var sw: float = r.range(1.4, 2.6)
		var col: int = r.pick([WHITE, C[7], C[6], C[6], C[5]])
		var pos := func(aa: float) -> Array:
			var u := Px.clamp(aa / L)
			var k := pow(u, 1.8)
			var rr := R + 1.0 + (r0 - R - 1.0) * (1.0 - k)
			var th := th0 - sw * (k + 0.5 * u)
			return [cos(th) * rr, Y + sin(th) * rr, rr]
		var P0: Array = pos.call(age)
		var P1: Array = pos.call(age - 0.05)
		var x: float = P0[0]
		var y: float = P0[1]
		var rr: float = P0[2]
		var tx: float = P1[0]
		var ty: float = P1[1]
		var a := minf(1.0, age * 5.0)
		if rr < R + 3.0:
			p.px(x, y, WHITE)
			p.glow(x, y, 5.0, C[6], 0.5)
			return
		p.line(tx, ty, (tx + x) / 2.0, (ty + y) / 2.0, C[4], a * 0.8)
		p.line((tx + x) / 2.0, (ty + y) / 2.0, x, y, col, a)
		p.glow(x, y, 3.0, col, 0.3 * a))
	# streaks: long dotted lines shot in from further out, white at the head (never from under the floor)
	Px.cycle(t, D, 9, S + 1.0, 0.42, func(age, L, r):
		var th: float = r.range(0.0, TAU)
		if sin(th) > 0.45:
			th = -th
		var r0: float = r.range(56.0, 74.0)
		var u: float = age / L
		var k := (exp(3.0 * u) - 1.0) / (exp(3.0) - 1.0)
		var rr := r0 - (r0 - R - 1.0) * k
		var len := 2.0 + 10.0 * k
		var ca := cos(th)
		var sa := sin(th)
		var d := 0.0
		while d <= len:
			p.dot(ca * (rr + d), Y + sa * (rr + d), WHITE if d < 1.0 else (C[6] if d < len * 0.5 else C[4]), 1.0 if d < len * 0.5 else 1.2 - d / len)
			d += 0.5
		p.glow(ca * rr, Y + sa * rr, 4.0, C[6], 0.4))
	# a gulp draws a faint ring in after it
	for gp: float in GULPS:
		var u := wrap_(t / D - gp) / (0.4 / D)
		if u >= 1.0:
			continue
		var rr := R + 2.0 + (VR - R) * (1.0 - Px.Ease.inQuad(u))
		Lib.ringFast(p, 0.0, Y, rr, 1.0, C[4], 0.35 * (1.0 - u))
		Lib.ringLight(p, 0.0, Y, rr, 4.0, C[5], 0.3 * (1.0 - u))
	orb(p, C, t, g)
	Lib.halo(p, 0.0, Y, R - 0.5, R + 7.0, C[6], 0.6 + 0.3 * g)
	Lib.halo(p, 0.0, Y, R - 0.5, R + 46.0, C[4], 0.38 + 0.15 * g)
	Lib.unlight(p, -R, Y - R, R, Y + R, func(x, y): return x * x + pow(y - Y, 2.0) < pow(R - 0.6, 2.0))
