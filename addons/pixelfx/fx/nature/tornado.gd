# port-of: src/fx/nature/tornado.js@a2efc88293cd3be0a6a45e6b12a53d25d34304c3
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Tornado",
	"desc": "A snaking funnel of spinning wind bands under a flared, churning top that flickers with lightning; leaves and debris whirl round it front and back, dust boils at its foot.",
	"tags": ["nature", "wind", "tornado", "storm", "hazard", "ground", "loop"],
	"size": [196, 168],
	"origin": [98, 152],
	"duration": 2.0,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#141221", "#231f33", "#36314a", "#4d4762", "#68617d", "#8a839e", "#b3adc4", "#e2def0"],
		"dust": ["#2a2018", "#4e3e2e", "#76624a", "#a08a6a", "#cbb894"],
		"leaves": ["#4a200c", "#a8541c", "#e8962e", "#ffd27a", "#123818", "#2f7a2a", "#6cb83a", "#c8f070"],
		"height": 112,
		"seed": 4,
	},
}

const SY := 0.28


# the funnel at time t: its axis snakes (a wave running up it), its radius flares at the top
static func geo(o: Dictionary, t: float) -> Dictionary:
	var ph: float = (TAU * t) / meta.duration
	var FH: float = o.height
	return {
		"FH": FH,
		"ph": ph,
		"ax": func(u: float) -> float: return 8.5 * sin(ph - 2.6 * u) * (0.2 + 0.8 * u) + 3.0 * sin(2.0 * ph + 1.3 - 4.5 * u) * u,
		"rad": func(u: float) -> float: return 3.0 + 20.0 * pow(u, 1.5) + 17.0 * pow(Px.smooth(0.78, 1.0, u), 2.0),
	}


# the body: a translucent column, thicker through its middle, lit from the left, with streaks of dust that
# shear past each other as rows spin at different speeds
static func body(p: Px.Painter, C: Array, Dst: Array, g: Dictionary, t: float, seed: float) -> void:
	var FH: float = g.FH
	var ax: Callable = g.ax
	var rad: Callable = g.rad
	for y in range(-ceili(FH) + 2, 1):
		var u := -y / FH
		var cx: float = ax.call(u)
		var r: float = rad.call(u)
		var K := 2 + (1 if Px.rand(y, seed) < 0.35 else 0)
		var rot: float = (TAU * K * t) / meta.duration
		var fade := minf(1.0, u * 8.0 + 0.25) * (1.0 - Px.smooth(0.9, 1.02, u))
		for x in range(floori(cx - r), ceili(cx + r) + 1):
			var c := (x + 0.5 - cx) / r
			if absf(c) > 1.0:
				continue
			var n := Px.tileNoise(((acos(c) + rot) * 6.0) / TAU, y * 0.34, 6.0, 0.0, seed)
			var v := -c * 0.55 + 0.15 + n * 0.55
			var col: int = C[6] if v > 0.6 else (C[5] if v > 0.28 else (C[4] if v > -0.05 else (C[3] if v > -0.4 else C[2])))
			if u < 0.3:
				col = Px.mix(col, Dst[3 if v > 0.3 else (2 if v > -0.2 else 1)], 0.7 * (1.0 - u / 0.3))
			p.blend(x, y, col, (0.14 + 0.36 * sqrt(1.0 - c * c)) * fade)


# wind bands: 1 px streaks wrapped round the funnel, bright at the head, fading along the tail; the far half
# goes behind, dimmer
static func bands(p: Px.Painter, C: Array, g: Dictionary, t: float, seed: float, back: bool) -> void:
	var FH: float = g.FH
	var ax: Callable = g.ax
	var rad: Callable = g.rad
	for j in 58:
		var R := Px.rng(seed, j)
		var u := (j + R.range(0.1, 0.9)) / 58.0
		var K := R.int_(2, 4)
		var span := R.range(0.7, 2.1)
		var lvl := R.next()
		var cx: float = ax.call(u)
		var r: float = rad.call(u) * R.range(1.0, 1.1)
		var y0 := -u * FH
		var head: float = R.range(0.0, TAU) + (TAU * K * t) / meta.duration
		if u > 0.97:
			continue
		var s := 0.0
		while s <= span:
			var th := head - s
			var sn := sin(th)
			if (sn > 0.0) == back:
				s += 0.5 / maxf(2.0, r)
				continue
			var k := s / span
			var x := cx + r * cos(th)
			var y := y0 + r * SY * sn
			var lit := cos(th) < 0.2
			var i := 2 if lvl < 0.18 else (7 if (k < 0.15 and lvl > 0.55) else ((6 if lit else 5) if k < 0.45 else (5 if lit else 4)))
			if back:
				i = maxi(1, i - 2)
			if k < 0.5:
				p.dot(x, y, C[i])
			else:
				p.blend(x, y, C[i], 2.0 * (1.0 - k))
			s += 0.5 / maxf(2.0, r)
		if not back and lvl > 0.6 and sin(head) > 0.0:
			var hx := cx + r * cos(head)
			var hy := y0 + r * SY * sin(head)
			p.dot(hx, hy, WHITE)
			p.glow(hx, hy, 5.0, C[6], 0.3)


