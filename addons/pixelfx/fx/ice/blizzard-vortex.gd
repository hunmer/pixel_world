# Particles and bands that pass behind and in front of a centre (dim far half drawn back, bright near half
# drawn front) follow the recipe in Sprite Fusion's open-source black hole
# (https://www.spritefusion.com/pixel-art-vfx/black-hole), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ice/blizzard-vortex.js@bd397bfc79222dfb4c2ecc5268e8a019e175544f
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Blizzard vortex",
	"desc": "A swirling snow tornado: wind bands spin up a leaning funnel, flakes and ice crystals orbit in front and behind, snow boils at its foot and cold light fills its throat.",
	"tags": ["ice", "snow", "blizzard", "tornado", "vortex", "wind", "loop"],
	"size": [128, 116],
	"origin": [64, 102],
	"duration": 2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "height": 80, "seed": 17},
}

const TILT := 0.24  # how flat the funnel's rings look


# the funnel: radius by height (narrow foot, wide mouth) and an axis that sways (one full sway a loop)
static func radius(h: float, H: float) -> float:
	return 4.0 + 28.0 * pow(Px.clamp(h / H), 1.35)


static func axis(h: float, H: float, ph: float) -> float:
	return (5.0 * sin(TAU * ph + h * 0.05) + 1.5 * sin(TAU * ph * 2.0 - h * 0.11)) * (h / H) - 2.0 * (h / H)


# wind streaks: arcs of snow-laden air swirling round the funnel and climbing it, a bright head and a fading
# tail, faster low down; the far half of each arc goes behind, the near half in front
static func streaks(p: Px.Painter, C: Array, t: float, o: Dictionary, front: bool) -> void:
	var D: float = meta.duration
	var H: float = o.height
	var ph := t / D
	Px.cycle(t, D, 58, o.seed + 9.0, func(g: Px.Rng) -> float: return g.range(0.5, 0.9), func(age: float, life: float, r: Px.Rng) -> void:
		var h0 := r.range(2.0, H)
		var w := r.range(8.0, 12.0) * (1.45 - h0 / H)
		var th := r.range(0.0, TAU) + age * w
		var k := age / life
		var fade := minf(1.0, age / 0.08) * ((1.0 - k) / 0.3 if k > 0.7 else 1.0)
		var L := r.range(0.7, 1.5)
		var m := ceili(L / 0.07)
		for j in m + 1:
			var a := th - j * 0.07
			var s := sin(a)
			if (s >= 0.0) != front:
				continue
			var h := minf(H + 4.0, h0 + age * 16.0 - j * 0.25)
			var R := radius(minf(h, H), H) * (1.0 + minf(0.3, maxf(0.0, h - H * 0.84) * 0.03))
			var u := j / float(m)
			var x := axis(minf(h, H), H, ph) + cos(a) * R
			var y := -h + s * R * TILT
			var c: int = (WHITE if u < 0.15 else (C[6] if u < 0.5 else C[5])) if front else (C[5] if u < 0.3 else (C[4] if u < 0.6 else C[3]))
			p.dot(x, y, c, fade * (1.0 if u < 0.6 else 1.5 - u * 1.2) * (1.0 if front else 0.85)))


# the body: a translucent column of snow-filled air, densest at the edges where you look through more of it
static func body(p: Px.Painter, C: Array, ph: float, H: float) -> void:
	p.each(-44.0, -H - 6.0, 44.0, 2.0, func(x: float, y: float, sx: int, sy: int) -> void:
		var h := -y
		if h < 0.0 or h > H + 4.0:
			return
		var R := radius(h, H)
		var dx := x - axis(h, H, ph)
		var u := dx / R
		if u * u >= 1.0:
			return
		var k := h / H
		var rim := pow(absf(u), 3.0)
		var swirl := sin(asin(u) * 3.0 - TAU * ph * 2.0 + h * 0.2) * 0.5 + 0.5
		var a := (0.07 + 0.24 * rim + 0.12 * swirl) * Px.clamp((1.0 - absf(u)) / 0.18) * (maxf(0.0, (1.0 - k) / 0.3) if k > 0.7 else 1.0) * (h / 4.0 if h < 4.0 else 1.0)
		if a < 0.03:
			return
		p.blendPx(sx, sy, C[6] if rim > 0.5 else (C[5] if swirl > 0.6 else C[4]), a)
		if rim > 0.3 or swirl > 0.75:
			p.add(sx, sy, C[5], 0.16 * maxf(rim, swirl - 0.5) * (1.0 - k * 0.5)))


