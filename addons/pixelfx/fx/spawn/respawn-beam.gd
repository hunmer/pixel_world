# The beam's slam, strands, rings and the sparks thrown along the floor are adapted from Sprite Fusion's
# open-source holy-light (https://www.spritefusion.com/pixel-art-vfx/holy-light), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/spawn/respawn-beam.js@038aa83e07da2aa3f1b801a9f2682307f2c73998
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Respawn beam",
	"desc": "A guide line drops, a pillar of light slams onto the spot, and a scan bar climbs from the feet writing the character back in row by row, white-hot lines cooling to its colors.",
	"tags": ["spawn", "respawn", "beam", "teleport", "scanline", "light", "one-shot"],
	"size": [128, 150],
	"origin": [64, 136],
	"duration": 2.5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#061e1b", "#0c3e36", "#136a5a", "#1f9c80", "#45d1a8", "#a8f5d8", "#ffffff"],
		"width": 15,
		"seed": 12,
	},
}

static var SET := {"turn": 1, "crouch": 4, "fx": -9, "fy": -14, "bx": 10, "by": -14, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"follow": 0,
	"poses": [
		[0, SET],
		[1.4, SET],
		[1.72, {"turn": 1.15, "crouch": -1, "fx": -13, "fy": -36, "bx": 14, "by": -36, "hy": -1, "ffx": -3, "fbx": 4}],
		[2.1, Px.READY],
		[2.5, Px.READY],
	],
}

const SLAM := 0.32
const WRITE0 := SLAM + 0.08
const WRITE := 0.95
const DONE := WRITE0 + WRITE
const LIFT := DONE + 0.12
static func actorAlpha(t: float, _o: Dictionary) -> float:
	return 0.0 if t < DONE + 0.04 else 1.0


const TOPY := -136.0
const DROP := 0.07

var C: Array
var R: Px.Rng
var BW: float
var body: Lib.Body
var rim: Array
var top: float
var H: float
var ps: Px.Particles
var lights: Px.Lights
var strands: Array
var t := 0.0
var slammed := false
var finished := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	BW = o.width
	body = Lib.bodyOf(o.actor, C)
	rim = Lib.rimOf(body)
	top = body.y
	H = body.h
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [WHITE, C[5], C[4], C[3]]})
	lights = Px.Lights.new()
	# strands of brighter light running down the beam, each at its own offset and shimmer
	strands = Px.arr(6, func(i): return {"o": Px.rand(i, 1) * 1.6 - 0.8, "f": 1.0 + Px.rand(i, 2) * 3.0, "w": Px.rand(i, 3)})


# the scan bar: where it is (local y), climbing from the feet to the crown
func scanY(tt: float) -> float:
	return -Px.Ease.inOutSine(Px.clamp((tt - WRITE0) / WRITE)) * (H + 2.0)


# when each row is written, and its glitch: some rows jump sideways for a frame or two as they land
func rowT(my: float) -> float:
	return WRITE0 + (WRITE * acos(1.0 - 2.0 * Px.clamp((H - my) / (H + 2.0)))) / PI


func width(tt: float) -> float:
	return 0.0 if tt < SLAM - DROP else (BW * 0.6 if tt < SLAM else (BW * (1.0 + 0.4 * Px.exp(-(tt - SLAM) * 10.0)) * (0.92 + 0.08 * sin(tt * 40.0)) if tt < LIFT else BW * (1.0 - Px.Ease.outCubic(Px.clamp((tt - LIFT) / 0.3)))))


# the beam lifts away bottom first once the character is written
func bottom(tt: float) -> float:
	return 0.0 if tt < LIFT else -150.0 * Px.Ease.inCubic(Px.clamp((tt - LIFT) / 0.4))


