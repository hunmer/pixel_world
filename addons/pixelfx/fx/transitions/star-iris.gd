# The twinkles (spinning glints at the tips, motes shed as it turns) follow Sprite Fusion's open-source sparkle
# (https://www.spritefusion.com/pixel-art-vfx/sparkle), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/star-iris.js@b46315a107bab00a2a2e37f2a202ed23251e81a2
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE
const W := Lib.W
const H := Lib.H

static var meta := Lib.screenMeta({
	"name": "Star iris",
	"desc": "A five-point star iris spins shut on the middle of the screen, its gold rim lit and its tips twinkling and shedding motes; it closes on a glint and spins open again from a flash.",
	"tags": ["iris", "star", "gold", "wipe"],
	"duration": 2.2,
	"options": {"palette": Px.PAL.gold, "focus": [160, 96], "seed": 1},
})

const CLOSE := 0.98
const OPEN0 := 1.16
const OPEN1 := 2.0
const RMAX := 430.0
const INNER := 0.46
const RW := 4.0


# the star at t: its outer radius and its turn
static func starAt(t: float) -> Dictionary:
	if t < CLOSE:
		return {"r": RMAX * (1.0 - Px.Ease.inOutQuad(t / CLOSE)) ** 1.3, "a": -PI / 2.0 + Px.Ease.inOutCubic(t / CLOSE) * 1.6 * TAU}
	if t < OPEN0:
		return {"r": 0.0, "a": 0.0}
	var u := Px.clamp((t - OPEN0) / (OPEN1 - OPEN0))
	return {"r": RMAX * Px.Ease.inOutCubic(u) ** 1.15, "a": -PI / 2.0 - Px.Ease.inOutCubic(u) * 1.6 * TAU}


static func points(fx: float, fy: float, r: float, a: float) -> Array:
	return Px.arr(10, func(i: int) -> Array:
		var rr := r * INNER if i % 2 else r
		var an := a + (i * PI) / 5.0
		return [fx + cos(an) * rr, fy + sin(an) * rr])


