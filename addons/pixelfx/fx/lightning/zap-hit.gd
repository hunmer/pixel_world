# The arc's halo-body-core inking, its flicker and the light that strobes as it dies follow Sprite Fusion's
# open-source lightning (https://www.spritefusion.com/pixel-art-vfx/lightning), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/zap-hit.js@cf5a8d0dcc8f77e70291697c63068c2a6e35cdde
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Zap hit",
	"desc": "A contact zap: an arc snaps in from the left, the hit point overloads into a knot of tiny crackling zigzags, a fern of burn marks glows outward, sparks jink away, ozone puffs.",
	"tags": ["lightning", "electric", "hit", "impact", "combat", "directional", "one-shot"],
	"size": [144, 112],
	"origin": [76, 56],
	"duration": 0.9,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": Lib.VOLT, "seed": 3},
}

const SNAP := 0.05
static var ASH := Px.hex("#6a6680")


# the burn the current leaves on what it hit: a Lichtenberg fern, main fronds radiating, side fronds alternating
static func fern(R: Px.Rng) -> Array:
	var out := []
	for i in 6:
		grow(R, out, 0.0, 0.0, (i / 6.0) * TAU + R.range(-0.35, 0.35), R.range(18.0, 32.0), 1.0, 0.0, 0)
	return out


static func grow(R: Px.Rng, out: Array, x: float, y: float, a: float, ln: float, w: float, d: float, depth: int) -> void:
	var pts := [[x, y, d]]
	var side := R.sign()
	var s := 0.0
	while s < ln:
		a += R.range(-0.3, 0.3)
		x += cos(a) * 1.4
		y += sin(a) * 1.4
		d += 1.4
		pts.append([x, y, d])
		if depth < 2 and s > 2.0 and R.chance(0.24):
			side = -side
			grow(R, out, x, y, a + side * R.range(0.55, 1.05), (ln - s) * R.range(0.3, 0.55), w * 0.6, d, depth + 1)
		s += 1.4
	out.append({"pts": pts, "w": w})


var o: Dictionary
var C: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var tree: Array
var Y0: float
var kinked: Array
var t := 0.0
var hit := false


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R})
	lights = Px.Lights.new()
	tree = fern(R)
	Y0 = R.range(-14.0, 6.0)
	# sparks that jink: they fly out and jerk to a new heading every few hundredths of a second
	kinked = Px.arr(16, func(_i):
		var a := R.range(-1.2, 1.2) + (0.0 if R.chance(0.7) else PI)
		var sp := R.range(130.0, 250.0)
		return {"x": 0.0, "y": 0.0, "vx": cos(a) * sp, "vy": sin(a) * sp - 40.0, "life": R.range(0.2, 0.36), "age": -SNAP, "next": R.range(0.02, 0.05), "trail": []})


