# The lumpy cloud (puffs that drift off their push, rise, swell from small to large and thin out, lit caps,
# motes with light) is adapted from Sprite Fusion's open-source poison cloud (https://www.spritefusion.com/pixel-art-vfx/poison),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/nature/spore-burst.js@38e27a8cd8d09e0a5b7b12510d1300d51c4dfaea
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Spore burst",
	"desc": "A toadstool pushes up, swells and trembles as its gills glow, then squashes and puffs a lumpy cloud of glowing spores that billows up and drifts down twinkling.",
	"tags": ["nature", "mushroom", "spores", "poison", "cloud", "ground", "one-shot"],
	"size": [212, 132],
	"origin": [106, 118],
	"duration": 3.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#06141c", "#0c2a34", "#11484e", "#17706a", "#22a08a", "#4cd0a8", "#a8f4d0", "#f0fff6"],
		"cap": ["#1a0c1e", "#3a1438", "#62204e", "#8e3462", "#bc5276", "#e88a96"],
		"stem": ["#2a2230", "#5a4e5e", "#9a8e98", "#d8ccd0", "#f6eeee"],
		"seed": 9,
	},
}

const GROW := 0.32
const PUFF := 0.8
const SINK := 2.15
const SPOTS := [[-0.45, 0.45, 1.4], [0.1, 0.72, 1.8], [0.55, 0.38, 1.2], [-0.12, 0.25, 1.0], [0.3, 0.12, 0.9], [-0.7, 0.16, 0.8]]


# the toadstool at its current squash: a stem with a frilled ring, a domed cap lit from the upper left with
# pale spots, glowing gills beneath it
static func toadstool(p: Px.Painter, K: Array, Sm: Array, Cs: Array, g: float, sx: float, sy: float, glow: float, sink: float) -> void:
	var H := 17.0 * g
	var cw := 17.0 * sx * g
	var ch := 13.0 * sy * g
	var base := sink
	var top := base - H
	if g < 0.05:
		return
	# stem
	var y := floori(top)
	while y <= minf(0.0, base):
		for x in range(-4, 5):
			var w := 3.0 + ((y - top) / H) * 1.0
			if absf(x + 0.5) > w:
				continue
			var q := (x + 0.5 + w) / (2.0 * w)
			p.px(x, y, Sm[1] if absf(x + 0.5) > w - 0.8 else (Sm[4] if q < 0.4 else (Sm[3] if q < 0.7 else Sm[2])))
		y += 1
	var ring := top + H * 0.3
	if ring <= 0.0:
		for x in range(-5, 6):
			p.px(x, ring + (1.0 if absi(x) > 3 else 0.0), Sm[1] if absi(x) > 4 else Sm[3])
	# gills: a glowing underside
	var gy := top + 1.0
	if gy <= 0.0:
		for x in range(floori(-cw), ceili(cw) + 1):
			var d := absf(x + 0.5) / cw
			if d > 0.95:
				continue
			p.px(x, gy, Cs[0] if d < 0.3 else (Sm[2] if (x & 1) else Sm[3]))
			if glow > 0.05:
				p.px(x, gy, K[7] if (glow > 0.6 and (x & 1)) else K[5])
	if glow > 0.05:
		p.glow(0.0, gy + 2.0, cw * 1.5 + 6.0, K[5], 0.5 * glow)
	# the cap: a dome with a curled lip
	p.shade(-cw - 1.0, top - ch - 1.0, cw + 1.0, top + 1.0, func(x: float, yy: float, out):
		var dx := x / cw
		var dy := (top - yy) / ch
		var d := dx * dx + dy * dy
		if dy < -0.12 or d > 1.12 or yy > 0.0:
			return
		if d > 1.0:
			out.c = Cs[0]
			return
		var i := 5 if (dx < -0.35 and dy > 0.45) else (4 if (dx < 0.05 and dy > 0.3) else (2 if dy < 0.18 else (2 if dx > 0.55 else 3)))
		for spot: Array in SPOTS:
			var sx0: float = spot[0]
			var sy0: float = spot[1]
			var r: float = spot[2]
			var ex := (dx - sx0) * cw
			var ey := (dy - sy0) * ch
			if ex * ex + ey * ey * 1.6 < r * r * g * g:
				i = 9 if (ex < 0.0 and ey > 0.0) else 8
		out.c = Sm[4] if i == 9 else (Sm[3] if i == 8 else Cs[i]))
	p.px(-cw * 0.45, top - ch * 0.8, Cs[5])


