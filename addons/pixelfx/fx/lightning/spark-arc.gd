# The arc's re-struck bowed shape, its halo-body-core inking, its flicker and the nodes where it roots follow
# Sprite Fusion's open-source lightning (https://www.spritefusion.com/pixel-art-vfx/lightning),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/spark-arc.js@d63414f17b7ff830758cec32cd3334a14989dd1b
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Spark arc",
	"desc": "A climbing arc between two rods: it strikes white at their narrow foot, climbs on rising heat as it stretches and bows, sputters and snaps at the top, then strikes again.",
	"tags": ["lightning", "electric", "arc", "jacobs-ladder", "machine", "prop", "loop"],
	"size": [124, 120],
	"origin": [62, 108],
	"duration": 2.0,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOLT, "sparks": Lib.PLASMA, "seed": 2},
}

const FPS := 30.0
const N := 60
const P := 2.0
const SNAP := 1.42
const H := 58.0
static var STEEL := Px.ramp(["#151823", "#262c3b", "#3d4558", "#5f6a82", "#8f9bb2", "#d2daea"])
static var CERAMIC := Px.ramp(["#4b4458", "#857d96", "#c9c1d6", "#efe9f6"])
static var ASH := Px.hex("#6a6478")
# the rods: a V from the insulators up; where the arc roots at height h above the gap
static func rodAt(s: float, h: float) -> Array:
	return [s * (4.5 + (h / 60.0) * 19.5), -9.0 - h]

