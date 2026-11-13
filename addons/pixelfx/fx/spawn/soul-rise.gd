# The pale ghost of the body and the motes it sheds follow Sprite Fusion's open-source movement and heal
# (https://www.spritefusion.com/pixel-art-vfx/movement), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/spawn/soul-rise.js@9521e7525defda730f201405173d38754923cd41
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Soul rise",
	"desc": "The body's outline flares and dims, then a pale glowing copy of it lifts out, stretching as its legs melt into a rippling wisp, shedding motes until it thins into light.",
	"tags": ["spawn", "death", "soul", "ghost", "spirit", "rise", "light", "one-shot"],
	"size": [96, 140],
	"origin": [48, 126],
	"duration": 3.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#101a33", "#1f3563", "#35609e", "#5c96d4", "#94c8f0", "#d2f0ff", "#ffffff"],
		"height": 50,
		"seed": 27,
	},
}

static var SLUMP := {"crouch": 8, "lean": 6, "hy": 2, "fx": 7, "fy": -9, "bx": 11, "by": -9, "ffx": 9, "fbx": -8}
static var act := {
	"onBody": true,
	"follow": 0,
	"poses": [
		[-0.2, Px.READY],
		[0.3, {"turn": 1, "crouch": 2, "hy": -1, "fx": -10, "fy": -24, "bx": 11, "by": -24, "ffx": -3, "fbx": 4}],
		[0.7, {"turn": 0.7, "crouch": 4, "lean": 3, "hy": 1, "fx": 2, "fy": -14, "bx": 8, "by": -14, "ffx": 4, "fbx": -3}],
		[1.1, SLUMP],
		[2.7, SLUMP],
		[3.2, Px.merge(SLUMP, {"crouch": 7})],
	],
	"dust": [{"t": 1.1, "x": 0, "n": 5}],
}

const LEAVE := 0.35
const TOP := 2.05
const GONE := 2.55
static var SHADOW := Px.hex("#0c0f1e")

var C: Array
var R: Px.Rng
var body: Lib.Body
var rim: Array
var W: int
var Hh: int
var waist: int
var tone: Array
var toneAt: PackedInt32Array
var ps: Px.Particles
var lights: Px.Lights
var height: float
var t := 0.0
var left := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	height = o.height
	body = Lib.bodyOf(o.actor, C)
	rim = Lib.rimOf(body)
	W = body.w
	Hh = body.h
	waist = Px.roundi(Hh * 0.6)
	# the soul is the body's own picture in pale light: each pixel's brightness picks a step of the ramp
	tone = body.list.map(func(b): return 6 if b.edge else 3 + mini(2, floori(Px.luma(b.c) * 3.6)))
	toneAt = PackedInt32Array()
	toneAt.resize(W * Hh)
	toneAt.fill(-1)
	for i in body.list.size():
		var b: Dictionary = body.list[i]
		toneAt[b.my * W + b.mx] = tone[i]
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [WHITE, C[5], C[4], C[3]]})
	lights = Px.Lights.new()


# where the soul is: lifted, stretched taller and thinner, swaying; legs melt into a wisp below the waist
func lift() -> float:
	return height * Px.Ease.inOutSine(Px.clamp((t - LEAVE) / (TOP - LEAVE)))

func stretch() -> float:
	return 1.0 + 0.22 * Px.Ease.inOutSine(Px.clamp((t - LEAVE) / (TOP - LEAVE)))

func sway(row: float) -> float:
	return sin(t * 3.0 - row * 0.12) * 2.2 * Px.smooth(LEAVE, LEAVE + 0.5, t)

func melt() -> float:
	return Px.smooth(LEAVE + 0.1, LEAVE + 0.9, t)

# it thins from the bottom up once it's high
func thin() -> float:
	return Px.smooth(TOP - 0.25, GONE, t)


# a ring of light across the floor as it tears loose: far half behind the body, near half in front
func ring(p: Px.Painter, near: bool) -> void:
	var k := (t - LEAVE) / 0.5
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.0, 6.0 + 26.0 * Px.Ease.outCubic(k), 0.18, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, C, func(g: float) -> bool: return (sin(g) >= 0.0) == near, k < 0.12)