var C: Array
var ink: int
var R: Px.Rng
var fx: float
var fy: float
var ps: Px.Particles
var lights: Px.Lights
var t := 0.0
var shut := false
var opened := false
var prev: Dictionary
var end: float


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	ink = Px.hex(o.color)
	R = Px.Rng.new(o.seed)
	fx = float(o.focus[0])
	fy = float(o.focus[1])
	ps = Px.Particles.new({"rng": R, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	t = 0.0
	shut = false
	opened = false
	prev = starAt(0.0)
	end = meta.duration - 0.05


func update(dt: float) -> void:
	t += dt
	var s := starAt(t)
	var pts := points(fx, fy, s.r, s.a)
	var spin: float = (s.a - prev.a) / dt
	# the tips shed gold motes as the star turns, flung off along their path
	if s.r > 2.0:
		var i := 0
		while i < 10:
			var x: float = pts[i][0]
			var y: float = pts[i][1]
			if x < 0.0 or y < 0.0 or x >= W or y >= H or not R.chance(0.35):
				i += 2
				continue
			var an: float = s.a + (i * PI) / 5.0
			var v: float = spin * s.r * 0.25
			ps.spawn(P.STAR if R.chance(0.6) else P.MOTE, x, y, -sin(an) * v + cos(an) * 20.0, cos(an) * v + sin(an) * 20.0, minf(R.range(0.25, 0.55), end - t), C[6] if R.chance(0.5) else C[5], R.range(0.6, 1.8))
			i += 2
	if not shut and t >= CLOSE:
		shut = true
		lights.add(fx, fy, 60, C[5], 0.7, 0.3)
	if not opened and t >= OPEN0:
		opened = true
		lights.add(fx, fy, 120, C[5], 0.7, 0.4)
		lights.add(fx, fy, 40, WHITE, 0.8, 0.12)
		for i in 24:
			var a := R.range(0, TAU)
			var v := R.range(60, 200)
			ps.spawn(P.STAR, fx, fy, cos(a) * v, sin(a) * v, R.range(0.3, 0.6), WHITE if R.chance(0.5) else C[6], R.range(0.6, 2))
	prev = s
	ps.update(dt)
	lights.update(dt)


func draw(p0: Px.Painter) -> void:
	var p := Lib.clipTo(p0)
	var s := starAt(t)
	var sr: float = s.r
	if t >= CLOSE and t < OPEN0:
		Lib.rect(p0, 0.0, 0.0, W, H, ink)
	elif sr < RMAX - 2.0:
		var pts := points(fx, fy, sr, s.a)
		# the dark outside the star, row by row: the star's spans are where the outline crossings pair up
		for y in H:
			var yc := y + 0.5
			var xs := []
			var j := 9
			for i in 10:
				var xi: float = pts[i][0]
				var yi: float = pts[i][1]
				var xj: float = pts[j][0]
				var yj: float = pts[j][1]
				j = i
				if (yi > yc) != (yj > yc):
					xs.append(xi + ((yc - yi) * (xj - xi)) / (yj - yi))
			xs.sort()
			var x := 0.0
			var k := 0
			while k + 1 < xs.size():
				var a := Px.clamp(Px.round(xs[k]), 0.0, W)
				if a > x:
					Lib.rect(p0, x, y, a - x, 1.0, ink)
				x = maxf(x, Px.clamp(Px.round(xs[k + 1]), 0.0, W))
				k += 2
			if x < W:
				Lib.rect(p0, x, y, W - x, 1.0, ink)
		# the gold rim: along each edge, out into the dark, white where it faces the light
		var j := 9
		for i in 10:
			var ax: float = pts[j][0]
			var ay: float = pts[j][1]
			var bx: float = pts[i][0]
			var by: float = pts[i][1]
			j = i
			var L := Px.hypot(bx - ax, by - ay)
			if L < 0.5:
				continue
			var ux := (bx - ax) / L
			var uy := (by - ay) / L
			var nx := -uy  # outward for this winding
			var ny := ux
			var lit := nx * -0.6 + ny * -0.8 > 0.1
			var sx := 0.0
			while sx <= L:
				var x0 := ax + ux * sx
				var y0 := ay + uy * sx
				if x0 < -RW or y0 < -RW or x0 > W + RW or y0 > H + RW:
					sx += 0.5
					continue
				var d := 0.0
				while d < RW:
					var c: int = (WHITE if lit else C[6]) if d < 1.0 else (C[5] if d < 2.0 else (C[4] if d < 3.0 else C[3]))
					p.px(x0 + nx * d, y0 + ny * d, c)
					d += 0.5
				if fmod(sx, 2.0) == 0.0:
					p.light(x0, y0, C[5], 0.5)
				sx += 0.5
		# twinkles on the tips, and light pooling in the star as it closes
		var i := 0
		while i < 10:
			var x: float = pts[i][0]
			var y: float = pts[i][1]
			if not (x < 2.0 or y < 2.0 or x > W - 2.0 or y > H - 2.0):
				Lib.glint(p, x, y, 5.0 + 3.0 * sin(t * 13.0 + i), t * 2.0 + i, C[6], C[5])
			i += 2
		if sr < 140.0:
			p.glow(fx, fy, sr * 0.7 + 8.0, C[5], 0.35 * (1.0 - sr / 140.0))
	# shutting: a glint where it closed; opening: a flash
	var u := t - CLOSE
	if u > -0.05 and u < 0.2:
		Lib.glint(p, fx, fy, 14.0 * (1.0 - absf(u) / 0.2), u * 4.0, C[6], C[5])
	var v := t - OPEN0
	if v >= 0.0 and v < 0.16:
		Lib.glint(p, fx, fy, 18.0 * (1.0 - v / 0.16), 0.3 - v * 5.0, C[6], C[5])
		p.glow(fx, fy, 50.0, WHITE, 0.5 * (1.0 - v / 0.16))
	ps.draw(p)
	lights.draw(p)