# a soft flattened puff: rx wide, ry tall, blended
static func blob(p: Px.Painter, cx: float, cy: float, rx: float, ry: float, c: int, a: float) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				p.blend(x, y, c, a)


# the flared top: a lid of cloud sheared into flat bands that ride round with the funnel, each thick in the
# middle and drawn out to a thin tail behind, lit along its upper rim, dark beneath; a dark mass at its core
static func crown(p: Px.Painter, C: Array, g: Dictionary, t: float, seed: float, back: bool, flash: float) -> void:
	var FH: float = g.FH
	var ax: Callable = g.ax
	var rad: Callable = g.rad
	var cx: float = ax.call(1.0)
	var r: float = rad.call(1.0)
	var L := func(c: int) -> int: return Px.mix(c, C[7], flash * 0.6)
	var y0 := -FH - 3.0
	if back:
		blob(p, cx, y0 + 1.0, r * 0.85, 6.0, C[1], 0.6)
		blob(p, cx - 4.0, y0 - 3.0, r * 0.6, 3.5, L.call(C[3]), 0.45)
	for j in 16:
		var R := Px.rng(seed, j)
		var rr := r * R.range(0.4, 1.15)
		var K := R.int_(1, 2)
		var span := R.range(1.4, 2.8)
		var head: float = R.range(0.0, TAU) + (TAU * K * t) / meta.duration
		var th0 := R.range(3.2, 6.0)
		var lift := R.range(-4.0, 3.0) - (1.0 - rr / (r * 1.15)) * 5.0
		var s2 := 0.0
		while s2 <= span:
			var th := head - s2
			var sn := sin(th)
			if (sn > 0.0) == back:
				s2 += 0.6 / rr
				continue
			var k := s2 / span
			var th2 := th0 * sin(PI * pow(1.0 - k, 0.7))
			var x := cx + rr * cos(th)
			var y := y0 + lift + rr * SY * sn
			var T := maxi(1, Px.roundi(th2))
			var d := 1 if back else 0
			var lit := cos(th) < 0.3
			for i in T:
				var c: int = L.call(C[(6 if lit else 5) - d]) if i == 0 else (C[1] if (i == T - 1 and T > 2) else L.call(C[(4 if i == 1 else 3) - d]))
				p.blend(x, y - T / 2.0 + i, c, (0.55 + 0.35 * (1.0 - k)) * (0.75 if back else 1.0))
			s2 += 0.6 / rr


# leaves, twigs and pebbles spiralling up round it and flung off the top
static func debris(p: Px.Painter, C: Array, L: Array, g: Dictionary, t: float, seed: float, back: bool, S: Array) -> void:
	var FH: float = g.FH
	var ax: Callable = g.ax
	var rad: Callable = g.rad
	Px.cycle(t, meta.duration, 24, seed, func(q): return q.range(1.3, 1.95), func(age: float, life: float, R: Px.Rng):
		# the first stretch skids in across the floor, then it spirals up and is flung off the top
		var k := age / life
		var sk := R.range(0.15, 0.3)
		var q := Px.clamp((k - sk) / (1.0 - sk))
		var u := Px.lerp(0.03, 0.98, pow(q, 0.85))
		var th := R.range(0.0, TAU) + R.range(2.0, 3.2) * TAU * k
		var sn := sin(th)
		if (sn > 0.0) == back:
			return
		var fling := Px.smooth(0.78, 1.0, q)
		var inward := 1.0 - Px.smooth(0.0, sk, k)
		var far := R.range(26.0, 44.0)
		var rr := Px.lerp(minf(68.0, rad.call(u) * (1.12 + fling * 1.1) + R.range(2.0, 7.0)), far, inward)
		var x: float = ax.call(u) + rr * cos(th)
		var y := minf(-1.0, -u * FH + rr * SY * sn - fling * 8.0)
		var a := minf(1.0, k * 8.0) * (1.0 - Px.smooth(0.85, 1.0, k))
		var kind := R.next()
		var spin := R.range(-14.0, 14.0) * age
		var dk := 1 if back else 0
		if kind < 0.62:
			var o := 0 if R.next() < 0.5 else 4
			var pal := [L[o], L[o + 1], L[o + 2 - dk], L[o + 3 - dk]]
			Lib.drawLeaf(p, x, y, R.range(6.0, 9.0), R.range(1.8, 2.6), spin, age * R.range(5.0, 10.0), pal, a)
		elif kind < 0.8:
			var ca := cos(spin) * 2.5
			var sa := sin(spin) * 2.5
			p.line(x - ca, y - sa, x + ca, y + sa, L[0] if back else L[1], a)
			p.dot(x + ca, y + sa, L[2], a)
		else:
			Lib.drawRock(p, x, y, R.range(1.6, 2.6), spin, Lib.stoneShape(R, 5), S, a))


