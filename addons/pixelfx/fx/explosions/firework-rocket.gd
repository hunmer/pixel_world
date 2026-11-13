# The flare, the twinkling glitter and the crackle are adapted from Sprite Fusion's open-source sparkle
# (https://www.spritefusion.com/pixel-art-vfx/sparkle), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/firework-rocket.js@6e11a9b0ea200b9e36d80d5e2889f9138cc5f3ec
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Firework rocket",
	"desc": "A rocket fizzes off the ground on a sparkling gold trail, coasts, and bursts into a palm: heavy gold fronds arc out, droop on glittering trails and crackle at the tips.",
	"tags": ["firework", "rocket", "celebration", "sparkle", "sky", "one-shot"],
	"size": [300, 300],
	"origin": [150, 288],
	"duration": 3.8,
	"loop": false,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#2a1406", "#6a3a0c", "#b8701a", "#f0a830", "#ffd860", "#fff2b0", "#ffffff"],
		"tips": ["#0c2a3a", "#1a5a78", "#36a2c8", "#7cd8f0", "#c8f4ff", "#ffffff"],
		"seed": 12,
	},
}

const FLY := 1.05
const HIGH := 192.0
const DRAG := 1.35
const G := 105.0
const TRAIL := 1.15


var C: Array
var T: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var fronds := []
var pops := []
var t := 0.0
var burst := false
var bx := 0.0
var by := 0.0
var acc := 0.0


func at(tt: float) -> Array:
	return [sin(tt * 8.0) * 1.6 * (tt / FLY), -8.0 - HIGH * Px.Ease.outQuad(Px.clamp(tt / FLY))]


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	T = Px.fit(o.tips, 6)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [C[6], C[5], C[4], C[3]]})
	lights = Px.Lights.new()
	lights.add(0.0, -14.0, 24.0, C[4], 0.7, 0.35)
	# ignition: a puff of smoke and a spray of sparks off the ground
	for i in 18:
		var a := -PI / 2.0 + R.range(-1.2, 1.2)
		var sp := R.range(60.0, 180.0)
		ps.spawn(P.SPARK, 0.0, -2.0, cos(a) * sp, sin(a) * sp * 0.6, R.range(0.15, 0.4))
	for i in 5:
		ps.spawn(P.VAPOUR, R.range(-3.0, 3.0), -2.0, R.range(-20.0, 20.0), -R.range(2.0, 10.0), R.range(0.6, 1.0), Px.hex("#5a5468"), R.range(3.0, 5.0))


