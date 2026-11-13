# port-of: src/fx/shadow/life-steal.js@939c1776e763ff4e387fc325d9529a042e027650
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Life steal",
	"desc": "A target on the right is struck and bleeds red orbs; they hang a moment, then whip home as comet streaks and flood the caster crimson.",
	"tags": ["shadow", "life-steal", "drain", "blood", "heal", "directional", "magic", "one-shot"],
	"size": [184, 100],
	"origin": [36, 92],
	"duration": 2.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#14040a", "#3a0a14", "#6a101c", "#a01824", "#d42a30", "#ff5a50", "#ff9a8a", "#ffe6de"], "dark": "#2a1040", "seed": 11},
}

static var GRASP := Px.merge(Px.READY, {"crouch": 3, "lean": 3, "fx": 17, "fy": -28, "bx": -6, "by": -21, "ffx": 10, "fbx": -9})
static var FED := {"turn": 1.15, "crouch": 0, "lean": -3, "hy": -1, "fx": -13, "fy": -37, "bx": 14, "by": -37, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"follow": 0,
	"target": {"x": 104},
	"poses": [
		[-0.46, Px.READY],
		[-0.2, Px.merge(Px.READY, {"crouch": 4, "lean": -2, "fx": 3, "fy": -27, "bx": 8, "by": -20})],
		[0, GRASP, "snap"],
		[0.4, GRASP],
		[0.7, Px.merge(GRASP, {"fx": 13, "fy": -26, "lean": 1})],
		[0.8, Px.merge(FED, {"crouch": 2}), "snap"],
		[1.22, FED],
		[1.7, {"turn": 1, "crouch": 2, "fx": -11, "fy": -26, "bx": 12, "by": -26, "ffx": -3, "fbx": 4}],
		[2.2, Px.READY],
	],
	"hits": [
		{"t": 0.01, "stop": 0.07, "shake": 0.12, "amp": 1, "push": 1.6, "straw": 12, "skin": "red", "y": -24},
		{"t": 1.6, "push": 0, "straw": 0, "flash": 0, "skin": null},
	],
}

# the target point on the right, the caster's heart; when the orbs turn for home
const TX := 104.0
const TY := -24.0
const HX := 1.0
const HY := -20.0
const N := 7


var C: Array
var R: Px.Rng
var A: Variant
var ps: Px.Particles
var drops: Lib.Drops
var stains: Array = []
var lights: Array = []
var orbs: Array = []
var t := 0.0
var hit := false
var flush := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	A = o.get("actor")
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [WHITE, C[7], C[6], C[5]]})
	drops = Lib.Drops.new({"onLand": func(x): stains.append({"x": x, "t0": t})})
	stains = []
	lights = []
	orbs = []
	for i in N:
		var a := -PI / 2.0 + (i - (N - 1) / 2.0) * 0.4 + R.range(-0.12, 0.12)
		var sp := R.range(100.0, 170.0)
		orbs.append({"x": TX, "y": TY, "vx": cos(a) * sp + 10.0, "vy": sin(a) * sp, "home": 0.36 + i * 0.05 + R.range(0.0, 0.04), "trail": [], "done": false, "at": 0.0, "size": R.range(1.6, 2.4)})
	t = 0.0
	hit = false
	flush = 0.0


func light(x: float, y: float, r: float, c: Variant, k: float, life: float) -> void:
	lights.append({"x": x, "y": y, "r": r, "c": c, "k": k, "life": life, "max": life})


