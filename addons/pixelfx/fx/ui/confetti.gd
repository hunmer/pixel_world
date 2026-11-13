# The flutter (a swing that slows at its ends, a tilt that follows it, a paper flip that shows the back) adapts
# Sprite Fusion's open-source falling leaves (https://www.spritefusion.com/pixel-art-vfx/falling-leaves),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ui/confetti.js@735fd4e6ee4ab5ef68812cad339c59cfbc4332cb
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Confetti",
	"desc": "Two party poppers bang one after the other: paper bits and curly streamers burst out, stall, then tumble and flutter down, flipping, and settle on the floor.",
	"tags": ["ui", "celebration", "confetti", "party", "reward", "one-shot"],
	"size": [200, 140],
	"origin": [100, 126],
	"duration": 3.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#ff4a5a", "#ff9a2a", "#ffe03c", "#5ad84a", "#3cc8ff", "#7a6cff", "#f53cd1"], "seed": 11},
}

static var POPPERS := [
	{"x": -74.0, "y": -1.0, "a": -PI / 2.0 + 0.62, "t": 0.1},
	{"x": 74.0, "y": -1.0, "a": -PI / 2.0 - 0.62, "t": 0.26},
]
static var INK := Px.hex("#141019")
static var KC8C0D8 := Px.hex("#c8c0d8")
static var K5D5660 := Px.hex("#5d5660")


# a party popper: a striped cone pointing along a, kicked back k px when it fires
static func popper(p: Px.Painter, x: float, y: float, a: float, k: float, C: Array, alpha: float) -> void:
	var ca := cos(a)
	var sa := sin(a)
	var bx := x - ca * k
	var by := y - sa * k
	p.shade(bx - 12.0, by - 12.0, bx + 12.0, by + 12.0, func(px: float, py: float, o):
		var dx := px - bx
		var dy := py - by
		var u := dx * ca + dy * sa
		var v := -dx * sa + dy * ca
		# u along the cone (0 at its tip on the floor, 11 at its mouth), v across
		if u < 0.0 or u > 11.0:
			return null
		var hw := 0.8 + u * 0.32
		if absf(v) > hw + 0.6:
			return null
		o.a = alpha
		if absf(v) > hw - 0.4 or u > 10.2 or u < 0.8:
			return INK
		var stripe := floori((u + v * 0.6) / 2.2) % 2 == 0
		return (C[2] if v < 0.0 else Px.scale(C[2], 0.75)) if stripe else (WHITE if v < 0.0 else KC8C0D8))


var C: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var bits := []
var ribbons := []
var fired := [false, false]
var end: float
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": ["#ffffff", "#fff3a6", "#ffc23d", "#ff8a2a"]})
	lights = Px.Lights.new()
	end = meta.duration - 0.05


static func kick(tt: float, pp: Dictionary) -> float:
	return 0.0 if tt < pp.t else 3.0 * exp(-(tt - pp.t) * 14.0)


func fire(pp: Dictionary) -> void:
	var mx: float = pp.x + cos(pp.a) * 11.0
	var my: float = pp.y + sin(pp.a) * 11.0
	lights.add(mx, my, 34.0, WHITE, 0.6, 0.12)
	lights.add(mx, my, 50.0, C[2], 0.4, 0.4)
	for i in 6:
		ps.spawn(P.SMOKE, mx, my, cos(pp.a) * R.range(20.0, 60.0) + R.range(-10.0, 10.0), sin(pp.a) * R.range(20.0, 60.0), R.range(0.6, 1.0), K5D5660, R.range(2.5, 4.0))
	for i in 12:
		var an: float = pp.a + R.range(-0.5, 0.5)
		var sp := R.range(120.0, 260.0)
		ps.spawn(P.SPARK, mx, my, cos(an) * sp, sin(an) * sp, R.range(0.1, 0.25))
	# paper: thrown hard up the cone, the air soon stalls it
	for i in 46:
		var an: float = pp.a + R.range(-0.38, 0.38)
		var sp := R.range(200.0, 380.0)
		bits.append({"x": mx, "y": my, "vx": cos(an) * sp, "vy": sin(an) * sp, "c": R.pick(C), "w": R.range(2.0, 3.0), "h": R.range(3.0, 4.6), "ang": R.range(0.0, TAU), "spin": R.range(-14.0, 14.0), "flip": R.range(0.0, TAU), "fs": R.range(5.0, 13.0), "ph": R.range(0.0, TAU), "amp": R.range(5.0, 12.0), "fw": R.range(2.0, 3.4), "x0": 0.0, "mode": 0, "rest": 0.0, "fall": R.range(26.0, 40.0)})
	# streamers: a head that flies like the paper, a tail that follows it and curls
	for i in 4:
		var an: float = pp.a + R.range(-0.25, 0.25)
		var sp := R.range(220.0, 330.0)
		var n := 11
		ribbons.append({"pts": Px.arr(n, func(_i): return [mx, my]), "vx": cos(an) * sp, "vy": sin(an) * sp, "c": R.pick(C), "ph": R.range(0.0, TAU), "amp": R.range(6.0, 12.0), "fw": R.range(1.5, 2.4), "mode": 0, "x0": 0.0, "curl": R.range(0.7, 1.1), "fall": R.range(22.0, 32.0)})