# snow and ice carried round: rising on a spiral, faster low down, flung out at the top
static func orbiters(p: Px.Painter, C: Array, t: float, o: Dictionary, front: bool) -> void:
	var D: float = meta.duration
	var H: float = o.height
	var ph := t / D
	Px.cycle(t, D, 76, o.seed, func(g: Px.Rng) -> float: return g.range(0.9, 1.6), func(age: float, life: float, r: Px.Rng, i: int) -> void:
		var h0 := r.range(0.0, H * 0.6)
		var h := h0 + age * r.range(14.0, 30.0)
		var k := age / life
		if h > H + 8.0:
			return
		var w := r.range(7.0, 11.0) * (1.5 - h / H)
		var th := r.range(0.0, TAU) + age * w
		var out := 1.0 + r.range(0.05, 0.3) + minf(0.35, maxf(0.0, h - H * 0.82) * 0.04)
		var R := radius(minf(h, H), H) * out
		var s := sin(th)
		if (s >= 0.0) != front:
			return
		var x := axis(minf(h, H), H, ph) + cos(th) * R
		var y := -h + s * R * TILT
		var big := i % 5 == 0
		var fade := minf(1.0, age / 0.1) * ((1.0 - k) / 0.2 if k > 0.8 else 1.0)
		if fade <= 0.0:
			return
		# a streak back along its path, a bright head
		var th2 := th - 0.25
		var x2 := axis(minf(h, H), H, ph) + cos(th2) * R
		var y2 := -h + 2.0 + sin(th2) * R * TILT
		if front:
			p.line(x2, y2, x, y, func(u: float) -> int: return C[6] if u > 0.6 else C[4], func(u: float) -> float: return u * fade)
			p.dot(x, y, WHITE if big else (WHITE if r.chance(0.5) else C[6]), fade)
			if big:
				for d: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					p.dot(x + d[0], y + d[1], C[6], fade)
				p.glow(x, y, 5.0, C[5], 0.35 * fade)
		else:
			p.line(x2, y2, x, y, C[3], func(u: float) -> float: return u * fade * 0.8)
			p.dot(x, y, C[5] if big else C[4], fade))


# snow boiling at the foot: soft puffs spinning round the base, lit on top
static func foot(p: Px.Painter, C: Array, t: float, o: Dictionary, front: bool) -> void:
	var D: float = meta.duration
	var ph := t / D
	Px.cycle(t, D, 12, o.seed + 5.0, func(g: Px.Rng) -> float: return g.range(0.8, 1.2), func(age: float, life: float, r: Px.Rng) -> void:
		var th := r.range(0.0, TAU) + age * r.range(4.0, 6.0)
		var R := 9.0 + age * r.range(8.0, 16.0)
		var s := sin(th)
		var k := age / life
		if (s >= 0.0) != front:
			return
		var x := axis(0.0, 1.0, ph) + cos(th) * R
		var y := -2.0 - age * r.range(4.0, 10.0) + s * R * 0.2
		var rad := 2.0 + 4.0 * k
		var a := 0.5 * pow(1.0 - k, 1.2) * minf(1.0, age / 0.1)
		p.disc(x, y, rad, C[6] if front else C[5], func(d: float) -> float: return a * (1.0 - d * d))
		p.disc(x - rad * 0.25, y - rad * 0.3, rad * 0.5, WHITE, func(d: float) -> float: return a * 0.5 * (1.0 - d * d) * (1.0 - k)))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	# a snow drift on the floor, swept round
	for x in range(-30, 31):
		var d := absf(x) / 30.0
		var hgt := Px.round((1.0 - d * d) * (1.5 + Px.rand(x, 3) * 1.5))
		var j := 0
		while j < hgt:
			p.px(x, -j, WHITE if j == hgt - 1.0 else C[5])
			j += 1
		p.dot(x, 0.0, C[6], 1.0 - d * 0.5)
		p.dot(x, 1.0, C[4], 0.8 - d * 0.6)
	p.glow(0.0, -2.0, 40.0, C[4], 0.22)
	foot(p, C, t, o, false)
	streaks(p, C, t, o, false)
	orbiters(p, C, t, o, false)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var H: float = o.height
	var ph: float = t / meta.duration
	body(p, C, ph, H)
	# cold light in its throat
	p.glow(axis(H * 0.45, H, ph), -H * 0.45, 40.0, C[4], 0.3)
	p.glow(axis(H * 0.15, H, ph), -H * 0.15, 18.0, C[5], 0.4 + 0.1 * sin(TAU * ph * 4.0))
	p.glow(axis(H * 0.05, H, ph), -3.0, 10.0, WHITE, 0.3)
	streaks(p, C, t, o, true)
	orbiters(p, C, t, o, true)
	foot(p, C, t, o, true)
	# snow thrown off the mouth, spreading into a thin cloud
	Px.cycle(t, meta.duration, 10, o.seed + 3.0, func(g: Px.Rng) -> float: return g.range(0.9, 1.3), func(age: float, life: float, r: Px.Rng) -> void:
		var th := r.range(0.0, TAU)
		var R := radius(H, H) * (0.6 + age * 0.9)
		var k := age / life
		var rad := 3.0 + 6.0 * k
		var Rc := minf(R, 36.0)
		var x := axis(H, H, ph) + cos(th) * Rc
		var y := -H - 2.0 - age * 4.0 + sin(th) * Rc * TILT
		var a := 0.24 * (1.0 - k) * minf(1.0, age / 0.15)
		p.disc(x, y, rad * 0.8, C[6], func(d: float) -> float: return a * (1.0 - d * d))
		p.glow(x, y, rad * 1.5, C[4], 0.08 * (1.0 - k)))
