# Soft puffs drawn as a body, a denser core and a lit cap, and streaks with a hot head and a cool tail, follow
# the recipes in Sprite Fusion's open-source pixel art VFX (https://www.spritefusion.com/pixel-art-vfx),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ice/frost-breath.js@0afac88eb09d5e236e07158bedae7b180c9cb55e
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Frost breath",
	"desc": "A cone of icy wind blowing right: frost puffs billow out, swell and sink, wind streaks race through, ice crystals tumble and glint off a white-hot mouth.",
	"tags": ["ice", "breath", "frost", "cone", "wind", "directional", "loop"],
	"size": [184, 104],
	"origin": [12, 50],
	"duration": 1.2,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "spread": 0.21, "power": 1, "seed": 11},
}

const SINK := 9.0  # cold air is heavy: it sags a little as it slows


# a puff of frost: a soft body, a denser core sitting low, a lit cap while it's young, a cold haze of light
static func puff(p: Px.Painter, C: Array, x: float, y: float, r: float, a: float, k: float, front: bool) -> void:
	var body: int = C[5] if front else C[4]
	var cap: int = C[7] if front else C[6]
	var soft := func(q: float) -> Callable: return func(d: float) -> float: return q * (1.0 - d * d)
	p.disc(x, y, r, body, soft.call(a * 0.6))
	p.disc(x + r * 0.06, y + r * 0.12, r * 0.68, Px.mix(body, C[3], 0.3), soft.call(a * 0.5))
	if k < 0.55:
		p.disc(x - r * 0.25, y - r * 0.3, r * 0.5, cap, soft.call(a * 0.7 * (1.0 - k / 0.55)))
	p.glow(x, y, r * 1.7, C[4], 0.1 * a)