static func height(t: float) -> float:
	return 1.5 + H * pow(Px.clamp(t / SNAP), 1.35)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var S := Px.ramp(o.sparks)
	var f := floori(t * FPS + 1e-6) % N
	var r := Px.rng(o.seed, 1, f)
	var climbing := t < SNAP
	var h := height(t)
	var u := Px.clamp(t / SNAP)
	var a := t - SNAP
	# the floor and the stand: a pool of cold light while it burns, a plate, two ribbed insulators
	p.glow(0.0, -14.0, 50.0, C[3], 0.2 + 0.15 * (1.0 - u) if climbing else 0.06)
	p.rect(-18.0, -3.0, 36.0, 3.0, STEEL[1])
	p.line(-18.0, -3.0, 17.0, -3.0, STEEL[3])
	for s in [-1, 1]:
		for y in range(-9, -3):
			var rib := (y & 1) == 0
			for x in range(2, 7):
				p.px(s * x - (1 if s < 0 else 0), y, (CERAMIC[3 if x < 4 else (2 if x < 6 else 1)]) if rib else CERAMIC[1 if x < 5 else 0])
	# the rods: steel, a lit edge, glowing where the arc has passed and cooling behind it
	for s in [-1, 1]:
		var hh := 0.0
		while hh <= 60.0:
			# when the arc passed this point; not yet this time round, it is still cooling from the last
			var xy := rodAt(s, hh)
			var x: float = xy[0]
			var y: float = xy[1]
			var tp := SNAP * pow(Px.clamp((hh - 1.5) / H), 1.0 / 1.35)
			var age := t - tp if t >= tp else t - tp + P
			var hot := 0.0 if hh > H + 2.0 else exp(-age / 0.26)
			var c := Lib.heat(hot * 1.05 - 0.12)
			p.px(x, y, c if c else (STEEL[4] if s < 0 else STEEL[3]))
			var h2 := Lib.heat(hot * 0.6) if (c and hot > 0.35) else 0
			p.px(x + s, y, (h2 if h2 else STEEL[2]) if (c and hot > 0.35) else (STEEL[2] if s < 0 else STEEL[1]))
			if hot > 0.3 and (Px.roundi(hh * 2.0) & 3) == 0:
				p.glow(x, y, 5.0, c if c else C[4], 0.25 * hot)
			hh += 0.5
		var txy := rodAt(s, 60.0)
		var tx: float = txy[0]
		var ty: float = txy[1]
		p.circle(tx + s * 0.5, ty, 1.6, STEEL[4])
		p.px(tx + s * 0.5 - 0.5, ty - 1.0, STEEL[5])
	# the arc: struck white at the foot, flickering as it climbs and stretches, sputtering at the top
	if climbing:
		var lxy := rodAt(-1.0, h)
		var rxy := rodAt(1.0, h)
		var xl: float = lxy[0]
		var yl: float = lxy[1]
		var xr: float = rxy[0]
		var yr: float = rxy[1]
		var k0 := 1.0 if t < 1.0 / FPS else 1.0 - 0.22 * u
		var sput := 0.4 if (u > 0.88 and r.next() < 0.25) else 1.0
		var k := k0 * sput * (0.82 + 0.18 * r.next())
		var bow := -(1.5 + 13.0 * u * u) * (0.8 + 0.4 * r.next())
		Lib.stroke(p, Lib.bowed(r, xl, yl, xr, yr, bow, 0.18 + 0.12 * u, 0.12 + 0.25 * u), k, C, 0.95 if t < 1.0 / FPS else 0.8, {"hero": t < 1.0 / FPS, "light": 0.7})
		p.glowLine(xl, yl + bow * 0.5, xr, yr + bow * 0.5, 12.0, C[4], 0.22 * k)
		for pt: Array in [[xl, yl], [xr, yr]]:
			var x: float = pt[0]
			var y: float = pt[1]
			p.circle(x, y, 1.8 + 0.6 * k, C[5])
			p.px(x, y, WHITE)
			p.glow(x, y, 12.0, C[5], 0.55 * k)
		if t < 0.1:
			p.glow(0.0, -11.0, 26.0, C[6], 0.45 * (1.0 - t / 0.1))
	elif a < 2.0 / FPS:
		# the snap: two stubs left clinging to the rods, a flash where it broke
		var lxy := rodAt(-1.0, H + 1.5)
		var rxy := rodAt(1.0, H + 1.5)
		var xl: float = lxy[0]
		var yl: float = lxy[1]
		var xr: float = rxy[0]
		var yr: float = rxy[1]
		for st: Array in [[xl, yl, 1.0], [xr, yr, -1.0]]:
			var x0: float = st[0]
			var y0: float = st[1]
			var s: float = st[2]
			Lib.crackle(p, Lib.zigzag(r, x0, y0, x0 + s * r.range(5.0, 9.0), y0 - r.range(2.0, 6.0), 0.4, 0.3), 0.7, C, 0.4)
		p.glow(0.0, yl - 8.0, 30.0, C[4], 0.5)
	elif t > P - 0.16:
		# anticipation: little sparks jump the narrow gap before it strikes again
		if r.next() < 0.7:
			Lib.crackle(p, Lib.zigzag(r, -4.5, -10.5 - r.range(0.0, 2.0), 4.5, -10.5 - r.range(0.0, 2.0), 0.5, 0.0), 0.4 + 0.3 * r.next(), C, 0.35)
	# ozone and smoke rise off the arc while it climbs, and from where it snapped
	for j in 3:
		var born := ((j + 1) / 3.2) * SNAP
		var age := Px.wrap(t - born, P)
		var life := 1.0
		if age >= life:
			continue
		var y0 := -9.0 - height(born) - 6.0
		Lib.puff(p, (3.0 if j % 2 else -3.0) + sin(age * 3.0 + j) * 2.0, y0 - age * 20.0, 1.8 + j * 0.3, age / life, Px.mix(ASH, C[5], 0.3))
	# sparks: thrown from the roots as it strikes, sprayed up where it snaps, molten drips off the rods
	burst(p, t, o, S, 0.0, 12, 11, func(q, j): return rodAt(1.0 if j % 2 else -1.0, 1.5) + [-PI / 2.0 + (0.6 if j % 2 else -0.6), 1.0, 60.0, 170.0])
	burst(p, t, o, S, SNAP, 14, 12, func(q, j): return [rodAt(1.0, H)[0] * q.range(-0.8, 0.8), -9.0 - H - 6.0, -PI / 2.0, 1.3, 50.0, 160.0])
	for ktt: Array in [[0, 0.45], [1, 0.8], [2, 1.15]]:
		var k: int = ktt[0]
		var tt: float = ktt[1]
		burst(p, t, o, S, tt, 2, 20 + k, func(q, j): return rodAt(1.0 if j % 2 else -1.0, height(tt)) + [PI / 2.0, 0.5, 5.0, 30.0])
	if climbing or a < 0.25:
		p.glow(0.0, -9.0 - h - 3.0, 26.0, C[4], 0.25 if climbing else 0.4 * (1.0 - a / 0.25))


static func burst(p: Px.Painter, t: float, o: Dictionary, S: Array, t0: float, n: int, salt: int, from: Callable) -> void:
	var age := Px.wrap(t - t0, P)
	for j in n:
		var q := Px.rng(o.seed, salt, j)
		var life := q.range(0.25, 0.6)
		if age >= life:
			continue
		var fr: Array = from.call(q, j)
		var x0: float = fr[0]
		var y0: float = fr[1]
		var a0: float = fr[2]
		var spread: float = fr[3]
		var sp0: float = fr[4]
		var sp1: float = fr[5]
		var ang := a0 + q.range(-spread, spread)
		var sp := q.range(sp0, sp1)
		var fl := Lib.flight(x0, y0, cos(ang) * sp, sin(ang) * sp, age, {"floor": 0.0})
		Lib.spark(p, fl[0], fl[1], fl[2], fl[3], 1.0 - age / life, S)
