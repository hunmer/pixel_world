# Shared by the scifi effects. Ghosts: the toolkit's simulated particles for loops (sparks that fall and bounce,
# smoke that rises and thins) worked out from their birth each frame, so a loop is a function of t alone and has
# no seam. Also lights that flare in loops, and electric arcs stroked the way Hugo strokes his bolts. Their motion is the toolkit's (src/core/sim.js), which is adapted from Sprite Fusion's open-source
# pixel art VFX (https://www.spritefusion.com/pixel-art-vfx), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/scifi/_lib.js@1c8b8fe0b500b3348a9b1f6536cd2bb9ad9f52a8
extends RefCounted

const Px := preload("../../core/px.gd")
const Self := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const GRAVITY := Px.GRAVITY
const WHITE := Px.WHITE

const SOFT := {P.VAPOUR: true, P.DUST: true, P.SMOKE: true}
const STEP := 1.0 / 240.0


# one toolkit step for one particle, with its own age standing in for the system clock (so it repeats)
static func move(q: Dictionary, dt: float, age: float, ground: Callable) -> void:
	match q.k:
		P.FIRE:
			q.vy -= 95.0 * dt
			q.vx += sin(age * 17.0 + q.seed) * 30.0 * dt
			q.vx -= q.vx * 5.0 * dt
			q.vy -= q.vy * 3.2 * dt
		P.GRIT:
			q.vy += GRAVITY * dt
			q.vx -= q.vx * 0.8 * dt
			var g: float = ground.call(q.x)
			var ny: float = q.y + q.vy * dt
			q.x += q.vx * dt
			if q.vy > 0.0 and q.y <= g and ny >= g:
				q.y = g - 0.25
				var hop := false
				if q.vy > 130.0:
					var h: int = q.hops
					q.hops += 1
					hop = Px.rand(q.seed * 1000.0, h) < 0.4
				if hop:
					q.vy = -q.vy * 0.25
					q.vx = q.vx * 0.5
				else:
					q.vy = 0.0
					q.vx = 0.0
					q.life = minf(q.life, 0.5)
			else:
				q.y = ny
			return
		P.SPARK:
			q.vy += GRAVITY * 0.45 * dt
			q.vx -= q.vx * 2.2 * dt
			q.vy -= q.vy * 2.2 * dt
			var g: float = ground.call(q.x)
			var ny: float = q.y + q.vy * dt
			q.x += q.vx * dt
			if q.vy > 0.0 and q.y <= g and ny >= g:
				q.vy = -q.vy * 0.45
				q.vx *= 0.7
				q.y = g - 0.25
			else:
				q.y = ny
			return
		P.STREAK:
			q.vx += q.vx * 3.0 * dt
			q.vy += q.vy * 3.0 * dt
		P.FLAKE:
			q.vx -= q.vx * 2.2 * dt
			q.vy -= q.vy * 2.2 * dt - 35.0 * dt
			q.x += sin(age * 2.5 + q.seed) * 7.0 * dt
		P.EMBER:
			q.vy += (-30.0 + sin(age * 3.0 + q.seed) * 20.0) * dt
			q.vx += cos(age * 2.3 + q.seed) * 45.0 * dt
			q.vx -= q.vx * 1.6 * dt
			q.vy -= q.vy * 1.6 * dt
		P.SMOKE:
			var big: int = q.flag & PF.BIG
			q.vy -= (23.0 if big else 16.0) * dt
			q.vx += sin(age * 1.3 + q.seed) * 8.0 * dt
			q.vx -= q.vx * 1.6 * dt
			q.vy -= q.vy * 1.2 * dt
		P.MOTE:
			q.vx -= q.vx * 0.6 * dt
			q.vy -= q.vy * 0.6 * dt
		_:
			var drag := 4.0 if SOFT.has(q.k) else 1.6
			q.vx -= q.vx * drag * dt
			q.vy -= q.vy * drag * dt + 5.0 * dt
	q.x += q.vx * dt
	q.y += q.vy * dt


