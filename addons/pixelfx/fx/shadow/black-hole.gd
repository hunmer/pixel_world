# The dithered tone ramp and the brighter, bluer approaching side are adapted from Sprite Fusion's open-source
# black-hole (https://www.spritefusion.com/pixel-art-vfx/black-hole), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/shadow/black-hole.js@d2a0e717b21dbb38198a246bef8f5505f421137f
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Black hole",
	"desc": "A tilted disk of banded rings turns round a black hole, its far side bent up over the top and under the bottom; debris spirals in, stretches and is swallowed.",
	"tags": ["shadow", "black-hole", "void", "space", "gravity", "dark", "magic", "loop"],
	"size": [184, 132],
	"origin": [92, 124],
	"duration": 4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOID, "rock": ["#120d1c", "#2e2440", "#544468", "#857399"], "seed": 4},
}

# the hole's centre, its shadow, how hard it bends light; the disk's tilt (screen angle, and how open it is)
# light bent over the top left the far side's upper face, so the arch sees the disk more face-on (SI_ARCH)
const Y := -70.0
const RS := 13.5
const E := 17.5
const SI := 0.25
const SI_ARCH := 0.46
const TILT := -0.14
const D := 4.0
static var CT := cos(TILT)
static var ST := sin(TILT)
# rings with gaps between them, inner ones hotter and turning faster (whole turns of pattern a loop)
const BANDS := [
	{"r0": 18.0, "r1": 24.0, "n": 5.0, "hot": 1.35, "k": 0.3},
	{"r0": 26.0, "r1": 34.0, "n": 3.0, "hot": 0.92, "k": 1.9},
	{"r0": 35.5, "r1": 46.0, "n": 2.0, "hot": 0.64, "k": 3.7},
	{"r0": 47.5, "r1": 60.0, "n": 1.0, "hot": 0.42, "k": 5.2},
]
const ROUT := 60.0
static var BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map(func(v): return (v + 0.5) / 16.0)
static var ICE := Px.hex("#e4f7ff")


# brightness of the disk at a point of its plane (X across, Z away from us), banded, streaked, turning
static func disk(X: float, Z: float, t: float) -> Variant:
	var rho := sqrt(X * X + Z * Z)
	for b: Dictionary in BANDS:
		if rho < b.r0 or rho > b.r1:
			continue
		var w: float = (rho - b.r0) / (b.r1 - b.r0)
		var ph: float = atan2(Z, X) - (TAU * b.n * t) / D
		var streak: float = 0.62 + 0.22 * cos(7.0 * ph + rho * 0.8 + b.k) + 0.16 * cos(13.0 * ph - rho * 1.6 + b.k * 2.0)
		var lane: float = 0.72 + 0.28 * cos(rho * 2.3 + b.k)
		var edge := Px.smooth(0.0, 0.18, w) * (1.0 - Px.smooth(0.78, 1.0, w))
		return {"I": b.hot * streak * lane * (0.35 + 0.65 * edge), "dop": -X / rho}
	return null


