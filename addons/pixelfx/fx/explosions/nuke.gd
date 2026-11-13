# The fire puffs, sparks and embers are adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/nuke.js@b06c5b836f1eab8d1a5c4cb7842223221ba1b0b8
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE

static var meta := {
	"name": "Nuke",
	"desc": "A blinding white frame, then a fireball lifts on a thin stem into a wide rolling cap that glows from inside; a white skirt flashes and a dust surge sweeps the floor.",
	"tags": ["explosion", "nuke", "mushroom", "cloud", "big", "ground", "one-shot"],
	"size": [400, 320],
	"origin": [200, 284],
	"duration": 9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#4a1712", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"], "dust": "#8a7466", "seed": 5},
}

const FLASH := 0.05
const LIFT := 0.07
const SKIRT := [0.55, 1.75]
# the cap's smoke: a lit crescent, two mid tones, a dark underside, the darkest hollow
static var CAP := Px.ramp(["#a0918c", "#7c6f6e", "#5f5458", "#40373f", "#271f27"])


var F: Array
var FR: Array
var R: Px.Rng
var dust: int
var DUST: Array
var W: int
var H: int
var OX: int
var OY: int
var X0: float
var X1: float
var Y0: float
var Y1: float
var ps: Px.Particles
var lights: Px.Lights
var plume: Lib.Plume
var column: Lib.Column
var veil: Array
var skirt: Array
var t := 0.0
var boomed := false


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 8)
	FR = Lib.fireRamp(F)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	dust = Px.hex(o.dust)
	DUST = [Px.mix(dust, WHITE, 0.22), dust, Px.mix(dust, Px.hex("#3a3040"), 0.35), Px.mix(dust, Px.hex("#2a2330"), 0.6), Px.mix(dust, Px.hex("#1c1720"), 0.8)]
	W = meta.size[0]
	H = meta.size[1]
	OX = meta.origin[0]
	OY = meta.origin[1]
	X0 = -OX + 3
	X1 = W - OX - 3
	Y0 = -OY + 3
	Y1 = H - OY - 3
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [F[6], F[5], F[3], F[2]]})
	lights = Px.Lights.new()
	# a wide, flat cap rolling like a torus: lobes go up the middle, out over the top and curl under at the rim
	plume = Lib.Plume.new(R, {
		"x": 0.0, "y": -26.0, "rise": 152.0, "tau": 1.7, "drift": 3.0, "tube": [14.0, 26.0], "ring": [4.0, 46.0], "grow": 1.6, "n": 50.0, "size": [9.5, 14.5], "swell": 0.45,
		"spin": 2.4, "spinTau": 2.4, "heat": 1.25, "cool": 0.42, "under": 0.6, "tilt": 0.16, "squash": 0.48, "fade": [6.0, 8.3], "spread": 26.0,
		"style": 1, "inner": true, "hollow": true, "fray": [4.0, 1.6, 6.4],
	})
	plume.onFray = func(x, y, r, ux, uy): ps.spawn(P.SMOKE, x, y, ux * R.range(10.0, 26.0), uy * R.range(4.0, 12.0) - R.range(2.0, 8.0), R.range(1.0, 1.7), CAP[R.int_(0, 1)], r * R.range(0.3, 0.45))
	# a thin stem that keeps feeding the cap, then breaks up from the bottom
	column = Lib.Column.new(R, {"w": 3.5, "foot": 22.0, "speed": 125.0, "size": [5.5, 7.0], "n": 84.0, "sway": 1.4, "style": 1})
	# the condensation skirt: a veil arching over the cap and a bell flaring round the stem
	veil = []
	for i in 72:
		veil.append({"a": -PI * ((i + R.range(0.2, 0.8)) / 72.0), "s": R.range(6.0, 10.0), "w": R.range(0.97, 1.06), "e": R.range(0.6, 1.3), "dx": R.range(-1.0, 1.0), "dy": R.range(-1.0, 0.2)})
	skirt = []
	for i in 110:
		skirt.append({"ph": R.range(0.0, TAU), "v": R.range(0.0, 1.0), "s": R.range(5.0, 9.0), "w": R.range(0.9, 1.06), "e": R.range(0.6, 1.3), "dx": R.range(-1.0, 1.0), "dy": R.range(-1.0, 0.4)})


func top() -> float:
	var S := plume.shape()
	return S.y + S.tube * 0.3


