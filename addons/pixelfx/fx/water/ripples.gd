# port-of: src/fx/water/ripples.js@d3352f45bc85a93811e0aa628c49cbc36cc5c027
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Ripples",
	"desc": "A drop plinks on still dark water and rings spread out across it at a low angle: the swell of each ring catches the light, crests glint, and they fade into the calm.",
	"tags": ["water", "ripples", "rings", "surface", "pond", "ambient", "loop"],
	"size": [136, 52],
	"origin": [68, 30],
	"duration": 2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.WATER, "seed": 2},
}

static var D: float = meta.duration
const SY := 0.26
const EVERY := 0.5
const LIFE := 2.0
const RMAX := 60.0
const PATCH := 64.0


# one ring at age a: its radius (fast out, slowing) and strength
static func radius(a: float) -> float:
	return 2.0 + (RMAX - 2.0) * Px.Ease.outCubic(a / LIFE)


static func power(a: float) -> float:
	return pow(1.0 - a / LIFE, 1.5) * minf(1.0, a / 0.08)


# the rings alive at t, newest first: [age, index]
static func alive(t: float) -> Array:
	var out := []
	var k := 0
	while k * EVERY < LIFE:
		var a := fmod(fmod(t - k * EVERY, D) + D, D)
		if a < LIFE:
			out.append([a, Px.round(fmod(fmod(t - a, D) + D, D) / EVERY)])
		k += 1
	return out


# the water: dark and see-through, shading with the slope of the swell each ring carries, so the rings read as
# waves catching the light from the far left, not just lines
static func surface(p: Px.Painter, C: Array, t: float) -> void:
	var rs := alive(t).map(func(e: Array): return [radius(e[0]), power(e[0]), 3.0 + e[0] * 2.2])
	var Y := floorf(-PATCH * SY)
	while Y < PATCH * SY:
		var X := -PATCH
		while X < PATCH:
			var x := X + 0.5
			var y := Y + 0.5
			var z := y / SY
			var r := Px.hypot(x, z)
			var e := r / PATCH
			if e > 1.0:
				X += 1.0
				continue
			var edge := 1.0 - Px.smooth(0.6, 1.0, e)
			p.blend(x, y, C[1], 0.55 * edge)
			var slope := 0.0
			for s: Array in rs:
				var R: float = s[0]
				var k: float = s[1]
				var w: float = s[2]
				var d := r - R
				if d > 2.2 * w or d < -2.2 * w:
					continue
				slope += k * Px.exp(-(pow(d / w, 2.0))) * -sin(d * 1.15) * 1.15
			if slope == 0.0:
				X += 1.0
				continue
			# the side of a swell facing the light (back and left) catches it; the side away from it goes dark
			var face := slope * (-(x * -0.55 + z * -0.84) / maxf(1.0, r))
			if face > 0.18:
				p.blend(x, y, C[5] if face > 0.6 else C[4], minf(0.9, (face - 0.18) * 2.2) * edge)
			elif face < -0.25:
				p.blend(x, y, C[0], minf(0.8, (-face - 0.25) * 2.0) * edge)
			X += 1.0
		Y += 1.0


static func rings(p: Px.Painter, C: Array, t: float, half: float) -> void:
	for e: Array in alive(t):
		var a: float = e[0]
		var i: float = e[1]
		var R := radius(a)
		var k := power(a)
		Lib.ring(p, 0.0, 0.0, R, SY, 0.85 * k, C, {"n": 2.0, "gap": 3.0 + a * 1.4, "half": half, "hot": a < 0.14, "glint": k if (half > 0.0 and a > 0.1) else 0.0, "seed": i + 1.0, "wob": 0.4 + a * 1.1})


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	surface(p, C, t)
	rings(p, C, t, -1.0)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var S: float = o.seed
	rings(p, C, t, 1.0)
	# each ring starts with a drop: a white fleck, a bead thrown up and back down, a little light
	for e: Array in alive(t):
		var a: float = e[0]
		if a < 0.08:
			p.px(0.0, 0.0, WHITE)
			p.px(-1.0, 0.0, C[6])
			p.px(1.0, 0.0, C[6])
			p.glow(0.0, 0.0, 8.0, C[5], 0.5 * (1.0 - a / 0.08))
		var b := a - 0.04
		var h := 90.0 * b - 0.5 * 700.0 * b * b
		if b > 0.0 and h > 0.0:
			p.px(0.0, -h, WHITE)
			p.px(0.0, -h + 1.0, C[5])
	# glints ride the near crests, winking
	Px.cycle(t, D, 10, S + 5.0, func(g: Px.Rng): return g.range(0.25, 0.45), func(age: float, life: float, r: Px.Rng):
		var all := alive(t)
		var ai := floori(r.next() * all.size())
		var a: float = all[ai][0] if ai < all.size() else 0.0
		var ang := r.range(0.3, PI - 0.3)
		var R := radius(a)
		var k := sin((PI * age) / life) * power(a)
		if k < 0.15 or R < 6.0:
			return
		var x := cos(ang) * R
		var y := sin(ang) * R * SY
		p.px(x, y, WHITE)
		if k > 0.5:
			for dd: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				p.px(x + dd[0], y + dd[1], C[6])
		p.glow(x, y, 5.0, C[5], 0.4 * k))
	# a cool light on the water, brightest where the rings start
	p.glow(0.0, 0.0, 40.0, C[4], 0.14)
	p.glow(0.0, 0.0, 14.0, C[5], 0.12)