# the hole and its disk, ray by ray: the near half straight in front, the far half seen through the bend
# (above the hole, and as a thin second image below it), the shadow, and the photon ring at its edge
static func hole(p: Px.Painter, C: Array, t: float, pulse: float) -> void:
	var RAMP := [C[1], C[2], C[3], C[4], C[5], C[6], C[7], WHITE]
	var n := RAMP.size()
	var W := ROUT + 2.0
	var H := 42.0
	p.shade(-W, Y - H, W, Y + H, func(x, y, out):
		var dx: float = x
		var dy: float = y - Y
		var u := dx * CT + dy * ST
		var v := -dx * ST + dy * CT
		var r := sqrt(u * u + v * v)
		var s: Variant = null
		if v > 0.0:
			s = disk(u, -v / SI, t)
		if s == null and r > RS:
			var k := 1.0 - (E * E) / (r * r)
			var bu := u * k
			var bv := v * k
			var si := SI_ARCH if k > 0.0 else SI
			if -bv / si > 0.0:
				s = disk(bu, -bv / si, t)
		if s == null or s.I < 0.06:
			if r < RS - 0.4:
				return C[0]
			if r < RS + 0.7:
				var a := atan2(v, u)
				var f := 0.5 + 0.5 * cos(3.0 * a + (TAU * 2.0 * t) / D) + pulse * 0.4
				out.k = 0.3
				return WHITE if f > 0.55 else C[7]
			return null
		# tone: dithered between ramp steps; the side turning toward us brighter and icier
		var I: float = s.I * 1.3 * (1.0 + 0.55 * s.dop) * (1.0 + 0.25 * pulse)
		var f := Px.clamp(I) * (n - 1)
		var i := floori(f)
		if f - i > BAYER[((floori(y) & 3) << 2) | (floori(x) & 3)]:
			i = mini(n - 1, i + 1)
		if i == 0 and I < 0.12:
			return null
		var c: int = RAMP[i]
		if s.dop > 0.35 and i >= n - 3:
			c = Px.mix(c, ICE, minf(1.0, (s.dop - 0.35) * 2.0))
		if s.dop < -0.4 and i >= 2 and i < n - 2:
			c = Px.mix(c, C[3], 0.35)
		if i >= n - 4 and ((floori(x) + floori(y)) & 1) == 0:
			out.k = 0.3 * minf(1.0, I - 0.35)
		return c)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	p.glow(0.0, -1.0, 44.0, C[4], 0.12)
	p.glow(0.0, Y, 80.0, C[4], 0.32)
	p.glow(0.0, Y, 46.0, Px.mix(C[6], C[5], 0.5), 0.45)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var K := Px.fit(o.rock, 4)
	var S: float = o.seed
	# a gulp as debris is swallowed, twice a loop
	var pulse := pow(maxf(0.0, cos((TAU * 2.0 * t) / D)), 12.0)
	# pebbles torn off the floor, rising to join the disk
	Px.cycle(t, D, 10, S + 3.0, func(r): return r.range(1.6, 2.6), func(age, L, r):
		var x0: float = r.range(-60.0, 60.0)
		var u := pow(age / L, 1.5)
		var tx: float = Px.sign(x0 if x0 else 1.0) * r.range(40.0, 56.0)
		var ty: float = Y + r.range(4.0, 9.0)
		var x := x0 + (tx - x0) * u
		var y := -1.0 + (ty + 1.0) * u - sin(PI * u) * 10.0
		p.px(x, y, K[3] if u > 0.6 else K[2])
		if age < 0.25:
			p.disc(x0, -1.5, 2.0 + age * 8.0, K[2], 0.4 * (1.0 - age / 0.25)))
	hole(p, C, t, pulse)
	# motes streaking in from all round, turning with the disk as they fall
	Px.cycle(t, D, 40, S + 7.0, func(r): return r.range(0.5, 0.9), func(age, L, r):
		var a0: float = r.range(0.0, TAU)
		var d0: float = r.range(48.0, 76.0)
		var q := pow(age / L, 1.6)
		var d := RS + 2.0 + (d0 - RS - 2.0) * (1.0 - q)
		var a := a0 + 0.9 * q
		var x := cos(a) * d * 1.15
		var y := Y + sin(a) * d * 0.75
		var q2 := pow(maxf(0.0, age - 0.09) / L, 1.6)
		var d2 := RS + 2.0 + (d0 - RS - 2.0) * (1.0 - q2)
		var a2 := a0 + 0.9 * q2
		if d < RS + 3.0 or y > -3.0 or y < -120.0 or Y + sin(a2) * d2 * 0.75 < -120.0 or absf(x) > 90.0:
			return
		var col: int = r.pick([WHITE, C[7], C[6], C[5]])
		p.line(cos(a2) * d2 * 1.15, Y + sin(a2) * d2 * 0.75, x, y, func(u): return col if u > 0.6 else C[4], minf(1.0, age * 6.0))
		p.glow(x, y, 3.0, col, 0.3))
	# debris spiralling in: lumps of rock lit on the side toward the hole, stretched into hot streaks as they
	# fall, gone in a flash at the photon ring; behind the hole they're hidden by it
	Px.cycle(t, D, 22, S, func(r): return r.range(1.4, 2.4), func(age, L, r):
		var ph0: float = r.range(0.0, TAU)
		var rho0: float = r.range(58.0, 80.0)
		var hgt: float = r.range(-8.0, 8.0)
		var size: float = r.range(1.6, 2.8)
		var at := func(aa: float) -> Dictionary:
			var q := Px.clamp(aa / L)
			var rho := RS + 1.0 + (rho0 - RS - 1.0) * (1.0 - pow(q, 1.5))
			var ph := ph0 + 2.4 * pow(q, 1.6) * (1.0 + 1.5 * q)
			var X := cos(ph) * rho
			var Z := sin(ph) * rho
			var sx := X
			var sy := -Z * SI + hgt * (1.0 - q)
			return {"x": sx * CT - sy * ST, "y": Y + sx * ST + sy * CT, "Z": Z, "rho": rho}
		var a: Dictionary = at.call(age)
		var b: Dictionary = at.call(age - 0.04)
		var hidden: bool = a.Z > 0.0 and Px.hypot(a.x, a.y - Y) < RS + 1.0
		if hidden:
			return
		if a.rho < RS + 3.0:
			p.px(a.x, a.y, WHITE)
			p.glow(a.x, a.y, 6.0, C[6], 0.6)
			return
		var heat := 1.0 - Px.smooth(16.0, 34.0, a.rho)
		var len := 1.0 + heat * 7.0
		if heat > 0.05:
			var dx: float = a.x - b.x
			var dy: float = a.y - b.y
			var l := Px.hypot(dx, dy)
			if not l:
				l = 1.0
			p.line(a.x - (dx / l) * len, a.y - (dy / l) * len, a.x, a.y, func(u): return WHITE if u > 0.7 else (C[6] if u > 0.35 else C[4]))
			p.glow(a.x, a.y, 4.0, C[6], 0.4 * heat)
		else:
			var h1 := Px.hypot(a.x, a.y - Y)
			var lx: float = -a.x / (h1 if h1 else 1.0)
			var h2 := Px.hypot(a.x, a.y - Y)
			var ly: float = -(a.y - Y) / (h2 if h2 else 1.0)
			# a lump of rock: a fading wake along its orbit, a dark body, its face toward the hole lit violet
			var c: Dictionary = at.call(age - 0.09)
			var d: Dictionary = at.call(age - 0.15)
			p.px(b.x, b.y, C[3])
			p.dot(c.x, c.y, C[3], 0.7)
			p.dot(d.x, d.y, C[2], 0.5)
			var s2 := size > 2.2
			p.px(a.x, a.y, K[2])
			p.px(a.x + 1.0, a.y, K[1])
			p.px(a.x, a.y + 1.0, K[1])
			if s2:
				p.px(a.x + 1.0, a.y + 1.0, K[0])
				p.px(a.x - 1.0, a.y, K[1])
				p.px(a.x, a.y - 1.0, K[2])
			p.px(a.x + Px.round(lx * 1.4), a.y + Px.round(ly * 1.4), C[6] if s2 else C[5])
			p.glow(a.x, a.y, 4.0, C[5], 0.15))
	Lib.halo(p, 0.0, Y, RS - 0.4, RS + 4.0, C[6], 0.35 + 0.3 * pulse)
	Lib.unlight(p, -RS, Y - RS, RS, Y + RS, func(x, y):
		var dx: float = x
		var dy: float = y - Y
		var v := -dx * ST + dy * CT
		var u := dx * CT + dy * ST
		return u * u + v * v < pow(RS - 0.6, 2.0) and not (v > 0.0 and disk(u, -v / SI, t) != null))