func update(dt: float) -> void:
	t += dt
	for i in POPPERS.size():
		var pp: Dictionary = POPPERS[i]
		if not fired[i] and t >= pp.t:
			fired[i] = true
			fire(pp)
	for b: Dictionary in bits:
		if b.mode == 2:
			b.rest += dt
			continue
		b.flip += b.fs * dt
		if b.mode == 0:
			# the burst: heavy drag, a little gravity, tumbling fast; once slow it starts to flutter
			b.vx -= b.vx * 3.4 * dt
			b.vy -= b.vy * 3.4 * dt - 140.0 * dt
			b.x += b.vx * dt
			b.y += b.vy * dt
			b.ang += b.spin * dt
			if Px.hypot(b.vx, b.vy) < 40.0:
				b.mode = 1
				b.x0 = b.x - sin(b.ph) * b.amp
		else:
			b.ph += b.fw * dt
			b.x0 += b.vx * dt
			b.vx -= b.vx * 2.0 * dt
			b.x = b.x0 + sin(b.ph) * b.amp
			b.y += b.fall * (0.4 + 0.9 * absf(cos(b.ph))) * dt
			b.ang = cos(b.ph) * 0.9
			if b.y >= -1.0:
				b.y = -0.5
				b.mode = 2
				b.ang = R.range(-0.3, 0.3)
				b.flip = 0.0
	for r: Dictionary in ribbons:
		var pts: Array = r.pts
		var h: Array = pts[0]
		if r.mode == 0:
			r.vx -= r.vx * 3.0 * dt
			r.vy -= r.vy * 3.0 * dt - 120.0 * dt
			h[0] += r.vx * dt
			h[1] += r.vy * dt
			if Px.hypot(r.vx, r.vy) < 35.0:
				r.mode = 1
				r.x0 = h[0] - sin(r.ph) * r.amp
		elif h[1] < -1.0:
			r.ph += r.fw * dt
			r.x0 += r.vx * dt
			r.vx -= r.vx * 2.0 * dt
			h[0] = r.x0 + sin(r.ph) * r.amp
			h[1] += r.fall * (0.5 + 0.7 * absf(cos(r.ph))) * dt
		# the tail follows the head link by link and hangs a little
		for i in range(1, pts.size()):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			b[1] = minf(-0.5, b[1] + 20.0 * dt)
			var dx: float = b[0] - a[0]
			var dy: float = b[1] - a[1]
			var d := Px.hypot(dx, dy)
			if not d:
				d = 1.0
			if d > 2.6:
				b[0] = a[0] + (dx / d) * 2.6
				b[1] = a[1] + (dy / d) * 2.6
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var fade := 1.0 - Px.seg(t, end - 0.45, end - 0.05)
	for pp: Dictionary in POPPERS:
		var k := kick(t, pp)
		popper(p, pp.x, pp.y, pp.a, k, C, 1.0 - Px.seg(t, 2.5, 2.9))
		var ft: float = t - pp.t
		if ft > 0.0 and ft < 0.12:
			Px.sparkle(p, pp.x + cos(pp.a) * 13.0, pp.y + sin(pp.a) * 13.0, 7.0 * (1.0 - ft / 0.12), WHITE, C[2], 0.7)
	# streamers: a two-tone ribbon that curls along its length
	for r: Dictionary in ribbons:
		var rp: Array = r.pts
		var pts := []
		for i in rp.size():
			pts.append([rp[i][0] + sin(i * r.curl + t * 9.0 + r.ph) * (1.6 if i else 0.0), rp[i][1]])
		for i in range(1, pts.size()):
			var x0: float = pts[i - 1][0]
			var y0: float = pts[i - 1][1]
			var x1: float = pts[i][0]
			var y1: float = pts[i][1]
			var front: bool = sin(i * r.curl + t * 9.0 + r.ph) > 0.0
			p.line(x0, y0, x1, y1, r.c if front else Px.scale(r.c, 0.6), fade)
			p.line(x0 + 1.0, y0, x1 + 1.0, y1, Px.mix(r.c, WHITE, 0.35) if front else Px.scale(r.c, 0.45), fade)
	# paper bits: a little card turned by its tilt, its width by its flip; the back side shows darker
	for b: Dictionary in bits:
		if b.y > 1.0:
			continue
		var fw: float = 1.0 if b.mode == 2 else cos(b.flip)
		var w: float = maxf(0.5, absf(fw) * b.w)
		var ca := cos(b.ang)
		var sa := sin(b.ang)
		var c: int = b.c if fw >= 0.0 else Px.scale(b.c, 0.62)
		var a := fade
		if b.mode == 2:
			p.dot(b.x, b.y, Px.scale(b.c, 0.8), a)
			p.dot(b.x + 1.0, b.y, Px.scale(b.c, 0.6), a)
			continue
		var bx: float = b.x
		var by: float = b.y
		var bh: float = b.h
		p.shade(bx - 4.0, by - 4.0, bx + 4.0, by + 4.0, func(x: float, y: float, out):
			var dx := x - bx
			var dy := y - by
			var u := dx * ca + dy * sa
			var v := -dx * sa + dy * ca
			if absf(u) > w / 2.0 + 0.2 or absf(v) > bh / 2.0:
				return null
			out.a = a
			return WHITE if (absf(fw) > 0.92 and v < -bh / 2.0 + 1.0) else c)
		# it catches the light as it turns face-on
		if absf(fw) > 0.97:
			p.glow(b.x, b.y, 5.0, Px.mix(b.c, WHITE, 0.5), 0.35 * fade)
	ps.draw(p, "front")
	lights.draw(p)