func update(dt: float) -> void:
	t += dt
	if not hit and t >= SNAP:
		hit = true
		lights.add(0.0, 0.0, 60.0, C[4], 0.7, 0.3)
		lights.add(0.0, 0.0, 14.0, WHITE, 0.5, 0.07)
		for i in 3:
			ps.spawn(P.SMOKE, R.range(-3.0, 5.0), R.range(-4.0, 2.0), R.range(-5.0, 8.0), -R.range(8.0, 16.0), R.range(0.55, 0.75), Px.mix(ASH, C[4], 0.3), R.range(2.5, 3.8), R.range(0.08, 0.16))
	for s: Dictionary in kinked:
		s.age += dt
		if s.age < 0.0 or s.age >= s.life:
			continue
		s.next -= dt
		if s.next <= 0.0:
			s.next = R.range(0.025, 0.055)
			var sp := Px.hypot(s.vx, s.vy)
			var a: float = atan2(s.vy, s.vx) + R.sign() * R.range(0.6, 1.3)
			s.vx = cos(a) * sp
			s.vy = sin(a) * sp
			s.trail.append([s.x, s.y])
			if s.trail.size() > 4:
				s.trail.pop_front()
		s.vx -= s.vx * 3.0 * dt
		s.vy -= s.vy * 3.0 * dt - 140.0 * dt
		s.x += s.vx * dt
		s.y += s.vy * dt
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the fern burns outward from the hit, glowing white, cooling through the palette, then fading
	if t < SNAP:
		return
	# it cools by stepping down the palette, and only the last embers dither away
	var cool := Px.smooth(0.45, 0.85, t)
	var fade := 1.0 - Px.smooth(0.78, 0.88, t)
	for br: Dictionary in tree:
		var pts: Array = br.pts
		for i in range(1, pts.size()):
			var x0: float = pts[i - 1][0]
			var y0: float = pts[i - 1][1]
			var x: float = pts[i][0]
			var y: float = pts[i][1]
			var d: float = pts[i][2]
			var age := t - SNAP - d / 260.0
			if age < 0.0:
				break
			var k := exp(-age / 0.22) - cool * 0.3
			var c: int = WHITE if k > 0.75 else (C[6] if k > 0.45 else (C[5] if k > 0.25 else (C[4] if k > 0.1 else (C[2] if k > -0.05 else C[1]))))
			p.line(x0, y0, x, y, c, fade)
			if br.w >= 1.0 and d < 9.0:
				p.line(x0 + 1.0, y0, x + 1.0, y, C[5] if k > 0.45 else C[2], fade)
			if (i & 3) == 0 and k > 0.0:
				p.glow(x, y, 5.0, C[5], 0.35 * k * fade)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var f := floori(t * 30.0 + 1e-4)
	# the arc snaps in from the left in two frames, holds and flickers, then lets go
	if t < 0.32:
		var r := Px.rng(o.seed, 2, f)
		var b := Lib.zigzag(r, -66.0, Y0, 0.0, 0.0, 0.22, 0.35)
		var u := Px.clamp(t / SNAP)
		var k := 1.0 if t < SNAP else ((0.7 if f % 2 else 1.0) if t < 0.2 else 0.55 * (1.0 - (t - 0.2) / 0.12))
		Lib.stroke(p, {"paths": [b.paths[0]]} if u < 1.0 else b, k, C, 0.95 if t < SNAP + 0.034 else 0.7, {"upTo": u, "hero": t >= SNAP and t < SNAP + 0.034})
		if u < 1.0:
			var tp: Array = b.paths[0].pts
			var hx: float = tp[floori(u * (tp.size() - 1))][0]
			var hy: float = tp[floori(u * (tp.size() - 1))][1]
			p.circle(hx, hy, 2.0, WHITE)
			p.glow(hx, hy, 14.0, C[5], 0.6)
	# the hit point overloads: a tight knot of tiny zigzags re-struck every frame round a white heart
	if t >= SNAP and t < 0.45:
		var a := (t - SNAP) / 0.4
		var r := Px.rng(o.seed, 5, f)
		var R0 := 8.0 * (1.0 - a * 0.6)
		var m := Px.roundi(11.0 * (1.0 - a * 0.5))
		for i in m:
			var ang := r.range(0.0, TAU)
			var d0 := r.range(0.5, R0 * 0.5)
			var ang2 := ang + r.range(-1.2, 1.2)
			var d1 := r.range(R0 * 0.55, R0)
			Lib.crackle(p, Lib.zigzag(r, cos(ang) * d0, sin(ang) * d0, cos(ang2) * d1, sin(ang2) * d1, 0.5, 0.0), 0.75 * (1.0 - a) + 0.25, C, 0.25)
		p.circle(0.0, 0.0, 3.0 * (1.0 - a) + 1.0, C[5])
		p.circle(0.0, 0.0, 2.0 * (1.0 - a) + 0.5, WHITE)
		p.glow(0.0, 0.0, 20.0, C[4], 0.55 * (1.0 - a))
		if t < SNAP + 0.07:
			p.glow(0.0, 0.0, 9.0, WHITE, 0.4)
	# the sparks: a bright head, the zigzag behind it cooling
	for s: Dictionary in kinked:
		if s.age < 0.0 or s.age >= s.life:
			continue
		var k: float = 1.0 - s.age / s.life
		var path: Array = s.trail + [[s.x, s.y]]
		for i in path.size() - 1:
			p.line(path[i][0], path[i][1], path[i + 1][0], path[i + 1][1], ((WHITE if k > 0.5 else C[6])) if i == path.size() - 2 else (C[5] if k > 0.5 else C[4]), 0.6 + 0.4 * (float(i) / path.size()))
		p.px(s.x, s.y, WHITE if k > 0.4 else C[5])
		p.glow(s.x, s.y, 4.0, C[5], 0.4 * k)
	# the light strobes as it dies
	if t >= SNAP:
		p.glow(0.0, 0.0, 40.0 * maxf(0.0, 1.0 - t / 0.85), C[3], 0.45 * exp(-(t - SNAP) * 5.0) * (0.7 if f % 2 else 1.0))
	ps.draw(p, "front")
	lights.draw(p)