## Simulated particles for loops. add(born, ...Particles.spawn arguments) once, at build time, for each particle
## born `born` seconds into the period; at(t) returns a Particles holding every particle alive at t, each moved
## there from its birth by the toolkit's physics, ready for draw(p, layer). A particle born late in the period
## carries on into the next one, so the loop has no seam. opts: the Particles options (ground, sparks, haze) and
## box: [x0, y0, x1, y1], outside which particles are dropped (keeps sparks on the canvas).
class Ghosts extends RefCounted:
	var D: float
	var ground: Callable
	var _g1: Callable
	var box: Variant
	var ps: Px.Particles
	var specs: Array = []
	var count: int:
		get: return specs.size()

	func _init(period: float, opts: Dictionary = {}) -> void:
		D = period
		ground = opts.ground if opts.get("ground") != null else func(): return INF
		# move() calls ground(x); a ground taking no argument is called without it (JS ignores extra arguments)
		var g0 := ground
		_g1 = g0 if g0.get_argument_count() >= 1 else func(_x): return g0.call()
		box = opts.get("box")
		ps = Px.Particles.new({"ground": ground, "sparks": opts.get("sparks"), "haze": opts.get("haze")})
		specs = []

	func add(born: float, k: int, x: float, y: float, vx: float, vy: float, life: float, col: Variant = WHITE, size: float = 1.0, flag: int = 0) -> void:
		var n := specs.size()
		# a star's twinkle runs on the clock: pick its seed so the twinkle repeats with the period too
		var seed := Px.rand(n, 41) * 100.0
		if k == P.STAR:
			var m := ceilf((8.0 * D) / TAU)
			var f := (TAU * m) / D - 8.0
			if f < 5.0:
				seed = f + 5.0 * floorf(Px.rand(n, 43) * 19.0)
		specs.append({"born": fmod(fmod(born, D) + D, D), "k": k, "x": x, "y": y, "vx": vx, "vy": vy, "life": life, "col": Px.hex(col) if col else 0, "size": size, "flag": flag, "seed": seed})

	## The state of one particle `age` seconds after its birth, or null if it's gone.
	func state(s: Dictionary, age: float) -> Variant:
		var q := {"k": s.k, "x": s.x, "y": s.y, "vx": s.vx, "vy": s.vy, "life": s.life, "max": s.life, "col": s.col, "size": s.size, "seed": s.seed, "delay": 0.0, "flag": s.flag, "hops": 0}
		var a := 0.0
		while a < age - 1e-9:
			var dt := minf(STEP, age - a)
			Self.move(q, dt, a, _g1)
			a += dt
			q.life -= dt
			if q.life <= 0.0:
				# a fire puff with SMOKES turns into smoke when it dies, as in the toolkit
				if q.k != P.FIRE or not (q.flag & PF.SMOKES):
					return null
				var big: int = q.flag & PF.BIG
				var L: float = 1.3 + Px.rand(s.seed * 7.0, 1) if big else 0.8 + Px.rand(s.seed * 7.0, 1) * 0.6
				var nvx: float = q.vx * 0.6
				var nvy: float = q.vy * 0.6 - 6.0
				var nsize: float = q.size * (0.85 if big else 0.7)
				q.k = P.SMOKE
				q.vx = nvx
				q.vy = nvy
				q.life = L
				q.max = L
				q.col = 0
				q.size = nsize
				q.flag = PF.BIG if big else 0
		if box != null:
			var x0: float = box[0]
			var y0: float = box[1]
			var x1: float = box[2]
			var y1: float = box[3]
			if q.x < x0 or q.x > x1 or q.y < y0 or q.y > y1:
				return null
		return q

	func at(t: float) -> Px.Particles:
		var list := []
		for s: Dictionary in specs:
			# its age now, and in each earlier period it may still be alive from (smoke from fire lives longer)
			var span: float = s.life + 2.4 if (s.k == P.FIRE and s.flag & PF.SMOKES) else s.life
			var age := fmod(fmod(t - s.born, D) + D, D)
			while age < span:
				var q: Variant = state(s, age)
				if q:
					list.append(q)
				age += D
		ps.list = list
		ps.t = t
		return ps


## A light that flares at t0 and dies over life, as the toolkit's Lights do, for loops: k falls with life².
static func flash(p: Px.Painter, t: float, t0: float, x: float, y: float, r: float, c: int, k: float, life: float) -> void:
	var a := t - t0
	if a < 0.0 or a >= life:
		return
	var q := 1.0 - a / life
	p.glow(x, y, r * (0.55 + 0.45 * q), c, k * q * q)


## Smallest positive age of an event at t0 in a loop of period D, seen at t.
static func since(t: float, t0: float, D: float) -> float:
	return fmod(fmod(t - t0, D) + D, D)


## An electric arc along a path [[x, y], ...], drawn the way Hugo strokes his bolts: a dark halo, a bright body,
## a white-hot core while it's fresh, light along it. C: [halo, body, glow]; k: 1 fresh, falling to 0; w: weight.
static func strokeArc(p: Px.Painter, pts: Array, C: Array, k: float = 1.0, w: float = 1.0) -> void:
	var halo: int = C[0]
	var body: int = C[1]
	var glow: int = C[2]
	for pass_ in [0, 1, 2]:
		for i in range(1, pts.size()):
			var ax: float = pts[i - 1][0]
			var ay: float = pts[i - 1][1]
			var bx: float = pts[i][0]
			var by: float = pts[i][1]
			var L := maxf(1.0, Px.hypot(bx - ax, by - ay))
			var d := 0.0
			while d <= L:
				var x := ax + ((bx - ax) * d) / L
				var y := ay + ((by - ay) * d) / L
				if pass_ == 0:
					p.circle(x, y, (1.6 if k > 0.6 else 1.1) * w, halo)
				elif pass_ == 1:
					p.circle(x, y, (0.9 if k > 0.6 else 0.6) * w, body)
				elif k > 0.3:
					p.px(x, y, WHITE)
				d += 0.5
			if pass_ == 0 and i % 3 == 0:
				p.glow(ax, ay, 9.0 * w, glow, 0.45 * k)
