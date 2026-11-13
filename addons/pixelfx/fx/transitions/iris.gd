# The motes drifting in the light and the glints follow Sprite Fusion's open-source holy-light and sparkle
# (https://www.spritefusion.com/pixel-art-vfx/sparkle), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/iris.js@022b4ba67998bba6943eb6aefbc748ec23df8868
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE
const W := Lib.W
const H := Lib.H

static var meta := Lib.screenMeta({
	"name": "Iris",
	"desc": "A lit iris closes onto a warm spotlight where dust drifts, holds as its rim twinkles, snaps shut into a glint, then pops open from a flash with a white-hot rim throwing sparks.",
	"tags": ["iris", "circle", "spotlight", "wipe"],
	"duration": 2.2,
	"options": {"palette": ["#1c140c", "#3b2a18", "#6e5233", "#a8875a", "#d9bd8a", "#f3e2bd", "#fff7e8", "#ffffff"], "focus": [160, 100], "seed": 1},
})

static var D: float = meta.duration
const CLOSE := 0.62
const SNAP := 0.9
const SHUT := 0.99
const POP := 1.2
const OPEN := 1.75
const RS := 24.0
const RW := 5.0
const GLO := 16.0

var C: Array
var ink: int
var R: Px.Rng
var fx: float
var fy: float
var R0: float
var ps: Px.Particles
var lights: Px.Lights
var t := 0.0
var shut := false
var popped := false
var prevR: float
var end: float


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	ink = Px.hex(o.color)
	R = Px.Rng.new(o.seed)
	fx = float(o.focus[0])
	fy = float(o.focus[1])
	var ds := [[0, 0], [W, 0], [0, H], [W, H]].map(func(q): return Px.hypot(q[0] - fx, q[1] - fy))
	R0 = ds.max() + RW + 2.0
	ps = Px.Particles.new({"rng": R, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	t = 0.0
	shut = false
	popped = false
	prevR = R0
	end = D - 0.05


# the hole's radius: closing, breathing on the spotlight, snapping shut; then popping open
func radius(t: float) -> float:
	return RS + (R0 - RS) * (1.0 - Px.Ease.inOutCubic(t / CLOSE)) if t < CLOSE \
		else (RS + sin((t - CLOSE) * 22.0) * 0.8 * (1.0 - (t - CLOSE) / (SNAP - CLOSE)) if t < SNAP \
			else (RS * (1.0 - Px.Ease.inCubic((t - SNAP) / (SHUT - SNAP))) if t < SHUT \
				else (0.0 if t < POP else R0 * Px.Ease.outQuart(Px.clamp((t - POP) / (OPEN - POP))))))


func update(dt: float) -> void:
	t += dt
	var r := radius(t)
	# dust drifts up through the spotlight while it holds
	if t > CLOSE - 0.25 and t < SNAP and R.chance(0.25):
		var a := R.range(0, TAU)
		var d := sqrt(R.next()) * r * 0.9
		ps.spawn(P.EMBER, fx + cos(a) * d, fy + sin(a) * d, R.range(-6, 6), -R.range(4, 14), R.range(0.4, 0.8), 0, 1)
	# the rim twinkles as it holds
	if t > CLOSE - 0.1 and t < SNAP and R.chance(0.3):
		var a := R.range(0, TAU)
		ps.spawn(P.STAR, fx + cos(a) * (r + 1.0), fy + sin(a) * (r + 1.0), 0, 0, R.range(0.2, 0.4), WHITE if R.chance(0.5) else C[6], R.range(1, 2.4))
	if not shut and t >= SHUT:
		shut = true
		lights.add(fx, fy, 50, C[5], 0.7, 0.3)
	if not popped and t >= POP:
		# pop: a white flash, sparks thrown out of the opening
		popped = true
		lights.add(fx, fy, 140, C[5], 0.7, 0.45)
		lights.add(fx, fy, 50, WHITE, 0.9, 0.12)
		for i in 40:
			var a := R.range(0, TAU)
			var v := R.range(150, 420)
			ps.spawn(P.SPARK, fx + cos(a) * 3.0, fy + sin(a) * 3.0, cos(a) * v, sin(a) * v, R.range(0.2, 0.5))
	# as the rim races out it sheds glinting motes that fly on and fade
	if t > POP and t < OPEN - 0.1:
		var vr := (r - prevR) / dt
		for k in 2:
			if not R.chance(0.6):
				continue
			var a := R.range(0, TAU)
			var x := fx + cos(a) * r
			var y := fy + sin(a) * r
			if x < 0.0 or y < 0.0 or x >= W or y >= H:
				continue
			ps.spawn(P.MOTE, x, y, cos(a) * vr * 0.35, sin(a) * vr * 0.35, minf(R.range(0.2, 0.45), end - t), C[6] if R.chance(0.5) else C[5], 0.7)
	prevR = r
	ps.update(dt)
	lights.update(dt)


func draw(p0: Px.Painter) -> void:
	var p := Lib.clipTo(p0)
	var r := radius(t)
	# the rim's heat: warm while it closes, white-hot as it pops, cooling as it opens
	var hot := 1.0 - Px.smooth(POP, OPEN, t) if t >= POP else (0.45 + 0.25 * Px.smooth(CLOSE - 0.2, CLOSE, t) if t < SNAP else 0.7)
	var rw := RW + (3.0 * hot if t >= POP else 0.0)
	if t < OPEN + 0.05 and not (t >= SHUT and t < POP and r <= 0.0):
		for y in H:
			var dy := y + 0.5 - fy
			var xo := sqrt(maxf(0.0, (r + rw) ** 2 - dy * dy))
			var _xi := sqrt(r * r - dy * dy) if absf(dy) < r else 0.0
			if xo <= 0.0:
				Lib.rect(p0, 0.0, y, W, 1.0, ink)
				continue
			var a0 := Px.clamp(floorf(fx - xo), 0.0, W)
			var b1 := Px.clamp(ceilf(fx + xo), 0.0, W)
			if a0 > 0.0:
				Lib.rect(p0, 0.0, y, a0, 1.0, ink)
			if b1 < W:
				Lib.rect(p0, b1, y, W - b1, 1.0, ink)
			# the rim band and the light just inside it
			var g := sqrt(maxf(0.0, (r - GLO) ** 2 - dy * dy)) if r > GLO else 0.0
			for x in range(int(a0), int(b1)):
				var dx := x + 0.5 - fx
				if absf(dx) < g:
					continue
				var d := Px.hypot(dx, dy) - r
				if d >= 0.0:
					# a bevel lit from the top left: bright there, a step darker round the far side
					var q := d / rw
					var lit := 0.5 - 0.5 * (dx * 0.7 + dy * 0.7) / (r + d + 0.01)
					var h := hot * (0.55 + 0.6 * lit)
					p0.px(x, y, ink if q >= 1.0 else ((WHITE if h > 0.5 else (C[6] if h > 0.3 else C[5])) if q < 0.2 else ((C[6] if h > 0.38 else C[5]) if q < 0.4 else ((C[5] if h > 0.3 else C[4]) if q < 0.65 else (C[3] if q < 0.85 else C[2])))))
					if q < 0.5:
						p0.light(x, y, C[5], 0.45 * h * (1.0 - q * 2.0))
				elif d > -GLO:
					p0.light(x, y, C[5], (0.18 + 0.3 * hot) * (1.0 + d / GLO) ** 2)
	elif t >= SHUT and t < POP:
		Lib.rect(p0, 0.0, 0.0, W, H, ink)
	# the spotlight's pool of light, gathering as the iris closes, hottest at its heart
	if r > 0.0 and r < 80.0 and t < SHUT:
		var k := 1.0 - r / 80.0
		p.glow(fx, fy, r * 1.15 + 6.0, C[5], 0.18 + 0.32 * k)
		p.glow(fx, fy, r * 0.6 + 3.0, C[6], 0.25 * k)
	# light catches the iris as it turns: a glint runs once round the rim while it closes
	if t > 0.08 and t < SNAP:
		var a := -2.4 + ((t - 0.08) / (SNAP - 0.08)) * TAU
		var gx := fx + cos(a) * (r + 1.0)
		var gy := fy + sin(a) * (r + 1.0)
		if gx > 2.0 and gy > 2.0 and gx < W - 2.0 and gy < H - 2.0:
			Lib.glint(p, gx, gy, 7.0 + 3.0 * sin(t * 9.0), t * 3.0, C[6], C[5], 0.9)
	# snapping shut: the light collapses into a glint that lingers in the dark
	var s := t - SHUT
	if s > -0.06 and s < 0.22:
		Lib.glint(p, fx, fy, 14.0 * (1.0 - absf(s + 0.01) / 0.23), s * 4.0, C[6], C[5])
	# popping open: a flash at the heart
	var u := t - POP
	if u >= 0.0 and u < 0.18:
		Lib.glint(p, fx, fy, 20.0 * (1.0 - u / 0.18), 0.4 - u * 3.0, C[6], C[5])
		p.glow(fx, fy, 60.0, WHITE, 0.6 * (1.0 - u / 0.18))
	ps.draw(p)
	lights.draw(p)