var K: Array
var Cs: Array
var Sm: Array
var R: Px.Rng
var ps: Px.Particles
var gas: Lib.Gas
var lights: Px.Lights
var t := 0.0
var puffed := false
var grown := false


func create(o: Dictionary) -> void:
	K = Px.fit(o.palette, 8)
	Cs = Px.fit(o.cap, 6)
	Sm = Px.fit(o.stem, 5)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [K[7], K[6], K[5], K[4]], "haze": K[5]})
	gas = Lib.Gas.new()
	lights = Px.Lights.new()
	t = 0.0
	puffed = false
	grown = false


func g() -> float:
	return Px.Ease.outBack(Px.clamp(t / GROW), 1.6) * (1.0 - Px.Ease.inCubic(Px.clamp((t - SINK) / 0.45)))


func charge() -> float:
	return Px.smooth(GROW, PUFF, t)


# squash and stretch: it swells as it charges, squashes flat as it puffs, springs back
func shape() -> Array:
	if t < PUFF:
		var k := charge()
		var j := sin(t * 70.0) * 0.04 * k
		return [1.0 + 0.28 * k + j, 1.0 + 0.22 * k - j]
	var e := t - PUFF
	var sp := Px.exp(-e * 7.0) * cos(e * 26.0)
	return [1.0 + 0.25 * sp, 1.0 - 0.35 * sp]