# at its foot: dust boiling round and out, grit hopping, scuffs swept round the floor
static func skirt(p: Px.Painter, D: Array, g: Dictionary, t: float, seed: float, back: bool) -> void:
	var cx0: float = g.ax.call(0.0)
	Px.cycle(t, meta.duration, 40, seed, func(q): return q.range(0.7, 1.3), func(age: float, life: float, R: Px.Rng):
		var k := age / life
		var th := R.range(0.0, TAU) + R.range(5.0, 9.0) * age
		var sn := sin(th)
		if (sn > 0.0) == back:
			return
		var rr := 4.0 + k * R.range(14.0, 28.0)
		var x := cx0 + rr * cos(th)
		var y := -1.5 - k * R.range(4.0, 16.0) + rr * 0.3 * sn
		var s := R.range(3.0, 6.0) * (0.6 + 0.8 * k)
		var a := minf(1.0, k * 6.0) * (1.0 - k) * 0.6
		p.disc(x, y + s * 0.2, s, D[1 if back else 2], a)
		p.disc(x - s * 0.2, y - s * 0.3, s * 0.55, D[2 if back else 3], a * 0.8))
	if back:
		return
	Px.cycle(t, meta.duration, 16, seed + 7.0, func(q): return q.range(0.35, 0.6), func(age: float, life: float, R: Px.Rng):
		var th := R.range(0.0, TAU)
		var v := R.range(25.0, 55.0)
		var x := cx0 + cos(th) * (4.0 + v * age)
		var y := sin(th) * 2.0 - R.range(40.0, 80.0) * age + 260.0 * age * age
		if y < 0.5:
			p.dot(x, minf(0.0, y), D[3] if R.next() < 0.5 else D[4], 1.0 - age / life))
	for j in 7:
		var R := Px.rng(seed + 3.0, j)
		var rr := R.range(12.0, 28.0)
		var th0: float = R.range(0.0, TAU) + (TAU * 3.0 * t) / meta.duration
		var span := R.range(0.5, 1.1)
		var s := 0.0
		while s < span:
			var th := th0 - s
			p.dot(cx0 + rr * cos(th), 0.5 + rr * 0.18 * sin(th), D[3 if s < span * 0.4 else 2], 1.0 - s / span)
			s += 0.6 / rr


# once a loop the crown lights up from inside
static func flashAt(t: float) -> float:
	var q: float = t / meta.duration
	return maxf(0.0, 1.0 - absf(q - 0.62) / 0.025) + 0.6 * maxf(0.0, 1.0 - absf(q - 0.69) / 0.015)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D := Px.fit(o.dust, 5)
	var g := geo(o, t)
	var f := flashAt(t)
	skirt(p, D, g, t, o.seed * 5.0 + 1.0, true)
	crown(p, C, g, t, o.seed * 7.0 + 2.0, true, f)
	bands(p, C, g, t, o.seed * 3.0 + 5.0, true)
	debris(p, C, Px.fit(o.leaves, 8), g, t, o.seed * 11.0 + 3.0, true, C)
	body(p, C, D, g, t, o.seed)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D := Px.fit(o.dust, 5)
	var g := geo(o, t)
	var f := flashAt(t)
	var cx: float = g.ax.call(1.0)
	bands(p, C, g, t, o.seed * 3.0 + 5.0, false)
	crown(p, C, g, t, o.seed * 7.0 + 2.0, false, f)
	skirt(p, D, g, t, o.seed * 5.0 + 1.0, false)
	debris(p, C, Px.fit(o.leaves, 8), g, t, o.seed * 11.0 + 3.0, false, C)
	# light: a soft pale column, a cold pool at its foot, the crown's lightning
	p.glowLine(g.ax.call(0.1), -g.FH * 0.1, cx, -g.FH * 0.9, 26.0, C[5], 0.08)
	p.glow(g.ax.call(0.0), -2.0, 30.0, D[3], 0.12)
	if f > 0.05:
		var R := Px.rng(o.seed, 99, floori(t / meta.duration * 7.0))
		var path := Px.bolt(R, cx - 18.0, -g.FH - 6.0, cx + 16.0, -g.FH + 2.0, {"jag": 0.3, "depth": 3})
		p.polyline(path, WHITE if f > 0.6 else C[7], minf(1.0, f * 1.5))
		p.glow(cx, -g.FH - 2.0, 70.0, C[7], 0.45 * f)