func boom() -> void:
	lights.add(0.0, -60.0, 150.0, F[4], 0.7, 1.6)
	# the fireball's first fire, sparks and embers
	for i in 26:
		var a := R.range(-PI, 0.0)
		var d := R.range(4.0, 22.0)
		var sp := R.range(40.0, 160.0)
		ps.spawn(P.FIRE, cos(a) * d, -26.0 + sin(a) * d, cos(a) * sp, sin(a) * sp * 0.7 - 30.0, R.range(0.6, 1.1), 0, R.range(7.0, 12.0), 0.0, (PF.SMOKES | PF.BIG) if R.chance(0.5) else 0)
	for i in 90:
		var a := R.range(-PI - 0.3, 0.3)
		var sp := R.range(200.0, 420.0)
		ps.spawn(P.SPARK, cos(a) * 18.0, -26.0 + sin(a) * 18.0, cos(a) * sp, sin(a) * sp - 60.0, R.range(0.3, 0.8))
	for i in 50:
		var a := R.range(-PI, 0.0)
		var sp := R.range(30.0, 140.0)
		ps.spawn(P.EMBER, cos(a) * 20.0, -26.0 + sin(a) * 20.0, cos(a) * sp, sin(a) * sp - 60.0, R.range(1.6, 3.4), F[3])
	# the base surge: dust thrown out along the floor in every direction, racing to the edges; a slower ring behind
	for i in 120:
		var slow := i >= 92
		var a := R.range(0.0, TAU)
		var c := cos(a)
		var s := sin(a)
		var sp := R.range(110.0, 200.0) if slow else R.range(240.0, 440.0)
		ps.spawn(P.SMOKE, c * 14.0, s * 14.0 * 0.16 - R.range(1.0, 3.0), c * sp, s * sp * (0.06 if s > 0.0 else 0.14) - R.range(0.0, 6.0 if slow else 3.0), R.range(1.8, 3.0), dust, R.range(8.0, 11.0) if slow else R.range(5.0, 9.0), R.range(0.05, 0.2))
	for i in 40:
		var u := R.range(-1.0, 1.0)
		var a := -PI / 2.0 + u * 0.7
		var sp := R.range(150.0, 380.0) * (1.0 - 0.4 * absf(u))
		ps.spawn(P.GRIT, u * 12.0, -1.0, cos(a) * sp, sin(a) * sp, R.range(1.2, 2.0), R.pick(DUST.slice(0, 3)), 2.0 if R.chance(0.4) else 1.0)


func update(dt: float) -> void:
	t += dt
	if not boomed and t >= LIFT:
		boomed = true
		boom()
	if t >= LIFT:
		plume.update(dt)
	var S := plume.shape()
	var hot := plume.hot()
	column.update(dt, top(), 1.0 if (t > 0.35 and t < 4.9) else 0.0)
	# afterwinds: dust drawn in along the floor and up the stem
	if t > 0.9 and t < 4.6 and R.chance(9.0 * dt):
		var s := R.sign()
		ps.spawn(P.VAPOUR, s * R.range(50.0, 160.0), -R.range(2.0, 6.0), -s * R.range(20.0, 45.0), -R.range(0.0, 6.0), R.range(1.2, 1.8), DUST[1], R.range(5.0, 8.0))
	if t > 0.3 and t < 3.4 and R.chance(14.0 * hot * dt):
		var a := R.range(0.0, TAU)
		ps.spawn(P.EMBER, S.x + cos(a) * (S.ring + S.tube), S.y + sin(a) * S.tube * 0.5, cos(a) * R.range(30.0, 80.0), -R.range(10.0, 50.0), R.range(1.4, 2.6), F[3])
	Lib.draft(ps, dt, {"x": 0.0, "top": S.y + S.tube * 0.3, "w": 9.0, "up": 160.0, "pull": 120.0, "low": 14.0, "reach": 170.0, "k": 1.0 - Px.smooth(4.4, 5.4, t)})
	ps.update(dt)
	Lib.cull(ps, X0, Y0, X1, Y1)
	Lib.fadeEdges(ps, X0, X1, 34.0, Y1)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	if t < FLASH:
		return
	var S := plume.shape()
	# the ground shock: a ring racing out along the floor ahead of the dust (far half)
	var k := (t - LIFT) / 0.8
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.5, 196.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 5.0 * (1.0 - k)), 1.15 - k, [DUST[2], DUST[0], F[5], F[7]], func(g): return sin(g) < 0.0)
	Lib.drawPs(p, ps, "back", FR)
	skirtDraw(p, t, S, veil, skirt, true)
	plume.draw(p, FR, CAP)
	# the dark hollow under the cap where the stem goes in, its heart still warm while the inside glows
	var E := plume.ember()
	var gone := Px.smooth(plume.o.fade[0], plume.o.fade[1] - 0.6, t - LIFT)
	if gone < 1.0:
		var hy: float = S.y + S.tube * 0.42
		var rx: float = S.ring * 0.7 + 5.0
		var ry: float = S.tube * 0.28 + 2.0
		Lib.haze(p, 0.0, hy, rx, ry, func(d: float): return Px.mix(CAP[4], FR[5 if d < 0.3 * E else 6], 0.75 * E) if d < 0.55 * E else CAP[4], func(d: float): return (0.8 if d < 0.6 else (0.5 if d < 0.85 else 0.22)) * (1.0 - gone))
	column.draw(p, top(), FR, DUST, Px.clamp(1.0 - t / 1.8), E * 0.8)
	skirtDraw(p, t, S, veil, skirt, false)
	Lib.pool(p, 0.0, 1.0, 140.0, 16.0, F[3], 0.3 * plume.hot())


