# The flames that cool into smoke, the embers and the smouldering glow are adapted from Sprite Fusion's
# open-source fire (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/spawn/dissolve-burn.js@22b57740bdec7b747ad75baf7ab3c24e16154739
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE

static var meta := {
	"name": "Dissolve burn",
	"desc": "An ember seam lights at the feet and climbs the body: above it the body scorches and smoulders, at it flames lick up, below it there's only falling ash, embers and smoke.",
	"tags": ["spawn", "death", "burn", "fire", "ash", "dissolve", "embers", "one-shot"],
	"size": [96, 112],
	"origin": [48, 100],
	"duration": 3.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#2a0e08", "#5a1a0c", "#a8320f", "#e8601a", "#ff9a2e", "#ffd25a", "#fff3c0", "#ffffff"],
		"ash": ["#2a2428", "#4a4248", "#6e6670"],
		"seed": 16,
	},
}

static var WRITHE := {"turn": 1, "crouch": 2, "fx": -13, "fy": -35, "bx": 13, "by": -26, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"poses": [
		[-0.16, Px.READY],
		[0.4, {"turn": 1, "crouch": 2, "fx": -9, "fy": -22, "bx": 10, "by": -22, "ffx": -3, "fbx": 4}],
		[0.8, WRITHE],
		[1.2, Px.merge(WRITHE, {"lean": 2, "fy": -26, "by": -36})],
		[1.6, Px.merge(WRITHE, {"lean": -2, "fy": -36, "by": -26})],
		[2.1, Px.merge(WRITHE, {"crouch": 5, "lean": 2, "fx": -8, "fy": -38, "bx": 9, "by": -38})],
		[3.6, Px.merge(WRITHE, {"crouch": 6, "lean": 2, "fx": -8, "fy": -36, "bx": 9, "by": -36})],
	],
}

const IGNITE := 0.15
const BURN := 1.9
static var CHAR := [Px.hex("#100908"), Px.hex("#22130e"), Px.hex("#3a2016")]
static func actorAlpha(_t: float, _o: Dictionary) -> float:
	return 0.0


var C: Array
var A: Array
var R: Px.Rng
var body: Lib.Body
var H: float
var cx := 0.0
var ps: Px.Particles
var lights: Px.Lights
var t := 0.0
var tongues: Array


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	A = Px.fit(o.ash, 3)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	body = Lib.bodyOf(o.actor, C)
	H = body.h
	# when each pixel catches: row by row from the feet, a ragged, licking front; the rim a beat early
	for b in body.list:
		b.key = (body.h - 1 - b.my) / H + 0.08 * (Px.rand(b.mx, b.my, 3) - 0.5) + 0.06 * Px.noise(b.mx * 0.35, 4) - (0.02 if b.edge else 0.0)
		b.gone = false
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[6], C[5], C[4], C[3]]})
	lights = Px.Lights.new()
	# tongues of flame along the seam, licking up the body still standing: layered, flickering, swaying
	tongues = Px.arr(6, func(i): return {"x": -9.0 + i * 3.6 + Px.rand(i, 1) * 1.5, "h": 6.0 + Px.rand(i, 2) * 6.0, "s": i * 13})


func front(tt: float) -> float:
	return -0.04 + 1.1 * Px.Ease.inOutSine(Px.clamp((tt - IGNITE) / BURN))


# a life that ends before the effect does
func left(a: float, b: float) -> float:
	return maxf(0.05, minf(R.range(a, b), meta.duration - 0.1 - t))


func tongue(p: Px.Painter, x: float, y: float, h: float, n: int) -> void:
	for L in [[1.0, 1.0, C[3]], [0.7, 0.8, C[4]], [0.45, 0.6, C[5]], [0.25, 0.35, C[6]]]:
		var lw: float = L[0]
		var lh: float = L[1]
		var c: int = L[2]
		var Hh := h * lh
		var r := 0
		while r <= Hh:
			var u := r / maxf(1.0, Hh)
			var half := 1.8 * lw * pow(1.0 - u, 0.9) + Px.noise(t * 9.0 + r * 0.5, n) * 0.4
			var cxr := x + Px.noise(t * 4.0 + r * 0.25, n + 7) * u * 1.6
			if half < 0.3:
				r += 1
				continue
			var px := Px.round(cxr - half)
			while px <= Px.round(cxr + half):
				p.px(px, Px.round(y - r), c)
				px += 1.0
			r += 1


