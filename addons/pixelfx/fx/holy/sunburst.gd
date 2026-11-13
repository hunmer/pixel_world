# port-of: src/fx/holy/sunburst.js@2083d4e40049dd9e9b183fddb7db37b640c6bfd9
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Sunburst",
	"desc": "A white-hot core in a gold corona; long and short rays turn slowly round it, breathing, with glints running out along them that wink at the tips.",
	"tags": ["holy", "sun", "radiant", "rays", "light", "glow", "loop"],
	"size": [128, 128],
	"origin": [64, 64],
	"duration": 4,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": Lib.GOLD, "rays": 8, "seed": 3},
}

const CORE := 4.5
const RING := 7.5
const R0 := 9.0

static func frac(x: float) -> float:
	return x - floorf(x)


# one tapered ray from radius R0 out to R0 + L at angle a: white at the root, cooling to gold, thinning into light
static func ray(p: Px.Painter, C: Array, a: float, L: float, w0: float, k: float) -> void:
	var ca := cos(a)
	var sa := sin(a)
	var x1 := ca * (R0 + L)
	var y1 := sa * (R0 + L)
	var pad := w0 + 1.0
	p.shade(minf(0.0, x1) - pad, minf(0.0, y1) - pad, maxf(0.0, x1) + pad, maxf(0.0, y1) + pad, func(x: float, y: float, out) -> void:
		var along := x * ca + y * sa - R0
		var u := along / L
		if u < 0.0 or u > 1.0:
			return
		var across := absf(-x * sa + y * ca)
		var w := (w0 / 2.0) * (1.0 - u * 0.85) + 0.25
		if across > w:
			return
		var spine := across < 0.5
		var rim := across > w - 0.6 and w > 0.9
		out.c = ((WHITE if u < 0.4 else (C[6] if u < 0.75 else C[5])) if spine else (C[3] if (rim and u > 0.15) else (C[6] if u < 0.3 else (C[5] if u < 0.62 else C[4]))))
		out.a = k if u < 0.72 else k * (1.0 - (u - 0.72) / 0.28) * 1.2)
	p.glowLine(ca * R0, sa * R0, ca * (R0 + L * 0.8), sa * (R0 + L * 0.8), 5.0, C[5], 0.16 * k)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var N: float = o.rays * 2
	var T: float = meta.duration
	var rot := (t / T) * ((2.0 * TAU) / N)
	p.glow(0.0, 0.0, 62.0, C[4], 0.3 + 0.06 * sin((t / T) * TAU * 2.0))
	# fine threads of light between the rays
	var i := 0
	while i < N:
		var a := rot + ((i + 0.5) * TAU) / N
		var L := 14.0 + 6.0 * sin(a * 3.0 + (t / T) * TAU)
		p.line(cos(a) * (R0 + 1.0), sin(a) * (R0 + 1.0), cos(a) * (R0 + L), sin(a) * (R0 + L), func(u): return C[6] if u < 0.3 else C[5], func(u): return 0.7 - u * 0.8)
		i += 1
	# the rays, long and short by turns, breathing as a wave runs round them
	i = 0
	while i < N:
		var a := rot + (i * TAU) / N
		var long := i % 2 == 0
		var breathe := 0.86 + 0.14 * sin(a * 3.0 - (t / T) * TAU * 2.0)
		var L := (36.0 if long else 21.0) * breathe
		ray(p, C, a, L, 4.0 if long else 2.6, 1.0)
		# a glint runs out along each long ray and winks at the tip
		if long:
			var g := frac((t / T) * 2.0 + (a * 3.0) / TAU)
			var r := R0 + g * L
			if g < 0.9:
				p.px(cos(a) * r, sin(a) * r, WHITE)
				p.glow(cos(a) * r, sin(a) * r, 5.0, C[6], 0.45 * (1.0 - g))
			else:
				Px.sparkle(p, cos(a) * (R0 + L), sin(a) * (R0 + L), 1.0 + 3.0 * sin(((g - 0.9) / 0.1) * PI), WHITE, C[6], 0.5)
		i += 1
	# the corona and the core
	p.shade(-RING - 2.0, -RING - 2.0, RING + 2.0, RING + 2.0, func(x: float, y: float, out) -> void:
		var d := Px.hypot(x, y)
		if d > RING:
			return
		var flick := 0.5 + 0.5 * sin(atan2(y, x) * 5.0 + (t / T) * TAU * 3.0)
		out.c = WHITE if d < CORE else ((WHITE if flick > 0.6 else C[6]) if d < CORE + 1.5 else (C[5] if flick > 0.5 else C[4])))
	p.glow(0.0, 0.0, 16.0, WHITE, 0.28)
	# twinkles round it
	Px.cycle(t, T, 10, o.seed, func(g): return g.range(0.35, 0.7), func(age, life, R):
		var a: float = R.range(0.0, TAU)
		var d: float = R.range(16.0, 44.0)
		var k := sin((age / life) * PI)
		Px.sparkle(p, cos(a) * d, sin(a) * d, 1.0 + 2.4 * k * R.range(0.5, 1.0), WHITE, C[5], 0.4 * k))
