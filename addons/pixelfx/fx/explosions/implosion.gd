# The gathering streaks, the pulse rings and the release (cross flare, rings, light) are adapted from Sprite Fusion's
# open-source energy charge (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/implosion.js@a5688ab93bdd3199533cc2f6f1b378f5734eef8d
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Implosion",
	"desc": "Everything is sucked in: streaks and grit rush inward, rings contract and a dark sphere collapses onto a crushed white point; a beat of stillness, then a sharp pop.",
	"tags": ["implosion", "energy", "magic", "collapse", "pop", "one-shot"],
	"size": [208, 184],
	"origin": [104, 92],
	"duration": 1.65,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": ["#0a0614", "#1c1236", "#3a2470", "#6a44c0", "#a080f0", "#d8c8ff", "#ffffff"], "seed": 2},
}

const SUCK := 0.8
const STILL := 1.02
static var VOID := Px.hex("#05040a")


var C: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var grit: Array
var rays: Array
var t := 0.0
var popped := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [C[6], C[5], C[4], C[3]]})
	lights = Px.Lights.new()
	# grit pulled in: specks that spiral toward the middle, faster and faster
	grit = []
	for i in 70:
		var t0 := R.range(0.0, 0.4)
		grit.append({"a": R.range(0.0, TAU), "d": R.range(40.0, 86.0), "t0": t0, "T": R.range(0.3, SUCK - 0.04 - t0), "spin": R.sign() * R.range(0.6, 1.6), "c": R.pick([C[2], C[3], C[4], Px.hex("#4a4458"), Px.hex("#6e6880")])})
	rays = []
	for i in 4:
		rays.append((i * TAU) / 4.0 + PI / 4.0)


func update(dt: float) -> void:
	t += dt
	if t < SUCK - 0.26:
		# streaks of light rushing in from all round, accelerating, more of them as it goes
		var k := t / SUCK
		for n in 1 + floori(k * 4.0):
			if not R.chance(0.9):
				continue
			var a := R.range(0.0, TAU)
			var D := R.range(34.0, 82.0) * (1.0 - 0.3 * k)
			var T := R.range(0.14, 0.24)
			var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
			ps.spawn(P.STREAK, cos(a) * D, sin(a) * D, -cos(a) * v, -sin(a) * v, T, C[5] if R.chance(0.5) else C[4])
		# vapour drawn in along the way
		if R.chance(14.0 * dt):
			var a := R.range(0.0, TAU)
			var D := R.range(50.0, 80.0)
			ps.spawn(P.VAPOUR, cos(a) * D, sin(a) * D, -cos(a) * 90.0, -sin(a) * 90.0, R.range(0.4, 0.6), C[3], R.range(3.0, 5.0))
	if not popped and t >= STILL:
		popped = true
		lights.add(0.0, 0.0, 90.0, C[4], 1.0, 0.4)
		lights.add(0.0, 0.0, 30.0, WHITE, 0.9, 0.08)
		for i in 34:
			var a := R.range(0.0, TAU)
			var sp := R.range(120.0, 330.0)
			ps.spawn(P.MOTE if R.chance(0.6) else P.STAR, 0.0, 0.0, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.45), R.pick([C[6], C[5], C[4]]), R.range(0.8, 1.8))
	ps.update(dt)
	Lib.cull(ps, -meta.origin[0] + 3, -meta.origin[1] + 3, meta.size[0] - meta.origin[0] - 3, meta.size[1] - meta.origin[1] - 3)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	var k := Px.clamp(t / SUCK)
	if t < STILL:
		# the void: a dark sphere edged with light, collapsing onto the core
		var vr := 64.0 * (1.0 - Px.Ease.inCubic(k)) + 3.0
		if k < 1.0:
			p.disc(0.0, 0.0, vr, VOID, 0.35 + 0.35 * k)
			p.ring(0.0, 0.0, vr + 1.0, 1.0, C[3] if k < 0.5 else C[4], 0.5 + 0.5 * k)
			p.glowRing(0.0, 0.0, vr, 5.0, C[4], 0.18 + 0.3 * k)
		# rings pulled in after it, one after another, brighter as they go
		for i in 4:
			var u := (t - i * 0.17) / 0.34
			if u <= 0.0 or u >= 1.0:
				continue
			var r := (70.0 - i * 8.0) * (1.0 - Px.Ease.inQuad(u)) + 2.0
			p.ring(0.0, 0.0, r, 2.0 if u > 0.7 else 1.0, C[5] if u > 0.6 else C[3], 0.4 + 0.6 * u)
		# the grit, spiralling in
		for q in grit:
			var u: float = (t - q.t0) / q.T
			if u <= 0.0 or u >= 1.0:
				continue
			var d: float = q.d * (1.0 - Px.Ease.inCubic(u))
			var a: float = q.a + q.spin * Px.Ease.inQuad(u) * 2.0
			var x := cos(a) * d
			var y := sin(a) * d
			var x2: float = cos(a - q.spin * 0.1) * (d + 4.0 * u * u + 0.5)
			var y2: float = sin(a - q.spin * 0.1) * (d + 4.0 * u * u + 0.5)
			var qc: int = q.c
			p.line(x2, y2, x, y, func(v: float): return Px.mix(qc, VOID, 0.4) if v < 0.5 else qc)
		# the core: growing hotter as it's crushed, then a white point trembling in the stillness
		var still := t > SUCK
		var jit := (0.5 if floori(t * 40.0) % 2 else -0.5) if still else 0.0
		var cr := 1.6 if still else 1.0 + 3.5 * (1.0 - k) * k * 4.0
		p.disc(jit, 0.0, cr + 3.5, VOID, 0.85)
		p.circle(jit, 0.0, cr + 1.2, C[4])
		p.circle(jit, 0.0, cr, WHITE)
		p.glow(0.0, 0.0, 10.0 + 26.0 * k, C[4], 0.3 + 0.5 * k)
		if still:
			p.glow(0.0, 0.0, 8.0, WHITE, 0.4 + 0.2 * sin(t * 60.0))
	else:
		# the pop: a white point bursting, a cross flare, a fast thin ring and a slower one
		var q := (t - STILL) / 0.5
		var e := Px.Ease.outCubic(Px.clamp(q))
		if q < 0.08:
			p.circle(0.0, 0.0, 6.0 * (1.0 - q / 0.08) + 1.0, WHITE)
		if q < 0.35:
			var L := (1.0 - q / 0.35) * 34.0 + 3.0
			for a in rays:
				var d := 0.0
				while d <= L:
					p.dot(cos(a) * d, sin(a) * d, WHITE if d < L * 0.4 else C[5], 1.0 if d < L * 0.7 else 1.0 - (d / L - 0.7) / 0.3)
					d += 0.5
			for a in rays:
				var d := 0.0
				while d <= L * 0.45:
					p.dot(cos(a + PI / 4.0) * d, sin(a + PI / 4.0) * d, C[5], 1.0 - d / (L * 0.45))
					d += 0.5
		if q < 1.0:
			p.ring(0.0, 0.0, 4.0 + 74.0 * e, maxf(1.0, 2.5 * (1.0 - q)), WHITE if q < 0.2 else C[5], 1.15 - q)
			p.ring(0.0, 0.0, 2.0 + 40.0 * Px.Ease.outCubic(Px.clamp(q * 1.4)), 1.0, C[4], 1.0 - q)
		if q < 0.6:
			Px.sparkle(p, 0.0, 0.0, 5.0 * (1.0 - q / 0.6), WHITE, C[5], 0.6)
	ps.draw(p)
	lights.draw(p)