func update(dt: float) -> void:
	t += dt
	var f := front(t)
	for b in body.list:
		if b.gone or b.key >= f:
			continue
		b.gone = true
		# a burnt pixel goes to ash that sifts down, an ember that rises, or a lick of flame
		var r := R.next()
		if r < 0.2:
			# ash: low down it drops and settles, higher up it sifts down slowly (and is gone before the floor)
			if b.y > -7.0:
				ps.spawn(P.GRIT, b.x, b.y, R.range(-12.0, 12.0), R.range(-20.0, 0.0), left(0.6, 1.2), R.pick(A), 1.0)
			else:
				ps.spawn(P.FLAKE, b.x, b.y, R.range(-10.0, 10.0), R.range(-8.0, 4.0), left(0.5, minf(1.5, -b.y / 18.0)), R.pick(A), 1.4 if R.chance(0.2) else 1.0)
		elif r < 0.32:
			ps.spawn(P.EMBER, b.x, b.y, R.range(-12.0, 12.0), -R.range(15.0, 45.0), left(0.6, 1.4), C[5], R.range(1.0, 1.6))
		elif r < 0.46:
			ps.spawn(P.FIRE, b.x, b.y, R.range(-6.0, 6.0), -R.range(14.0, 30.0), R.range(0.2, 0.42), 0, R.range(1.2, 2.2), 0.0, PF.SMOKES if R.chance(0.5) else 0)
		elif r < 0.5:
			ps.spawn(P.SMOKE, b.x, b.y - 2.0, R.range(-5.0, 5.0), -R.range(14.0, 26.0), left(1.2, 2.0), Px.mix(A[1], C[1], 0.3), R.range(2.0, 3.4))
	# the feet catch with a spit of sparks and a puff of light
	if t >= IGNITE and t - dt < IGNITE:
		lights.add(0.0, -4.0, 34.0, C[4], 0.8, 0.4)
		for i in 10:
			ps.spawn(P.SPARK, R.range(-8.0, 8.0), -1.0, R.range(-80.0, 80.0), -R.range(40.0, 150.0), R.range(0.2, 0.5))
	# while it burns: steady embers and smoke off the front
	if f > 0.0 and f < 1.02:
		var fy := body.y + (1.0 - Px.clamp(f)) * H
		if R.chance(0.34):
			ps.spawn(P.SMOKE, R.range(-7.0, 7.0), fy - 5.0, R.range(-6.0, 6.0), -R.range(16.0, 30.0), left(1.4, 2.4), Px.mix(A[1], C[3], 0.35), R.range(2.6, 4.2))
		if R.chance(0.5):
			ps.spawn(P.FIRE, R.range(-9.0, 9.0), fy, R.range(-6.0, 6.0), -R.range(18.0, 34.0), R.range(0.18, 0.36), 0, R.range(1.2, 2.4), 0.0, PF.SMOKES if R.chance(0.35) else 0)
		if R.chance(0.15):
			ps.spawn(P.EMBER, R.range(-9.0, 9.0), fy, R.range(-15.0, 15.0), -R.range(30.0, 70.0), left(0.8, 1.6), C[5], 1.4)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# warm light on the floor while the body burns down to it
	var k := Px.smooth(0.0, IGNITE + 0.2, t) * (1.0 - Px.smooth(IGNITE + BURN * 0.6, IGNITE + BURN + 0.4, t))
	if k > 0.0:
		p.glow(0.0, -1.0, 30.0, C[4], 0.3 * k)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var f := front(t)
	var fr := floori(t * 30.0)
	for b in body.list:
		if b.gone:
			continue
		var d: float = b.key - f
		var c: int
		# the seam: white-hot at the very edge, flickering through yellow and orange
		if d < 0.025:
			c = WHITE if Px.rand(b.mx, b.my, fr) < 0.35 else C[6]
		elif d < 0.05:
			c = C[5] if Px.rand(b.mx, b.my, fr + 7) < 0.5 else C[4]
		# just above it the body is charred, with live sparks in the char
		elif d < 0.11:
			c = C[3] if (Px.rand(b.mx, b.my, 13) < 0.15 and Px.rand(b.mx, fr, 2) < 0.6) else CHAR[0 if d < 0.075 else 1]
		elif d < 0.16:
			c = Px.mix(b.c, CHAR[2], 0.6)
		# above that the heat browns it
		elif d < 0.26:
			c = Px.mix(b.c, C[2], 0.18)
		else:
			c = b.c
		p.px(b.x, b.y, c)
	# light along the seam, and flames licking up from it while there's body left to burn
	if f > -0.02 and f < 1.05:
		var fy := body.y + (1.0 - Px.clamp(f)) * H
		var k := 1.0 - Px.smooth(0.95, 1.05, f)
		for g in tongues:
			var row := Px.roundi(fy - body.y)
			var mx := Px.roundi(g.x - body.x)
			if not body.on(mx, int(minf(H - 1.0, maxf(0.0, row)))):
				continue
			var h: float = g.h * k * (0.6 + 0.6 * (Px.noise(t * 2.6 + g.s, g.s) * 0.5 + 0.5)) * Px.smooth(-0.02, 0.06, f)
			if h >= 1.0:
				tongue(p, g.x, fy + 1.0, h, g.s)
		var fl := 0.85 + 0.15 * Px.noise(t * 11.0, 9)
		p.glowLine(-11.0, fy, 11.0, fy, 9.0, C[4], 0.45 * k)
		p.glow(0.0, fy - 6.0, 56.0, C[4], 0.38 * k * fl)
		p.glow(0.0, fy - 2.0, 18.0, C[5], 0.28 * k * fl)
	ps.draw(p, "front")
	lights.draw(p)