func update(dt: float) -> void:
	t += dt
	if t < FLY:
		# the climb: a hot tail spitting gold sparks, glitter left hanging, a thread of smoke
		var xy := at(t)
		var xy2 := at(maxf(0.0, t - 0.02))
		var x: float = xy[0]
		var y: float = xy[1]
		var vy: float = (y - xy2[1]) / 0.02
		var vx: float = (x - xy2[0]) / 0.02
		acc += dt * 90.0
		while acc > 1.0:
			var a := PI / 2.0 + R.range(-0.45, 0.45)
			var sp := R.range(30.0, 110.0)
			ps.spawn(P.SPARK, x, y + 4.0, cos(a) * sp + vx * 0.2, sin(a) * sp + vy * 0.15, R.range(0.15, 0.4))
			if R.chance(0.25):
				ps.spawn(P.STAR, x + R.range(-1.5, 1.5), y + R.range(2.0, 6.0), R.range(-6.0, 6.0), R.range(5.0, 20.0), R.range(0.4, 0.9), C[5] if R.chance(0.5) else WHITE, 1.2 if R.chance(0.15) else 0.5)
			if R.chance(0.18):
				ps.spawn(P.VAPOUR, x, y + 5.0, R.range(-4.0, 4.0), R.range(4.0, 12.0), R.range(0.6, 1.1), Px.hex("#4a4458"), R.range(1.2, 2.2))
			acc -= 1.0
	elif not burst:
		burst = true
		var bxy := at(FLY)
		bx = bxy[0]
		by = bxy[1]
		lights.add(bx, by, 82.0, C[4], 0.8, 1.6)
		lights.add(bx, by, 40.0, WHITE, 0.6, 0.08)
		# the palm: heavy comets thrown up and out, a few low ones to the sides
		for i in 9:
			var a := -PI / 2.0 + ((i - 4) / 4.0) * 1.4 + R.range(-0.1, 0.1)
			var sp := R.range(180.0, 210.0) * (1.0 - 0.12 * absi(i - 4) / 4.0)
			fronds.append({"x": bx, "y": by, "vx": cos(a) * sp, "vy": sin(a) * sp, "age": 0.0, "life": R.range(1.8, 2.15), "pts": [], "acc": R.next(), "seed": R.range(0.0, 100.0)})
		for i in 6:
			ps.spawn(P.VAPOUR, bx + R.range(-4.0, 4.0), by + R.range(-4.0, 4.0), R.range(-20.0, 20.0), R.range(-15.0, 15.0), R.range(1.8, 2.6), Px.hex("#4a4458"), R.range(6.0, 10.0))
		for i in 30:
			var a := R.range(0.0, TAU)
			var sp := R.range(40.0, 160.0)
			ps.spawn(P.SPARK, bx, by, cos(a) * sp, sin(a) * sp, R.range(0.15, 0.35))
	var i := fronds.size() - 1
	while i >= 0:
		var f: Dictionary = fronds[i]
		i -= 1
		f.age += dt
		var k: float = f.age / f.life
		if k >= 1.0:
			for j in 4:
				pops.append({"x": f.x + R.range(-5.0, 5.0), "y": f.y + R.range(-5.0, 5.0), "t0": t + R.range(0.0, 0.2), "life": R.range(0.06, 0.12), "c": WHITE if R.chance(0.5) else T[3]})
			fronds.remove_at(i + 1)
			continue
		f.vx -= f.vx * DRAG * dt
		f.vy -= f.vy * DRAG * dt - G * dt
		f.x += f.vx * dt
		f.y += f.vy * dt
		f.pts.append(f.x)
		f.pts.append(f.y)
		f.pts.append(t)
		while f.pts.size() > 3 and t - f.pts[2] > TRAIL:
			f.pts.pop_front()
			f.pts.pop_front()
			f.pts.pop_front()
		# glitter shed all along: specks that hang, twinkle and drift down
		f.acc += dt * 34.0
		while f.acc > 1.0:
			ps.spawn(P.STAR, f.x + R.range(-1.0, 1.0), f.y + R.range(-1.0, 1.0), f.vx * 0.1 + R.range(-5.0, 5.0), R.range(0.0, 14.0), R.range(0.5, 1.1), C[5] if R.chance(0.6) else WHITE, R.range(1.0, 1.5) if R.chance(0.12) else 0.5)
			f.acc -= 1.0
	var j := pops.size() - 1
	while j >= 0:
		if t > pops[j].t0 + pops[j].life:
			pops.remove_at(j)
		j -= 1
	ps.update(dt)
	Lib.cull(ps, -meta.origin[0] + 2, -meta.origin[1] + 2, meta.size[0] - meta.origin[0] - 2, meta.size[1] - meta.origin[1] - 2)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	if t < FLY:
		# the rocket: a little tube on a stick, a white-hot tail flickering under it
		var xy := at(t)
		var x: float = xy[0]
		var y: float = xy[1]
		p.line(x, y + 4.0, x, y + 12.0, Px.hex("#5a4030"))
		p.rect(x - 1.0, y - 3.0, 3.0, 7.0, Px.hex("#b8303a"))
		p.px(x - 1.0, y - 3.0, Px.hex("#e86070"))
		p.px(x, y - 4.0, Px.hex("#d8d0c0"))
		var fl := 2.0 + (1.0 if sin(t * 70.0) > 0.0 else 0.0)
		p.line(x, y + 4.0, x, y + 4.0 + fl, func(u: float): return WHITE if u < 0.4 else C[5])
		p.glow(x, y + 5.0, 9.0, C[4], 0.6)
	for f in fronds:
		var k: float = f.age / f.life
		var P2: Array = f.pts
		var n := floori(P2.size() / 3.0)
		# the frond: a thick gold trail, hot near the head, cooling and dithering out behind
		var j := n - 1
		while j > 0:
			var u: float = (t - P2[j * 3 + 2]) / TRAIL
			if u >= 1.0:
				break
			var c: int = C[6] if u < 0.08 else (C[5] if u < 0.25 else (C[4] if u < 0.5 else (C[3] if u < 0.75 else C[2])))
			var a := pow(1.0 - u, 0.6) * (1.25 - k * 0.45)
			p.line(P2[j * 3], P2[j * 3 + 1], P2[j * 3 - 3], P2[j * 3 - 2], c, a)
			if u < 0.7:
				p.line(P2[j * 3] + 1.0, P2[j * 3 + 1], P2[j * 3 - 3] + 1.0, P2[j * 3 - 2], C[5] if u < 0.25 else (C[3] if u < 0.5 else C[2]), a * 0.85)
			if u < 0.35:
				p.line(P2[j * 3], P2[j * 3 + 1] + 1.0, P2[j * 3 - 3], P2[j * 3 - 2] + 1.0, C[3], a * 0.6)
			j -= 1
		if k > 0.8 and sin(t * 55.0 + f.seed) < 0.0:
			continue
		p.rect(f.x - 0.5, f.y - 0.5, 2.0, 2.0, WHITE if k < 0.5 else C[6])
		if k < 0.6:
			for dd in [[-1, 0], [2, 0], [0, -1], [0, 2]]:
				p.px(f.x + dd[0], f.y + dd[1], C[5])
		p.glow(f.x, f.y, 10.0, C[4], 0.6 * (1.0 - k * 0.5))
	for q in pops:
		var u: float = (t - q.t0) / q.life
		if u < 0.0 or u > 1.0:
			continue
		Px.sparkle(p, q.x, q.y, 2.8 * sin(PI * u), q.c, T[2], 0.5)
	# the burst: a white heart for two frames, a flare turning
	var b := t - FLY
	if b >= 0.0 and b < 0.26:
		var u := b / 0.26
		var L := 30.0 * pow(1.0 - u, 1.3)
		for i in 8:
			var diag := i % 2 == 1
			var an := u * 0.5 + (i * TAU) / 8.0
			var len := L * 0.45 if diag else L
			var ca := cos(an)
			var sa := sin(an)
			var d := 0.0
			while d <= len:
				var v := d / len
				p.dot(bx + ca * d, by + sa * d, WHITE if v < 0.3 else (C[5] if v < 0.65 else C[4]), 1.0 if v < 0.7 else 1.0 - (v - 0.7) / 0.35)
				d += 0.5
		if b < 0.07:
			p.circle(bx, by, 2.5, WHITE)
		p.glow(bx, by, 4.0 + L * 1.2, C[4], 0.35)
	ps.draw(p, "front")
	lights.draw(p)