func update(dt: float) -> void:
	t += dt
	var f := minf(1.0, dt * 120.0)
	if not grown:
		grown = true
		for i in 10:
			ps.spawn(P.GRIT, R.range(-4.0, 4.0), -1.0, R.range(-50.0, 50.0), -R.range(40.0, 120.0), R.range(0.5, 0.8), R.pick([Sm[1], Sm[2]]), 1.0)
		for i in 4:
			ps.spawn(P.DUST, R.range(-4.0, 4.0), -1.0, R.sign() * R.range(10.0, 40.0), -R.range(4.0, 12.0), R.range(0.4, 0.7), Sm[1], R.range(2.0, 3.0))
	# charging: spores gather toward the gills
	if t > GROW and t < PUFF - 0.05 and R.chance(0.25 * f):
		var a := R.range(PI * 1.05, PI * 1.95)
		var d := R.range(20.0, 38.0)
		var x := cos(a) * d
		var y := -18.0 + sin(a) * d * 0.7
		ps.spawn(P.STREAK, x, y, -x * 3.0, (-18.0 - y) * 3.0, R.range(0.2, 0.3), K[6])
	if not puffed and t >= PUFF:
		puffed = true
		lights.add(0.0, -22.0, 30.0, WHITE, 0.6, 0.1)
		lights.add(0.0, -28.0, 70.0, K[5], 0.55, 0.9)
		# the cloud: lumps shoved up and out from under the cap, swelling as they go
		for i in 30:
			var a := -PI / 2.0 + R.range(-1.1, 1.1)
			var sp := R.range(15.0, 95.0)
			gas.add(t, R.range(-8.0, 8.0), -20.0 + R.range(-3.0, 3.0), cos(a) * sp * 1.3, sin(a) * sp - 10.0, R.range(3.0, 5.0), R.range(8.0, 14.0), t + R.range(1.6, 2.2), R.range(5.0, 10.0))
		for i in 6:
			var sd := R.sign()
			gas.add(t, sd * R.range(6.0, 12.0), -5.0, sd * R.range(30.0, 70.0), -R.range(2.0, 14.0), R.range(2.0, 3.0), R.range(4.0, 6.0), t + R.range(0.8, 1.1), R.range(4.0, 8.0))
		for i in 40:
			var a := -PI / 2.0 + R.range(-1.4, 1.4)
			var sp := R.range(40.0, 160.0)
			var mote := R.chance(0.5)
			var k := 0.35 if mote else 0.7
			ps.spawn(P.MOTE if mote else P.FLAKE, R.range(-5.0, 5.0), -20.0, cos(a) * sp * k, sin(a) * sp * k, R.range(1.0, 2.0), R.pick([K[7], K[6], K[6], K[5]]), R.range(0.6, 1.6))
		for i in 6:
			ps.spawn(P.STAR, R.range(-20.0, 20.0), -R.range(12.0, 40.0), 0.0, -6.0, R.range(0.3, 0.6), K[7], R.range(1.0, 2.4), R.range(0.05, 0.4))
		for i in 8:
			ps.spawn(P.DUST, R.sign() * R.range(4.0, 10.0), -1.0, R.sign() * R.range(30.0, 90.0), -R.range(2.0, 10.0), R.range(0.5, 0.9), K[3], R.range(2.0, 3.5))
	# after it: spores keep drifting down out of the cloud, twinkling
	if puffed and t < 2.6 and R.chance(0.12 * f):
		ps.spawn(P.FLAKE, R.range(-40.0, 40.0), -R.range(30.0, 70.0), R.range(-8.0, 8.0), R.range(4.0, 14.0), minf(R.range(0.9, 1.5), meta.duration - 0.05 - t), K[7] if R.chance(0.5) else K[6], R.range(0.6, 1.5))
	if t > SINK and t < SINK + 0.4 and R.chance(0.15 * f):
		ps.spawn(P.DUST, R.range(-5.0, 5.0), -1.0, R.sign() * R.range(10.0, 30.0), -R.range(2.0, 8.0), R.range(0.3, 0.5), Sm[1], R.range(1.5, 2.5))
	gas.prune(t)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# a ring of glow on the floor round it while it charges and puffs
	var k := charge() * (1.0 - Px.smooth(PUFF + 0.2, PUFF + 1.2, t))
	if k > 0.0:
		for x in range(-20, 21):
			p.dot(x, 0.0, K[5] if absi(x) < 10 else K[4], k * (1.0 - absi(x) / 21.0))
	p.glow(0.0, -2.0, 30.0, K[4], 0.25 * k)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var sxy := shape()
	var sx: float = sxy[0]
	var sy: float = sxy[1]
	var gl := charge() * (0.75 + 0.25 * sin(t * (20.0 + 30.0 * charge()))) if t < PUFF else maxf(0.0, 1.0 - (t - PUFF) * 1.5)
	toadstool(p, K, Sm, Cs, g(), sx, sy, gl, Px.Ease.inCubic(Px.clamp((t - SINK) / 0.45)) * 20.0)
	# the cloud: teal lumps lit along their tops, a cool light through them
	gas.draw(p, t, K[2], K[4], K[6], K[7], 0.62, K[6])
	# the cloud glows from within: a soft light riding its middle
	if gas.list.size():
		var cx := 0.0
		var cy := 0.0
		var n := 0.0
		for q: Dictionary in gas.list:
			var g2 := gas.at(q, t)
			cx += g2.x * g2.a
			cy += g2.y * g2.a
			n += g2.a
		if n > 0.2:
			p.glow(cx / n, cy / n, 46.0, K[5], minf(0.32, 0.03 * n))
	var e := t - PUFF
	if e > 0.0 and e < 0.1:
		Px.sparkle(p, 0.0, -20.0, 10.0 * (1.0 - e / 0.1), K[7], K[6], 0.6)
	ps.draw(p, "front")
	lights.draw(p)
