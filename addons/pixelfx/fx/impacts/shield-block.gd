# Mapping a lattice onto a dome by longitude and latitude, the ripple measured over its surface, the rim light
# and the glancing sparks are adapted from Sprite Fusion's open-source shield
# (https://www.spritefusion.com/pixel-art-vfx/shield), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/impacts/shield-block.js@ff7cda3a61304a52d9b6ade8b6a45da95e28d9ab
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Shield block",
	"desc": "A blow is caught on a half-dome of energy in front of the character: its diamond lattice flashes, a ripple runs over it, sparks glance off, then it blinks out cell by cell.",
	"tags": ["impact", "block", "shield", "barrier", "energy", "ripple", "actor", "one-shot"],
	"size": [148, 104],
	"origin": [40, 88],
	"duration": 1.1,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"seed": 12,
	},
}

static var BRACE := Px.merge(Px.READY, {"crouch": 4, "lean": 2, "fx": 13, "fy": -28, "bx": 6, "by": -21, "ffx": 9, "fbx": -9})
static var act := {
	"poses": [
		[-0.36, Px.READY],
		[-0.1, BRACE],
		[0, Px.merge(BRACE, {"x": -3, "crouch": 6, "lean": -2, "fx": 10, "fy": -26}), "snap"],
		[0.18, Px.merge(BRACE, {"x": -4, "crouch": 5, "lean": 0})],
		[0.65, Px.merge(BRACE, {"x": -3})],
		[1.1, Px.merge(Px.READY, {"x": 0})],
	],
	"hits": [{"t": 0.005, "stop": 0.09, "shake": 0.2, "amp": 2}],
	"dust": [{"t": 0.01, "x": -10, "n": 6, "dir": -1}],
}

# the dome's flat face, its depth and height, lattice density
const CX := 3.0
const RX := 28.0
const RY := 44.0
const GRID := 3.4
# where the blow lands; when the dome starts to blink out
const HIT := {"lon": 1.18, "lat": 0.5}
const GONE := 0.5


# a point on the dome's surface (lon round from facing us, lat up from the floor) to local space
static func onDome(lon: float, lat: float) -> Array:
	return [CX + RX * cos(lat) * sin(lon), -RY * sin(lat)]


var C: Array
var S: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var hx: float
var hy: float
var sp: Array
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	S = Px.fit(o.sparks, 4)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": S})
	lights = Px.Lights.new()
	var hxy := onDome(HIT.lon, HIT.lat)
	hx = hxy[0]
	hy = hxy[1]
	sp = Lib.spikes(R, 8, 0.2, {"len": [5.0, 8.0], "w": [1.4, 1.9], "fwd": 1.2, "back": 0.3})

	lights.add(hx, hy, 40.0, S[1], 0.7, 0.2)
	lights.add(hx, hy, 12.0, WHITE, 0.7, 0.06)
	# sparks glance off the dome: out and along its surface, mostly upward
	var nA := atan2(-sin(HIT.lat) / RY, (cos(HIT.lat) * sin(HIT.lon)) / RX) # the outward normal, roughly
	for i in 14:
		var a := nA + R.range(-1.2, 0.9)
		var v := R.range(130.0, 300.0)
		ps.spawn(P.SPARK, hx + 1.0, hy, cos(a) * v, sin(a) * v - 30.0, R.range(0.15, 0.42), WHITE, 1.0, R.range(0.01, 0.04) if i > 10 else 0.0)