func update(dt: float) -> void:
	t += dt
	if not hit:
		hit = true
		light(TX, TY, 54.0, C[5], 1.0, 0.35)
		light(TX, TY, 18.0, WHITE, 1.0, 0.08)
		for i in 14:
			drops.add(TX + R.range(-3.0, 3.0), TY + R.range(-3.0, 3.0), R.range(-40.0, 90.0), R.range(-140.0, -20.0), 2.0 if R.chance(0.4) else 1.0)
		for i in 12:
			var a := R.range(0.0, TAU)
			var sp := R.range(80.0, 170.0)
			ps.spawn(P.SPARK, TX, TY, cos(a) * sp, sin(a) * sp, R.range(0.15, 0.35))
	for b: Dictionary in orbs:
		if b.done:
			continue
		if t < b.home:
			# burst out, slowing to a hover
			b.vx -= b.vx * 5.0 * dt
			b.vy -= b.vy * 5.0 * dt
		else:
			# whip home: steer hard at the caster's heart, faster and faster
			var dx: float = HX - b.x
			var dy: float = HY - b.y
			var d := Px.hypot(dx, dy)
			if not d:
				d = 1.0
			var pull := 2600.0 * minf(1.0, (t - b.home) * 3.0)
			b.vx += (dx / d) * pull * dt
			b.vy += (dy / d) * pull * dt
			b.vx -= b.vx * 2.2 * dt
			b.vy -= b.vy * 2.2 * dt
			if d < 6.0:
				b.done = true
				b.at = t
				flush = minf(1.5, flush + 0.45)
				light(HX, HY, 30.0, C[5], 0.8, 0.25)
				for i in 6:
					var a := R.range(0.0, TAU)
					var sp := R.range(40.0, 100.0)
					ps.spawn(P.SPARK, HX, HY, cos(a) * sp, sin(a) * sp - 20.0, R.range(0.12, 0.3))
				for i in 3:
					ps.spawn(P.EMBER, HX + R.range(-8.0, 8.0), HY + R.range(-6.0, 14.0), R.range(-10.0, 10.0), -R.range(15.0, 35.0), R.range(0.6, 1.1), C[6])
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.trail.push_front([b.x, b.y])
		if b.trail.size() > 26:
			b.trail.pop_back()
	flush -= flush * 2.6 * dt
	for i in range(lights.size() - 1, -1, -1):
		lights[i].life -= dt
		if lights[i].life <= 0.0:
			lights.remove_at(i)
	for i in range(stains.size() - 1, -1, -1):
		if t - stains[i].t0 > 0.8:
			stains.remove_at(i)
	drops.update(dt)
	ps.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the wound: a dark red bloom where the target was struck, thinning away
	var k := 1.0 - Px.smooth(0.1, 0.9, t)
	if k > 0.0:
		p.disc(TX, TY, 6.0 + t * 10.0, C[2], 0.5 * k)
		p.glow(TX, TY, 30.0, C[4], 0.35 * k)
	for s: Dictionary in stains:
		p.dot(s.x, -0.5, C[3], 1.0 - (t - s.t0) / 0.8)


func draw(p: Px.Painter) -> void:
	# the caster flushes crimson as the orbs land: its own colours pushed toward blood-red, a hot outline
	var fk := minf(1.0, flush) * (1.0 - Px.smooth(1.5, 2.05, t))
	if A and fk > 0.03:
		var aw: int = A.w
		var ah: int = A.h
		var pix: PackedInt32Array = A.pixels
		for my in ah:
			for mx in aw:
				var c0 := pix[my * aw + mx]
				if not c0:
					continue
				var l := Px.luma(c0)
				p.blend(A.x + mx, A.y + my, C[6] if l > 0.6 else (C[5] if l > 0.4 else (C[4] if l > 0.2 else C[3])), 0.45 * fk)
		if fk > 0.12:
			p.outline(A.mask, A.x, A.y, C[6] if fk > 0.6 else (C[5] if fk > 0.3 else C[3]))
		p.glow(HX, HY, 28.0, C[5], 0.45 * fk)
	# the hit on the target
	if t < 0.12:
		Px.sparkle(p, TX, TY, 10.0 * (1.0 - t / 0.12), C[7], C[5], 0.6)
	var ru := t / 0.28
	if ru < 1.0:
		Lib.ringFast(p, TX, TY, 4.0 + 16.0 * Px.Ease.outCubic(ru), maxf(1.0, 2.0 * (1.0 - ru)), C[7] if ru < 0.4 else C[5])
	drops.draw(p, C[3], C[6])
	# the orbs: comet tails tapering from a hot head through blood-red to a dark wine thread
	for b: Dictionary in orbs:
		if b.done and t - b.at > 0.2:
			continue
		# the tail is swallowed after the head: it shortens rather than fades
		var n: int = floori(b.trail.size() * (1.0 - (t - b.at) / 0.2)) if b.done else b.trail.size()
		var i := n - 1
		while i >= 1:
			var u := i / 25.0
			var x0: float = b.trail[i - 1][0]
			var y0: float = b.trail[i - 1][1]
			var x1: float = b.trail[i][0]
			var y1: float = b.trail[i][1]
			p.line(x1, y1, x0, y0, C[7] if u < 0.15 else (C[6] if u < 0.35 else (C[5] if u < 0.6 else (C[4] if u < 0.8 else C[2]))))
			if i < 7:
				p.disc(x1, y1, (b.size + 0.4) * (1.0 - i / 7.0), C[6] if u < 0.12 else C[5], 0.8)
			if i % 6 == 3:
				p.glow(x1, y1, 6.0, C[5], 0.2 * (1.0 - u))
			i -= 1
		if b.done:
			continue
		var pulse: float = 0.8 + 0.2 * sin(t * 30.0 + b.size * 9.0) if t < b.home else 1.0
		p.circle(b.x, b.y, b.size + 0.9, C[4])
		p.circle(b.x, b.y, b.size * pulse, C[6])
		p.px(b.x - 0.5, b.y - 0.5, WHITE)
		p.glow(b.x, b.y, 9.0, C[5], 0.5)
	ps.draw(p)
	for l: Dictionary in lights:
		var q: float = l.life / l.max
		p.glow(l.x, l.y, l.r * (0.6 + 0.4 * q), l.c, l.k * q * q)
