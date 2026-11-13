# port-of: src/fx/shadow/eclipse.js@c2470b8ce9331480f33a35afbda4dbc409ded984
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Eclipse",
	"desc": "A black moon over the sun: a breathing pearl corona with long streamers, a thin white rim, and one diamond bead blazing on its edge.",
	"tags": ["shadow", "eclipse", "moon", "sun", "corona", "sky", "magic", "loop"],
	"size": [160, 144],
	"origin": [80, 72],
	"duration": 4,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {"palette": Lib.VOID, "pearl": ["#5a4f8a", "#a99be0", "#e6defa", "#fffaf2"], "seed": 3},
}

# the moon's radius, the loop, where the bead blazes on the rim (radians, 0 = right, up is negative)
const R := 19.0
const D := 4.0
const BEAD := -0.72


static func breathe(t: float, k: float, ph: float) -> float:
	return sin((TAU * k * t) / D + ph)


# streamers: crowded toward the equator (left and right), longer there, each curving off as it goes out
static var STREAMS := Px.arr(30, func(i):
	var side := 0.0 if i % 2 else PI
	var spread := (Px.rand(i, 1) - 0.5) * (1.3 if Px.rand(i, 2) < 0.7 else 3.1)
	var a := side + spread
	var eq := absf(cos(a))
	return {"a": a, "len": (10.0 + Px.rand(i, 3) * 28.0) * (0.45 + 0.75 * eq), "curl": (Px.rand(i, 4) - 0.5) * 0.00018, "k": 1 + (i % 3), "ph": Px.rand(i, 5) * TAU, "w": Px.rand(i, 6)})


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var Q := Px.fit(o.pearl, 4)
	var S: float = o.seed
	# stars twinkling in the dark sky round it
	Px.cycle(t, D, 26, S, func(r): return r.range(1.2, 2.6), func(age, L, r):
		var x: float = r.range(-78.0, 78.0)
		var y: float = r.range(-70.0, 70.0)
		if Px.hypot(x, y) < R + 22.0:
			return
		var k := sin((PI * age) / L)
		p.dot(x, y, WHITE if k > 0.7 else Q[1], k * 1.2)
		if k > 0.85 and r.next() < 0.4:
			p.dot(x - 1.0, y, Q[0], 0.8)
			p.dot(x + 1.0, y, Q[0], 0.8))
	# the outer corona's light: a wide pearly bloom, breathing
	var b := 1.0 + 0.08 * breathe(t, 1.0, 0.0)
	p.glow(0.0, 0.0, 72.0 * b, C[4], 0.38)
	p.glow(0.0, 0.0, 46.0 * b, Q[1], 0.34)
	# streamers: fine rays of pearl, white at the root, thinning to violet, curling as they go out
	for s: Dictionary in STREAMS:
		var L: float = s.len * (1.0 + 0.18 * breathe(t, s.k, s.ph))
		var d := 4.0
		while d <= L:
			var u := d / L
			var a: float = s.a + s.curl * d * d
			var r := R + 1.0 + d
			var x := cos(a) * r
			var y := sin(a) * r
			p.dot(x, y, Q[2] if u < 0.3 else (Q[1] if u < 0.65 else C[5]), 1.0 if u < 0.75 else (1.0 - u) * 4.0)
			d += 0.5
		p.glowLine(cos(s.a) * (R + 4.0), sin(s.a) * (R + 4.0), cos(s.a) * (R + L * 0.6), sin(s.a) * (R + L * 0.6), 3.0, Q[1], 0.12)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var Q := Px.fit(o.pearl, 4)
	var b := 1.0 + 0.08 * breathe(t, 1.0, 0.0)
	# the inner corona: a bright collar hugging the moon, finely streaked, fading out through pearl to violet
	var W := R + 10.0
	p.shade(-W, -W, W, W, func(x, y, out):
		var r: float = sqrt(x * x + y * y)
		if r < R - 0.5 or r > R + 9.0 * b:
			return null
		var a: float = atan2(y, x)
		var e := (r - R) / (9.0 * b)
		var streak := 0.55 + 0.3 * cos(a * 23.0 + sin(a * 5.0) * 2.0) + 0.15 * cos(a * 41.0 - (TAU * t) / D)
		var I := pow(1.0 - e, 2.2) * streak * (0.75 + 0.4 * absf(cos(a)))
		if r < R + 0.9:
			return Q[3]
		if I < 0.1:
			return null
		if I > 0.45 and ((floori(x) + floori(y)) & 1) == 0:
			out.k = 0.2 * I
		return Q[2] if I > 0.72 else (Q[1] if I > 0.42 else (C[5] if I > 0.22 else C[4])))
	# the moon: black, a whisper of earthshine on its left limb
	p.shade(-R, -R, R, R, func(x, y):
		var r: float = sqrt(x * x + y * y)
		if r >= R - 0.5:
			return null
		return C[1] if (r > R - 2.2 and x < -R * 0.45) else C[0])
	# the diamond bead: a blazing point on the rim, rays flaring out and breathing
	var bx := cos(BEAD) * (R + 0.4)
	var by := sin(BEAD) * (R + 0.4)
	var k := 0.75 + 0.25 * breathe(t, 2.0, 1.0)
	for i in 8:
		var a := (i * PI) / 4.0 + 0.12
		var len := (7.0 if i % 2 else 22.0) * k * (1.6 if (i == 1 or i == 5) else 1.0)
		var d := 1.0
		while d <= len:
			var u := d / len
			var x := bx + cos(a) * d
			var y := by + sin(a) * d
			if x * x + y * y < pow(R - 0.5, 2.0):
				break
			p.dot(x, y, WHITE if u < 0.35 else (Q[2] if u < 0.7 else Q[1]), 1.0 if u < 0.5 else (1.0 - u) * 2.2)
			d += 0.5
	p.circle(bx, by, 3.0 * k, Q[2])
	p.circle(bx, by, 2.2 * k, Q[3])
	p.circle(bx, by, 1.4, WHITE)
	p.glow(bx, by, 46.0 * k, Q[2], 0.8 * k)
	p.glow(bx, by, 14.0, WHITE, 0.8)
	Lib.halo(p, 0.0, 0.0, R - 0.5, R + 16.0, Q[2], 0.35 * b)
	Lib.unlight(p, -R, -R, R, R, func(x, y): return x * x + y * y < pow(R - 0.6, 2.0))