func update(dt: float) -> void:
	t += dt
	# the guide: motes drawn in to the spot along the floor
	if t < SLAM and R.chance(0.5):
		var s := R.sign()
		var D := R.range(18.0, 40.0)
		var T := R.range(0.15, 0.25)
		var v := (D * 3.0) / (Px.exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, s * D, -R.range(0.0, 3.0), -s * v, 0.0, T, C[5] if R.chance(0.5) else C[4])
	if not slammed and t >= SLAM:
		slammed = true
		lights.add(0.0, -28.0, 64.0, C[4], 1.0, 0.5)
		lights.add(0.0, -52.0, 80.0, C[5], 1.1, 0.4)
		lights.add(0.0, -9.0, 24.0, WHITE, 0.9, 0.12)
		for i in 40:
			var s := R.sign()
			var sp := R.range(60.0, 135.0)
			ps.spawn(P.SPARK, s * R.range(0.0, 6.0), -1.0, s * sp, -R.range(20.0, 140.0), R.range(0.25, 0.7))
		for i in 12:
			ps.spawn(P.STAR, R.range(-BW, BW), -R.range(2.0, 40.0), R.range(-20.0, 20.0), -R.range(20.0, 70.0), R.range(0.5, 1.0), R.pick([WHITE, C[5]]), R.range(0.8, 1.8))
		for i in 8:
			var s := R.sign()
			ps.spawn(P.DUST, s * R.range(4.0, 10.0), -1.0, s * R.range(30.0, 80.0), -R.range(3.0, 10.0), R.range(0.4, 0.7), C[2], R.range(1.5, 3.0))
	# the scan bar spits sparks sideways as it climbs
	if t > WRITE0 and t < DONE and R.chance(0.45):
		var y := scanY(t)
		var s := R.sign()
		ps.spawn(P.SPARK, s * R.range(6.0, 11.0), y, s * R.range(40.0, 140.0), R.range(-60.0, 10.0), R.range(0.15, 0.35))
	# motes rise inside the beam while it stands
	if t > SLAM and t < LIFT + 0.2 and R.chance(0.6):
		ps.spawn(P.STAR, R.range(-1.3, 1.3) * BW, -R.range(0.0, 90.0), R.range(-6.0, 6.0), -R.range(30.0, 90.0), R.range(0.4, 0.9), R.pick([WHITE, C[5], C[5], C[4]]), R.range(1.0, 1.8) if R.chance(0.3) else 0.6)
	if not finished and t >= DONE:
		finished = true
		lights.add(0.0, top + H / 2.0, 40.0, C[5], 0.7, 0.3)
		for i in 14:
			var c: Dictionary = R.pick(rim)
			ps.spawn(P.STAR, c.x, c.y, R.range(-25.0, 25.0), -R.range(10.0, 50.0), R.range(0.4, 0.9), R.pick([WHITE, C[5]]), R.range(0.8, 1.8))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var w := width(t)
	var b := bottom(t)
	# the guide line before the slam, a marker on the floor
	if t < SLAM:
		var k := Px.smooth(0.0, SLAM * 0.7, t) * (1.0 - Px.smooth(SLAM - DROP, SLAM, t) * 0.5)
		var y := TOPY
		while y < -1.0:
			p.dot(0.0, y + int(t * 60.0) % 2, C[5], k * (0.35 + 0.65 * ((y - TOPY) / -TOPY)))
			y += 2.0
		Px.band(p, 0.0, 0.0, 10.0 - 4.0 * k, 0.2, 1.0, k, C, func(g: float) -> bool: return sin(g) < 0.0)
		p.glow(0.0, -2.0, 16.0, C[4], 0.4 * k)
	if w <= 0.2:
		return
	# the beam: a see-through column, hard bright edges, shimmering strands; its light hugs the edges so
	# whatever it writes inside stays readable
	var yEnd := TOPY + (-1.0 - TOPY) * Px.Ease.inCubic(Px.clamp((t - SLAM + DROP) / DROP)) if t < SLAM else -1.0 + b
	var writing := Px.smooth(WRITE0 - 0.05, WRITE0 + 0.1, t) * (1.0 - Px.smooth(DONE, LIFT, t))
	var fill := 0.2 - 0.1 * writing
	var y := TOPY
	while y <= yEnd:
		for x in range(floori(-w), ceili(w) + 1):
			var q := absf((x + 0.5) / w)
			if q > 1.0:
				continue
			if q > 0.86:
				p.dot(x, y, WHITE if (q > 0.94 and Px.rand(x, y, int(t * 30.0)) < 0.7) else C[5], 1.0)
				continue
			var core := 1.0 - Px.smooth(SLAM + 0.06, WRITE0 + 0.08, t)
			if q < 0.7 * core:
				# the white-hot core, with strands of colour running down it
				var hot := q < 0.35 * core
				for s in strands:
					if absf((x + 0.5) / w - s.o * 0.6 - 0.05 * sin(t * s.f * 3.0 + y * 0.05)) < 0.04:
						hot = false
				p.px(x, y, WHITE if hot else (C[6] if q < 0.5 * core else C[5]))
				continue
			var a := fill * (1.2 - q)
			var c: int = C[4]
			for s in strands:
				if absf((x + 0.5) / w - s.o - 0.06 * sin(t * s.f + s.o * 7.0)) < 0.045 + 0.03 * s.w:
					a = 0.55 - 0.25 * writing
					c = C[5]
			p.blend(x, y, c, a)
		y += 1.0
	if yEnd > TOPY + 24.0:
		for s in [-1.0, 1.0]:
			p.glowLine(s * w, TOPY + 24.0, s * w, yEnd, 6.0, C[4], 0.3)
	p.glow(0.0, -5.0, w * 1.5 + 6.0, C[5], 0.45)


