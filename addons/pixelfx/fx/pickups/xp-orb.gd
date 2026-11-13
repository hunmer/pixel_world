# The orb's shading and its glow follow Sprite Fusion's open-source pickup orb
# (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/xp-orb.js@f7bfafc47760962b0d603d1cce0f0d69dcc751e6
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "XP orb",
	"desc": "A small glowing orb races a figure-eight, a comet tail tapering behind it along its path, flecks shed from the tail winking out, its light following it over the floor.",
	"tags": ["pickup", "xp", "orb", "experience", "energy", "loop"],
	"size": [72, 56],
	"origin": [36, 48],
	"duration": 1.8,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#0c1806", "#1e3a0a", "#36620e", "#5c9614", "#8cd024", "#c4f060", "#effcc0", "#ffffff"], "seed": 2},
}

const A := 16.0
const B := 9.0
const HOVER := 20.0
const TAIL := 0.48
static var INK := Px.hex("#0a1406")


# the figure-eight, as a function of time (one lap a loop), with a little lift and fall
static func at(t: float) -> Array:
	var D: float = meta.duration
	var a := (t / D) * TAU
	return [A * sin(a), -HOVER + B * sin(a) * cos(a) - 1.2 * cos(a * 2.0)]


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var xy := at(t)
	var x: float = xy[0]
	# its shadow and its light slide over the floor beneath it
	Lib.blobShadow(p, x, 3.5, 0.55)
	Lib.pool(p, x, 0.5, 14.0, 3.0, C[5], 0.3)
	# flecks shed from the tail drift down and wink out
	Px.cycle(t, meta.duration, 16, o.seed, func(g: Px.Rng) -> float: return g.range(0.35, 0.7), func(age: float, life: float, r: Px.Rng) -> void:
		var fxy := at(t - age)
		var fx: float = fxy[0]
		var fy: float = fxy[1]
		var k := 1.0 - age / life
		var tw := sin(age * r.range(20.0, 30.0) + r.range(0.0, TAU))
		var x2 := fx + r.range(-2.0, 2.0) + age * r.range(-6.0, 6.0)
		var y2 := fy + r.range(-2.0, 2.0) + age * r.range(4.0, 10.0)
		if tw * k > -0.2:
			p.px(x2, y2, WHITE if (tw > 0.6 and k > 0.5) else (C[6] if k > 0.5 else C[5]))
		p.glow(x2 + 0.5, y2 + 0.5, 3.0, C[5], 0.3 * k))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var xy := at(t)
	var x: float = xy[0]
	var y: float = xy[1]
	var D: float = meta.duration
	var beat := 0.5 + 0.5 * sin((t / D) * TAU * 3.0)
	# the tail: the orb's own path just behind it, tapering and cooling down the ramp
	var n := 60
	# an outer ribbon cooling down the ramp, then a bright core line down its middle
	var i := n
	while i >= 1:
		var u := float(i) / n
		var txy := at(t - u * TAIL)
		var tx: float = txy[0]
		var ty: float = txy[1]
		var r := 3.1 * pow(1.0 - u, 1.1)
		var c: int = C[5] if u < 0.25 else (C[4] if u < 0.55 else C[3])
		if r > 0.6:
			p.circle(tx, ty, r, c, 1.0 if u < 0.7 else (1.0 - u) * 3.3)
		else:
			p.dot(tx, ty, c, (1.0 - u) * 3.0)
		if i % 6 == 0:
			p.glow(tx, ty, 7.0 * (1.0 - u) + 2.0, C[5], 0.24 * (1.0 - u))
		i -= 1
	i = floori(n * 0.6)
	while i >= 1:
		var u := float(i) / n
		var txy := at(t - u * TAIL)
		p.dot(txy[0], txy[1], WHITE if u < 0.2 else C[6], (0.6 - u) * 4.0)
		i -= 1
	# the orb: a dark rim, a bright body, a white heart and a highlight, pulsing with light
	var X := Px.round(x)
	var Y := Px.round(y)
	p.circle(X, Y, 4.4, INK)
	p.circle(X, Y, 3.6, func(d: float, a: float) -> int: return (C[5] if cos(a + 2.4) > 0.3 else C[3]) if d > 0.72 else ((C[6] if cos(a + 2.4) > -0.2 else C[5]) if d > 0.4 else WHITE))
	p.px(X - 2.0, Y - 2.0, WHITE)
	p.px(X - 1.0, Y - 2.0, C[7])
	p.glow(x, y, 16.0 + 3.0 * beat, C[5], 0.36 + 0.14 * beat)
	# a glint now and then
	var g := fmod((t / D) * 3.0, 1.0)
	if g < 0.12:
		Lib.glint(p, X - 2.0, Y - 2.0, 2.4 * sin((g / 0.12) * PI), WHITE, 0.4)
