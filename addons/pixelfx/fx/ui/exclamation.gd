# port-of: src/fx/ui/exclamation.js@d5dd3a8444b0b8b459f464e707a91920e0bf3095
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Exclamation",
	"desc": "A bold ! springs up off the hero's head, stretching as it shoots up and squashing as it lands; surprise ticks flick out, it wobbles, then pops away.",
	"tags": ["ui", "alert", "surprise", "emote", "character", "one-shot"],
	"size": [84, 104],
	"origin": [42, 92],
	"duration": 1.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#2a1405", "#6a2e06", "#b85a0a", "#f08c14", "#ffc23a", "#ffe580", "#fff6c8", "#ffffff"], "seed": 3},
}

static var STARTLED := {"turn": 1, "y": -5, "crouch": -1, "fx": -14, "fy": -34, "bx": 15, "by": -34, "ffx": -3, "ffy": -6, "fbx": 4, "fby": -6}
static var act := {
	"poses": [
		[-0.08, Px.READY],
		[0, STARTLED, "snap"],
		[0.14, Px.merge(STARTLED, {"y": 0, "crouch": 4, "ffy": -4, "fby": -4, "fy": -26, "by": -26}), "in"],
		[0.3, {"turn": 1, "fx": -10, "fy": -23, "bx": 11, "by": -23, "ffx": -3, "fbx": 4}],
		[1.1, {"turn": 1, "fx": -10, "fy": -23, "bx": 11, "by": -23, "ffx": -3, "fbx": 4}],
		[1.4, Px.READY],
	],
	"dust": [{"t": 0.14, "x": 0, "n": 4}],
}

const HEAD := -40.0
const REST := -45.0
const POP := 1.1


# the mark: a bar that tapers to its foot and a round dot, with a dark outline, lit down its left side,
# turned by a about its foot
static func _hw(V: float) -> float:
	return 2.3 + (-V - 10.0) * 0.09


static func _inBar(U: float, V: float) -> bool:
	return V > -24.0 and V < -9.5 and absf(U) < _hw(V)


static func _inDot(U: float, V: float) -> bool:
	return Px.hypot(U, V + 3.6) < 3.3


static func _inside(U: float, V: float) -> bool:
	return _inBar(U, V) or _inDot(U, V)


static func bang(p: Px.Painter, C: Array, x: float, y: float, sx: float, sy: float, a: float, white: bool) -> void:
	var ca := cos(a)
	var sa := sin(a)
	p.shade(x - 16.0, y - 34.0, x + 16.0, y + 6.0, func(px: float, py: float):
		var dx := px - x
		var dy := py - y
		var u := (dx * ca + dy * sa) / sx
		var v := (-dx * sa + dy * ca) / sy
		var ex := 1.0 / sx
		var ey := 1.0 / sy
		if not _inside(u, v):
			return C[0] if (_inside(u - ex, v) or _inside(u + ex, v) or _inside(u, v - ey) or _inside(u, v + ey)) else null
		if white:
			return WHITE
		if _inDot(u, v):
			return WHITE if Px.hypot(u + 1.2, v + 4.8) < 1.2 else (C[6] if u + v + 3.6 < -0.5 else (C[5] if u + v + 3.6 < 1.5 else C[4]))
		var w := _hw(v)
		var q := (u + w) / (2.0 * w)
		if q < 0.28:
			return WHITE if v < -20.0 else C[7]
		if q > 0.74:
			return C[4]
		return C[6] if v < -18.0 else (C[5] if v < -13.0 else C[5]))


var C: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var m: Dictionary
var t := 0.0
var popped := false
var sprung := false
var end: float


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [C[7], C[6], C[5], C[3]]})
	lights = Px.Lights.new()
	# the mark's foot: shot up off the head with a spring, so it overshoots and settles
	m = {"y": HEAD, "vy": -420.0, "sq": 0.0, "landed": false}
	end = meta.duration - 0.05