func draw(p: Px.Painter) -> void:
	var w := width(t)
	var sk := (t - SLAM) / 0.45
	if sk > 0.0 and sk < 1.0:
		var rx := 14.0 + 18.0 * Px.Ease.outCubic(sk)
		var ry := 3.0 + 1.5 * sk
		p.ellipse(0.0, 0.5, rx, ry, func(d): return WHITE if d < 0.4 else (C[6] if d < 0.7 else C[5]), func(d): return (1.0 - sk) * 1.4 * (1.0 - d * d))
		p.glow(0.0, -2.0, rx * 1.3, C[5], 0.5 * (1.0 - sk))
	# the floor: a hot spot and rings at the slam
	for i in 2:
		var k := (t - SLAM - 0.08 * i) / 0.5
		if k > 0.0 and k < 1.0:
			Px.band(p, 0.0, 0.0, 8.0 + (22.0 if i else 34.0) * Px.Ease.outCubic(k), 0.2, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, C, func(_g): return true, k < 0.15)
	# the character, written in from the feet: each row lands white, then cools to its own colors
	if t >= WRITE0 and t < DONE + 0.05:
		var sy := scanY(t)
		var fr := floori(t * 30.0)
		for b in body.list:
			var t0 := rowT(b.my)
			var age := t - t0
			if age < 0.0:
				continue
			var glitch := ((-2.0 if Px.rand(b.my, fr, 4) < 0.5 else 2.0) if (age < 0.12 and Px.rand(b.my, fr, 9) < 0.3) else 0.0)
			var c: int = WHITE if age < 0.05 else (C[5] if age < 0.14 else (Px.mix(b.c, C[5], 0.5 * (1.0 - (age - 0.14) / 0.16)) if age < 0.3 else b.c))
			p.px(b.x + glitch, b.y, C[6] if (b.edge and age < 0.3) else c)
		# the scan bar itself: a bright line across the beam and a light riding it
		if t < DONE:
			p.line(-w - 2.0, sy, w + 2.0, sy, func(u): return WHITE if absf(u - 0.5) < 0.35 else C[5])
			p.line(-w, sy + 1.0, w, sy + 1.0, C[4], 0.6)
			p.glowLine(-w, sy, w, sy, 6.0, C[5], 0.6)
	# done: a flash round the finished character
	var fk := (t - DONE) / 0.25
	if fk > 0.0 and fk < 1.0:
		for c in rim:
			p.dot(c.x, c.y, WHITE if fk < 0.4 else C[5], 1.2 - fk)
		Px.sparkle(p, 6.0, top + 6.0, Px.round(6.0 * (1.0 - fk)), WHITE, C[5], 0.5)
	# the beam's front edges over the character while it stands
	if w > 0.2:
		var _yEnd := TOPY + (-1.0 - TOPY) * Px.Ease.inCubic(Px.clamp((t - SLAM + DROP) / DROP)) if t < SLAM else -1.0 + bottom(t)
		if t >= SLAM and t - SLAM < 0.1:
			p.glow(0.0, -30.0, 56.0, WHITE, 0.6 * (1.0 - (t - SLAM) / 0.1))
	ps.draw(p)
	lights.draw(p)