# the dome, front (back = false) or the far side seen through it (back = true): a glassy fill, a diamond
# lattice, a bright rim where it turns away, a sheen sweeping up it
func dome(p: Px.Painter, back: bool) -> void:
	var fade := 1.0 - Px.smooth(GONE + 0.35, GONE + 0.55, t)
	if fade <= 0.0:
		return
	var y := -RY - 1.0
	while y < 0.0:
		var x := CX
		while x <= CX + RX + 1.0:
			var u := (x + 0.5 - CX) / RX
			var v := -(y + 0.5) / RY
			var q := u * u + v * v
			if q > 1.0 or u < 0.0 or v < 0.0:
				x += 1.0
				continue
			var z := sqrt(1.0 - q) * (-1.0 if back else 1.0)
			var lon := atan2(u, z)
			var lat := asin(Px.clamp(v))
			# the lattice, and which cell this is: each cell keeps its own clock for blinking out
			var a := (lon + lat) * GRID
			var b := (lon - lat) * GRID
			var fa := a - floorf(a)
			var fb := b - floorf(b)
			var cell := Px.rand(floorf(a), floorf(b), 31)
			var line := minf(minf(fa, 1.0 - fa), minf(fb, 1.0 - fb)) < 0.13
			var gone := GONE + cell * 0.35
			if t > gone:
				x += 1.0
				continue
			# how far over the surface from the blow, and the two ripples running out from it
			var d := acos(Px.clamp(cos(lat) * cos(HIT.lat) * cos(lon - HIT.lon) + sin(lat) * sin(HIT.lat), -1.0, 1.0))
			var hit := 0.0
			for tk: Array in [[0.0, 1.0], [0.12, 0.55]]:
				var t0: float = tk[0]
				var k0: float = tk[1]
				var k := t - t0
				var front := k * 3.6
				if k < 0.0 or k > 0.55:
					continue
				if absf(d - front) < 0.2:
					hit = maxf(hit, k0 * (1.0 - k / 0.55))
				elif d < front:
					hit = maxf(hit, 0.3 * k0 * (1.0 - k / 0.55))
			var rim := 1.0 - absf(z)
			var flash := t < 0.05
			var blink := t > gone - 0.06
			var sheen := absf(fmod(fmod(lat * 0.8 - lon * 0.3 - t * 1.6, 1.0) + 1.0, 1.0) - 0.5) < 0.05
			if back:
				if line:
					p.dot(x, y, C[3], 0.5 * fade)
				x += 1.0
				continue
			if q > 0.9:
				p.dot(x, y, WHITE if (flash or hit > 0.5) else C[6], fade)
			elif line:
				p.dot(x, y, WHITE if (flash or blink or hit > 0.5) else (C[6] if (hit > 0.2 or sheen) else (C[5] if rim > 0.7 else (C[4] if rim > 0.35 else C[3]))), fade)
			else:
				p.blend(x, y, C[6] if (flash or hit > 0.35) else C[3], fade * minf(0.85, (0.35 if flash else 0.1 + 0.25 * rim * rim) + hit * 0.65))
			if (int(x * 7.0 + y * 3.0) & 15) == 0:
				p.light(x, y, C[4], 0.15 + 0.5 * hit)
			x += 1.0
		y += 1.0


func update(dt: float) -> void:
	t += dt
	# as cells blink out, little motes of light lift off
	if t > GONE and t < GONE + 0.38 and R.chance(0.5):
		var lon := R.range(0.0, PI / 2.0)
		var lat := R.range(0.05, 1.4)
		var xy := onDome(lon, lat)
		ps.spawn(P.STAR, xy[0], xy[1], R.range(-10.0, 10.0), -R.range(10.0, 40.0), R.range(0.2, 0.36), C[6] if R.chance(0.5) else C[5], R.range(0.6, 1.4))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	dome(p, true)


func draw(p: Px.Painter) -> void:
	dome(p, false)
	# where the dome meets the floor
	var fade := 1.0 - Px.smooth(GONE + 0.3, GONE + 0.55, t)
	if fade > 0.0:
		var x := CX
		while x <= CX + RX:
			p.dot(x, 0.0, WHITE if t < 0.05 else C[5], fade * (0.6 + 0.4 * ((x - CX) / RX)))
			x += 1.0
	# the blow: a hot star where it lands, then the sparks glancing off
	if t < 0.03:
		Lib.star(p, hx, hy, sp, 1.0, 1.0, [S[3], S[0], S[1], WHITE], 1.0, 2.0)
	elif t < 0.06:
		Lib.star(p, hx, hy, sp, 1.25, 0.55, [S[3], S[1], S[2], S[0]], 1.0, 2.0)
	ps.draw(p)
	p.glow(CX + RX * 0.5, -RY * 0.45, RY * 0.9, C[4], 0.2 * (1.0 - Px.smooth(GONE, GONE + 0.55, t)) + 0.35 * exp(-t / 0.08))
	lights.draw(p)