func draw(p: Px.Painter) -> void:
	# the blinding frame: a white-hot core in a wash of white light that fades out before the canvas edges
	if t < FLASH:
		wash(p, OX, OY, W, H, 0.0, -40.0, WHITE, 1.6)
		p.circle(0.0, -40.0, 64.0, WHITE)
		return
	var k := (t - LIFT) / 0.8
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.5, 196.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 5.0 * (1.0 - k)), 1.15 - k, [DUST[2], DUST[0], F[5], F[7]], func(g): return sin(g) >= 0.0)
	# out of the white: a crisp white-hot sphere, cooling into the fireball
	var f := (t - FLASH) / 0.13
	if f < 1.0:
		var r := 22.0 + 8.0 * f
		p.circle(0.0, -26.0, r + 1.5, F[2])
		p.circle(0.0, -26.0, r, F[6] if f < 0.5 else F[5])
		p.circle(0.0, -26.0, r * 0.62, WHITE if f < 0.5 else F[6])
	Lib.drawPs(p, ps, "front", FR)
	# the shock in the air: a thin bright shell racing out from the fireball, cut off by the floor and the canvas
	var u := (t - FLASH) / 0.7
	if u < 1.0:
		var r := 30.0 + 250.0 * Px.Ease.outCubic(u)
		var cy := -26.0
		var out := func(a: float) -> bool: return cy + sin(a) * r > 0.0 or absf(cos(a) * r) > OX - 3 or cy + sin(a) * r < 3 - OY
		p.ring(0.0, cy, r, maxf(1.0, 2.5 * (1.0 - u)), WHITE if u < 0.3 else F[6], func(v: float, a: float): return 0.0 if out.call(a) else 1.1 - u)
		Lib.glowDome(p, 0.0, cy, r, 7.0, F[5], 0.3 * (1.0 - u), [3 - OX, 3 - OY, W - OX - 4, 0])
	# the light of it: everything washed white, falling away fast, then the fireball's own warm light
	var w := exp(-(t - FLASH) / 0.13)
	if w > 0.02:
		wash(p, OX, OY, W, H, 0.0, -40.0, WHITE, 0.9 * w)
	lights.draw(p)


# light over most of the canvas, brightest near (cx, cy), falling to nothing just inside the canvas edges so it
# never shows the canvas as a box
static func wash(p: Px.Painter, OX_: float, OY_: float, W_: float, H_: float, cx: float, cy: float, c: int, k: float) -> void:
	var rx := minf(OX_ + cx, W_ - OX_ - cx) - 4.0
	var up := OY_ + cy - 4.0
	var down := H_ - OY_ - cy - 4.0
	p.shade(-OX_, -OY_, W_ - OX_ - 1.0, H_ - OY_ - 1.0, func(x: float, y: float, out):
		var d := Px.hypot((x - cx) / rx, (y - cy) / (up if y < cy else down))
		out.l = c
		out.k = k * (1.0 - Px.smooth(0.0, 1.0, d)))


# the condensation skirt: a white veil that flashes over the cap and a bell that flares round the stem, edged with a
# crisp white rim, then evaporates into wisps that drift apart and thin; far half behind the cloud, near in front
static func skirtDraw(p: Px.Painter, tt: float, S: Dictionary, veil_: Array, skirt_: Array, back: bool) -> void:
	var u: float = (tt - SKIRT[0]) / (SKIRT[1] - SKIRT[0])
	if u <= 0.0 or u >= 1.0:
		return
	var a := minf(1.0, u / 0.06) * pow(1.0 - u, 1.5) * 0.6
	var capR: float = (S.ring + S.tube) * 1.1
	var y0: float = S.y + S.tube * 0.3
	var y1: float = S.y * 0.55
	if not back:
		for q in veil_:
			var ev: float = u * u * q.e
			var R: float = capR * q.w * (1.0 + ev * 0.2)
			p.disc(cos(q.a) * R + q.dx * ev * 10.0, S.y + sin(q.a) * (S.tube * 1.15 + 6.0) * q.w + q.dy * ev * 8.0, q.s * (1.0 - 0.5 * u), WHITE, a * 0.38)
	for q in skirt_:
		var z: float = sin(q.ph)
		if (z < 0.0) != back:
			continue
		var R: float = Px.lerp(capR * 0.82, 13.0, pow(q.v, 0.6)) * q.w
		var ev: float = u * u * q.e
		var x: float = cos(q.ph) * R * (1.0 + ev * 0.25) + q.dx * ev * 10.0
		var y: float = Px.lerp(y0, y1, q.v) + z * R * 0.18 + q.dy * ev * 8.0
		p.disc(x, y, q.s * (1.0 - 0.55 * u), WHITE, a * (0.3 if back else 0.55) * (1.0 - q.v * 0.3))
	# the bell's crisp lower edge, dithering away as it evaporates
	if u < 0.7:
		var R := 13.0 * 1.25
		var k := 1.0 - u / 0.7
		for i in 64:
			var g := (i / 64.0) * TAU
			var z := sin(g)
			if (z < 0.0) != back:
				continue
			p.dot(cos(g) * R * (1.0 + u * 0.6), y1 + 2.0 + z * R * 0.22, WHITE, k * (0.6 if back else 1.0))