func update(dt: float) -> void:
	t += dt
	if t < POP:
		# a stiff spring pulls it to its rest above the head
		m.vy += (-(m.y - REST) * 900.0 - m.vy * 14.0) * dt
		m.y += m.vy * dt
		if not m.landed and m.vy > 0.0:
			m.landed = true
			m.sq = 1.0
	m.sq = maxf(0.0, m.sq - dt / 0.12)
	# it leaves the head with a little burst of light
	if not sprung and t >= 0.04:
		sprung = true
		lights.add(0.0, HEAD - 4.0, 26.0, C[5], 0.6, 0.25)
		for i in 8:
			var an := -PI / 2.0 + R.range(-1.3, 1.3)
			var sp := R.range(40.0, 90.0)
			ps.spawn(P.STAR, R.range(-4.0, 4.0), HEAD - 2.0, cos(an) * sp, sin(an) * sp, R.range(0.2, 0.4), R.pick([C[7], C[6], C[5]]), 0.6 if i % 3 else 1.3)
	if not popped and t >= POP + 0.05:
		popped = true
		lights.add(0.0, REST - 13.0, 28.0, C[5], 0.5, 0.2)
		for i in 7:
			var an := (i / 7.0) * TAU + R.range(-0.2, 0.2)
			var sp := R.range(30.0, 60.0)
			ps.spawn(P.STAR, cos(an) * 5.0, REST - 13.0 + sin(an) * 9.0, cos(an) * sp, sin(an) * sp, minf(R.range(0.2, 0.35), end - t), R.pick([C[7], C[6], C[5]]), 0.6 if i % 3 else 1.4)
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	var k := t
	# surprise ticks: three flick out each side on the spring, and again on a second beat
	for tl in [[0.04, 6.0], [0.48, 4.5]]:
		var t0: float = tl[0]
		var len_: float = tl[1]
		var u := (k - t0) / 0.24
		if u <= 0.0 or u >= 1.0:
			continue
		for s in [-1.0, 1.0]:
			for i in 3:
				var an: float = -PI / 2.0 + s * (0.55 + i * 0.42)
				var r0 := 14.0 + 7.0 * Px.Ease.outCubic(u)
				var L := len_ * sin(u * PI) * (1.0 if i == 1 else 0.75)
				var cx := 0.0
				var cy := REST - 13.0
				var ca := cos(an)
				var sa := sin(an)
				if L < 0.8:
					continue
				p.line(cx + ca * r0, cy + sa * r0, cx + ca * (r0 + L), cy + sa * (r0 + L), func(q: float): return WHITE if q < 0.5 else C[5])
	# the mark: stretched while it shoots up, squashed as it lands, wobbling, white on the pop
	var pu := (k - POP) / 0.06
	if pu < 1.0:
		var speed := minf(1.0, absf(m.vy) / 420.0)
		var up := speed if m.vy < 0.0 else 0.0
		var sx: float = 1.0 - 0.3 * up + 0.3 * m.sq
		var sy: float = 1.0 + 0.45 * up - 0.28 * m.sq
		if k < 0.05:
			sx *= k / 0.05
			sy *= k / 0.05
		if pu > 0.0:
			sx = 1.0 + 0.3 * pu
			sy = sx
		var wob := 0.28 * exp(-k * 4.0) * sin(k * 26.0)
		var white := k < 0.06 or pu > 0.0
		if sx > 0.1:
			bang(p, C, 0.0, m.y, sx, sy, wob, white)
		p.glow(0.0, m.y - 13.0, 20.0, C[5], 0.35 + (0.3 if white else 0.0))
		if k > 0.6 and k < 0.85:
			Px.sparkle(p, -3.0, m.y - 22.0, 3.5 * sin(((k - 0.6) / 0.25) * PI), C[7], C[6], 0.4)
	ps.draw(p)
	lights.draw(p)