func update(dt: float) -> void:
	t += dt
	if not left and t >= LEAVE:
		left = true
		lights.add(0.0, -20.0, 50.0, C[4], 0.85, 0.55)
		lights.add(0.0, -20.0, 24.0, WHITE, 0.8, 0.12)
		for i in 10:
			var c: Dictionary = R.pick(rim)
			ps.spawn(P.STAR, c.x, c.y, R.range(-20.0, 20.0), -R.range(20.0, 60.0), R.range(0.4, 0.8), R.pick([WHITE, C[5]]), R.range(0.8, 1.8))
	# motes come off its edges as it rises, and pour off it as it thins
	if t > LEAVE and t < GONE:
		var s := stretch()
		var y0 := body.y * s - lift()
		var th := thin()
		for n in (3 if th > 0.0 else 1):
			if not R.chance(0.9 if th > 0.0 else 0.5):
				continue
			var c: Dictionary = R.pick(rim)
			var row: int = c.my
			if row / float(Hh) < 1.0 - th * 1.1 - 0.05 and th > 0.0:
				continue
			var x: float = c.x * (1.0 - 0.12 * (s - 1.0) * 4.0) + sway(row)
			var y: float = y0 + c.my * s
			# nothing outlives the effect, and nothing climbs off the top
			var life := minf(minf(R.range(0.5, 1.1), meta.duration - 0.1 - t), (y + 120.0) / 60.0)
			if life > 0.1:
				ps.spawn(P.MOTE if R.chance(0.7) else P.STAR, x, y, R.range(-12.0, 12.0), -R.range(25.0, 60.0), life, R.pick([WHITE, C[5], C[5], C[4]]), R.range(0.5, 1.0))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# a pale pool on the floor while it leaves, and a ring from the moment it tears loose
	var k := Px.smooth(0.0, LEAVE, t) * (1.0 - Px.smooth(LEAVE + 0.4, TOP, t))
	if k > 0.0:
		p.glow(0.0, -1.0, 26.0, C[4], 0.3 * k)
	ring(p, false)


func draw(p: Px.Painter) -> void:
	# the body: its outline flares as the soul tears loose, then the body is left dimmed
	if t < LEAVE + 0.3:
		var k := t / LEAVE if t < LEAVE else 1.0 - (t - LEAVE) / 0.3
		for c in rim:
			if Px.rand(c.mx, c.my, floori(t * 30.0)) < 0.25 + 0.7 * k:
				p.px(c.x, c.y, WHITE if k > 0.7 else C[5])
		p.glow(0.0, -19.0, 26.0, C[4], 0.45 * k)
	var dim := Px.smooth(LEAVE, LEAVE + 0.6, t) * (1.0 - Px.smooth(GONE, meta.duration - 0.1, t))
	if dim > 0.0:
		for b in body.list:
			p.blend(b.x, b.y, SHADOW, 0.45 * dim)
	ring(p, true)
	if t < LEAVE or t > GONE + 0.1:
		ps.draw(p)
		lights.draw(p)
		return
	# the soul, drawn backward from the screen so stretching leaves no holes; see-through, its rim solid
	var s := stretch()
	var L := lift()
	var m := melt()
	var th := thin()
	var top := body.y * s - L
	var sx := 1.0 - 0.12 * (s - 1.0) * 4.0
	var tail := Px.round(10.0 * m)
	var y1 := top + (Hh + tail) * s
	var fadeIn := Px.clamp((t - LEAVE) / 0.15)
	for y in range(floori(top), ceili(y1) + 1):
		var my := floori((y + 0.5 - top) / s)
		if my < 0:
			continue
		# rows below the waist pull in toward a wavy spine: legs melting into a wisp
		var k := (my - waist + 1) / (Hh - waist + tail) if my >= waist else 0.0
		var narrow := 1.0 - k * m * 0.95
		if narrow <= 0.05:
			continue
		var cx := sway(my) + sin(my * 0.7 - t * 8.0) * 2.0 * k * m
		var a := (1.0 - k * 0.45 if my >= waist else 1.0) * fadeIn
		for x in range(floori(cx - W / 2.0 - 4.0), ceili(cx + W / 2.0 + 4.0) + 1):
			var mx := floori((x + 0.5 - cx) / (sx * narrow) - body.x)
			# as it thins the lower rows go first, with a ragged edge
			if th > 0.0 and my / (Hh + tail) > 1.0 - th * 1.25 + 0.25 * Px.rand(mx, my, 5) - 0.1:
				continue
			var ti: int
			if my < Hh:
				if mx < 0 or mx >= W:
					continue
				ti = toneAt[my * W + mx]
				if ti < 0:
					continue
			else:
				# the wisp below the feet: a thin trail that tapers to nothing
				var w := (1.0 - (my - Hh) / maxf(1.0, tail)) * 3.2 * m
				var d := absf(x + 0.5 - cx)
				if d > w:
					continue
				ti = 5 if d > w - 1.0 else 4
			# the first frames it tears loose it is all white
			if t < LEAVE + 0.07:
				p.px(x, y, C[5] if ti >= 6 else WHITE)
			elif ti >= 5:
				p.dot(x, y, WHITE if ti >= 6 else C[5], minf(1.0, a * 1.3))
			else:
				p.blend(x, y, C[ti], a * 0.7)
	# its light
	var cy := top + Hh * s * 0.45
	p.glow(sway(10.0), cy, 30.0, C[4], 0.42 * fadeIn * (1.0 - th))
	p.glow(sway(10.0), cy - 6.0, 14.0, C[5], 0.3 * fadeIn * (1.0 - th))
	ps.draw(p)
	lights.draw(p)


static func actorAlpha(_t: float, _o: Dictionary) -> float:
	return 1.0