# the body of the gust: a cone of turbulent, translucent cold air streaming right, brightest at its heart.
# The noise scrolls exactly one tile per loop, so it never seams.
static func gust(p: Px.Painter, C: Array, t: float, o: Dictionary) -> void:
	var ph: float = t / meta.duration
	var sp: float = tan(o.spread) * 1.08
	var S: float = o.seed
	p.each(2.0, -46.0, 170.0, 46.0, func(x: float, y: float, sx: int, sy: int) -> void:
		var u := x / 170.0
		var hw := 2.5 + x * sp
		var yc := 7.0 * u * u
		var v := (y - yc) / hw
		if v * v >= 1.0 or u >= 1.0:
			return
		var n := Px.tileFbm(x * 0.055 - ph * 10.0, (y - yc) * 0.15 + 7.0, 10.0, 0.0, S, 2)
		var edge := (1.0 - v * v) * (u / 0.08 if u < 0.08 else 1.0) * pow(1.0 - u, 0.8)
		# denser and brighter down its heart near the mouth
		var d := Px.clamp(0.5 + n * 1.3 + (1.0 - absf(v)) * 0.35 * pow(1.0 - u, 1.5)) * edge
		if d < 0.08:
			return
		p.blendPx(sx, sy, C[7] if d > 0.72 else (C[6] if d > 0.52 else (C[5] if d > 0.32 else C[4])), minf(0.78, d * 0.95) * Px.clamp((d - 0.08) / 0.3))
		if d > 0.3:
			p.add(sx, sy, C[6] if d > 0.6 else C[5], 0.2 * d))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var S: float = o.seed
	var sp: float = o.spread
	gust(p, C, t, o)
	# the big slow billows behind
	Px.cycle(t, D, 12, S, func(g: Px.Rng) -> float: return g.range(1.0, 1.25), func(age: float, life: float, r: Px.Rng) -> void:
		var th := r.range(-sp, sp)
		var v: float = r.range(170.0, 230.0) * o.power
		var xy := Px.fly(3.0, r.range(-1.0, 1.0), v * cos(th), v * sin(th), age, SINK, 1.4)
		var k := age / life
		var rad := 2.0 + 12.0 * pow(k, 0.75)
		puff(p, C, xy[0], minf(xy[1], 40.0 - rad), rad, 0.75 * pow(1.0 - k, 1.2) * minf(1.0, age / 0.08), k, false))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var S: float = o.seed
	var sp: float = o.spread
	var ph := t / D
	# light down the cone
	p.glowLine(4.0, 0.0, 120.0, 6.0, 24.0, C[4], 0.26)
	p.glowLine(2.0, 0.0, 50.0, 1.0, 9.0, C[6], 0.3)
	p.glow(60.0, 4.0, 44.0, C[3], 0.16)
	# brighter puffs in front, smaller and quicker
	Px.cycle(t, D, 10, S + 1.0, func(g: Px.Rng) -> float: return g.range(0.7, 0.95), func(age: float, life: float, r: Px.Rng) -> void:
		var th := r.range(-sp * 0.8, sp * 0.8)
		var v: float = r.range(190.0, 260.0) * o.power
		var xy := Px.fly(3.0, r.range(-1.0, 1.0), v * cos(th), v * sin(th), age, SINK, 1.6)
		var k := age / life
		var rad := 1.5 + 8.0 * pow(k, 0.7)
		puff(p, C, xy[0], minf(xy[1], 40.0 - rad), rad, 0.85 * pow(1.0 - k, 1.3) * minf(1.0, age / 0.06), k, true))
	# snow carried along, swaying
	Px.cycle(t, D, 18, S + 2.0, func(g: Px.Rng) -> float: return g.range(0.8, 1.1), func(age: float, life: float, r: Px.Rng) -> void:
		var th := r.range(-sp * 1.1, sp * 1.1)
		var v := r.range(120.0, 190.0)
		var xy := Px.fly(4.0, 0.0, v * cos(th), v * sin(th), age, SINK * 1.4, 1.5)
		var k := age / life
		var sw := sin(age * 9.0 + r.range(0.0, TAU)) * 1.5
		if k < 0.85 or fmod(age * 30.0, 2.0) < 1.0:
			p.px(xy[0], xy[1] + sw, WHITE if r.chance(0.5) else C[6]))
	# wind streaks: a white head, a pale body, a cool tail
	Px.cycle(t, D, 26, S + 3.0, func(g: Px.Rng) -> float: return g.range(0.22, 0.36), func(age: float, life: float, r: Px.Rng) -> void:
		var th := r.range(-sp * 0.9, sp * 0.9)
		var v := r.range(280.0, 380.0)
		var xy := Px.fly(6.0, r.range(-2.0, 2.0), v * cos(th), v * sin(th), age, 0.0, 0.9)
		var x: float = xy[0]
		var y: float = xy[1]
		var vv := Px.flyV(v * cos(th), v * sin(th), age, 0.0, 0.9)
		var vx: float = vv[0]
		var vy: float = vv[1]
		var s := Px.hypot(vx, vy)
		var L := 4.0 + s * 0.03
		var ux := vx / s
		var uy := vy / s
		var k := age / life
		p.line(x - ux * L, y - uy * L, x, y, func(u: float) -> int: return WHITE if u > 0.8 else (C[6] if u > 0.4 else C[4]), func(u: float) -> float: return (1.0 if u > 0.35 else u / 0.35) * (1.0 if k < 0.75 else (1.0 - k) / 0.25))
		p.glow(x, y, 3.0, C[5], 0.3 * (1.0 - k)))
	# ice crystals tumbling through: a short shard with a white edge, glinting as it turns
	Px.cycle(t, D, 9, S + 4.0, func(g: Px.Rng) -> float: return g.range(0.65, 0.9), func(age: float, life: float, r: Px.Rng) -> void:
		var th := r.range(-sp, sp)
		var v := r.range(150.0, 230.0)
		var xy := Px.fly(5.0, 0.0, v * cos(th), v * sin(th), age, SINK, 1.1)
		var x: float = xy[0]
		var y: float = xy[1]
		var k := age / life
		var a := r.range(0.0, TAU) + age * r.range(9.0, 15.0) * r.sign()
		var L := r.range(1.5, 2.6)
		var ca := cos(a)
		var sa := sin(a)
		if k > 0.85 and fmod(age * 30.0, 2.0) < 1.0:
			return
		p.line(x - ca * L, y - sa * L, x + ca * L, y + sa * L, C[5])
		p.px(x + ca * L, y + sa * L, WHITE)
		var gl := cos(a * 2.0)
		if gl > 0.92:
			for d: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				p.px(x + d[0], y + d[1], C[6])
			p.px(x, y, WHITE)
			p.glow(x, y, 6.0, C[5], 0.5)
		else:
			p.glow(x, y, 3.0, C[5], 0.2))
	# the mouth: a white-hot core, a flickering jet of cold
	for i in 3:
		var L := 9.0 + 6.0 * Px.loopNoise(ph, 1.2, S + i * 7)
		var dy := (i - 1) * 1.4
		p.line(2.0, dy * 0.5, 2.0 + L, dy, func(u: float) -> int: return WHITE if u < 0.5 else C[6], func(u: float) -> float: return 1.0 if u < 0.6 else 1.0 - (u - 0.6) / 0.4)
	p.ellipse(2.5, 0.0, 4.6, 3.0, C[6])
	p.ellipse(2.0, 0.0, 3.0, 1.8, WHITE)
	var fl := 0.85 + 0.15 * sin(ph * TAU * 3.0)
	p.glow(2.0, 0.0, 24.0, C[5], 0.7 * fl)
	p.glow(2.0, 0.0, 9.0, WHITE, 0.5 * fl)
