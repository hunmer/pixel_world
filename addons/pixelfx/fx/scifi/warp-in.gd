# The column (bands of the ramp across it, strands, pulses scrolling along it, a guide thread before it lands,
# rings riding it) is adapted from Sprite Fusion's open-source holy light
# (https://www.spritefusion.com/pixel-art-vfx/holy-light), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/scifi/warp-in.js@5c9ed185a8cebac8f1182f546db29c524f6fe28b
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Warp in",
	"desc": "A beam slams down, rings run down it and a scanline paints the hero in from head to toe, white-hot pixels cooling to their own colors; the beam pinches shut in sparks.",
	"tags": ["scifi", "teleport", "warp", "beam", "spawn", "arrive", "one-shot"],
	"size": [192, 168],
	"origin": [96, 128],
	"duration": 3,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#0b1030", "#152a63", "#1d4f9e", "#2582d2", "#36b9ee", "#8ae8ff", "#d4fbff", "#ffffff"], "width": 15, "seed": 3},
}

static var IN := {"crouch": 7, "lean": 3, "fx": 9, "fy": -12, "bx": 12, "by": -12, "ffx": 8, "fbx": -6}
static var act := {
	"onBody": true,
	"follow": 0,
	"poses": [
		[0, IN],
		[1.82, IN],
		[2.05, {"crouch": 3, "fx": 8, "fy": -19, "bx": 8, "by": -18, "ffx": 4, "fbx": -3}],
		[2.5, Px.READY],
		[3, Px.READY],
	],
}

# the beats: the guide thread, the slam, the tube opens, the scan, the cooling, the beam narrows, it snaps shut
const SLAM := 0.34
const OPEN := 0.52
const SCAN0 := 0.62
const SCAN1 := 1.4
const COOL := 0.42
const DONE := SCAN1 + COOL
const CLOSE := 1.9
const SNAP := 2.16
static var TOP: float = -meta.origin[1]


static func actorAlpha(t: float, _o: Dictionary) -> float:
	return 1.0 if t >= DONE else 0.0


# when the scanline crosses row y (top to bottom, easing in and out), for a body from y0 to the floor
static func scanY(t: float, y0: float) -> float:
	return Px.lerp(y0 - 2.0, 1.0, Px.Ease.inOutSine(Px.clamp((t - SCAN0) / (SCAN1 - SCAN0))))


static func scanT(y: float, y0: float) -> float:
	return SCAN0 + ((SCAN1 - SCAN0) * acos(1.0 - 2.0 * Px.clamp((y + 0.5 - (y0 - 2.0)) / (3.0 - y0)))) / PI


# the beam's half width over time: overshoots as it lands, hums, narrows to a thread
static func widthAt(t: float, W: float) -> float:
	if t < SLAM:
		return 0.0
	if t < CLOSE:
		return W * (1.0 + 0.45 * exp(-(t - SLAM) * 14.0) + 0.03 * sin(t * 31.0))
	return Px.lerp(W, 0.7, Px.Ease.outCubic(Px.clamp((t - CLOSE) / (SNAP - CLOSE))))


var C: Array
var W: float
var R: Px.Rng
var A: Dictionary
var seed: float
var ps: Px.Particles
var lights: Px.Lights
var body: Array = []
var rows := {}
var rings: Array = []
var t := 0.0
var slammed := false
var snapped := false
var nextRing := SLAM + 0.08
var lastRow: float


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	W = o.width
	R = Px.Rng.new(o.seed)
	A = o.actor
	seed = o.seed
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[3]], "haze": C[5]})
	lights = Px.Lights.new()
	# the body: each filled pixel, its own color, whether it's on the outline, and each row's extent
	var Aw: int = A.w
	var Ah: int = A.h
	var data: PackedByteArray = A.mask.data
	var pixels: PackedInt32Array = A.pixels
	var on := func(x: int, y: int) -> bool: return x >= 0 and y >= 0 and x < Aw and y < Ah and data[y * Aw + x] != 0
	for my in Ah:
		for mx in Aw:
			var i := my * Aw + mx
			if not data[i]:
				continue
			var x: int = A.x + mx
			var y: int = A.y + my
			var edge: bool = not on.call(mx - 1, my) or not on.call(mx + 1, my) or not on.call(mx, my - 1) or not on.call(mx, my + 1)
			body.append({"x": x, "y": y, "c": pixels[i] if pixels[i] else C[2], "edge": edge, "ts": scanT(y, A.y), "j": Px.rand(o.seed, mx, my)})
			var r: Array = rows.get(y, [x, x])
			rows[y] = [mini(r[0], x), maxi(r[1], x)]
	lastRow = A.y - 3.0


func column(p: Px.Painter) -> void:
	var w := widthAt(t, W)
	if w <= 0.05 or t > SNAP + 0.14:
		return
	# it falls from the sky as it lands, and snaps back up into it at the end
	var bottom := Px.lerp(TOP, 0.0, Px.Ease.inCubic(Px.clamp((t - SLAM) / 0.06) * 0.5 + 0.5)) if t - SLAM < 0.06 else (Px.lerp(0.0, TOP, Px.Ease.outExpo((t - SNAP) / 0.14)) if t > SNAP else 0.0)
	# the core hollows out from the middle into a tube of light, and the tube's walls close into a thread
	var hero_ := t - SLAM < 0.07
	var hollow := 0.78 * Px.smooth(OPEN - 0.16, OPEN, t)
	var thin := 1.0 - Px.clamp((w - 1.5) / (W - 1.5))
	var y := floorf(TOP)
	while y < bottom:
		var pulse := 1 if fmod(fmod((y - TOP) * 0.028 - t * 2.6, 1.0) + 1.0, 1.0) < 0.09 else 0
		var x := floorf(-w * 1.35)
		while x <= ceilf(w * 1.35):
			var q := absf(x + 0.5) / w
			if q > 1.35:
				x += 1.0
				continue
			if hero_:
				p.dot(x, y, WHITE if q < 0.55 else (C[6] if q < 0.8 else (C[5] if q < 1.0 else C[4])), 1.0 if q < 1.0 else (1.35 - q) / 0.35)
				x += 1.0
				continue
			if w < 2.4:
				p.dot(x, y, WHITE if q < 0.7 else C[6], 1.0 if q < 1.0 else (1.35 - q) / 0.35)
				x += 1.0
				continue
			# strands: thin bright threads drifting inside the beam
			var strand := 0
			for s in 5:
				if absf((x + 0.5) / w - (Px.rand(seed, s) - 0.5) * 1.3 - 0.06 * sin(t * (1.5 + s) + s * 2)) < 0.05:
					strand = 1
			if q < hollow:
				p.blend(x + 0.5, y + 0.5, C[6] if (strand or pulse) else C[5], Px.clamp(0.12 + 0.3 * q * q + 0.3 * strand + 0.25 * pulse + 0.7 * thin))
			elif q < 0.78:
				var lvl := maxi(0, (0 if q < 0.22 else (1 if q < 0.45 else 2)) - pulse - strand)
				p.px(x, y, WHITE if lvl == 0 else C[7 - lvl])
			elif q < 0.96:
				p.px(x, y, WHITE if (q > 0.86 and q < 0.93) else C[6])
			else:
				p.dot(x, y, C[5] if q < 1.1 else C[4], (1.35 - q) / 0.39)
			x += 1.0
		# light rides the walls, not the middle, so the body being built inside stays readable
		if (int(y) & 7) == 0:
			var r := minf(w + 8.0, y - TOP + 2.0)
			if hollow < 0.4:
				p.glow(0.0, y, minf(w * 2.6 + 6.0, y - TOP + 2.0), C[4], 0.55 if hero_ else 0.32)
			else:
				for s: float in [-1.0, 1.0]:
					p.glow(s * (w + 3.0), y, r, C[4], 0.24)
		y += 1.0


# a ring riding down the beam: the near half in front, the far half behind
func ring(p: Px.Painter, near: bool) -> void:
	var w := widthAt(t, W)
	for r: Dictionary in rings:
		var k: float = (t - r.t0) / 0.5
		if k < 0.0 or k >= 1.0:
			continue
		var y := Px.lerp(TOP + 6.0, -1.0, Px.Ease.inQuad(k))
		var rx := w * 1.18 + 1.0
		var c: int = WHITE if k < 0.25 else C[6]
		Px.band(p, 0.0, y, rx, 2.6 / rx, 1.5, 1.0, [C[3], C[5], c, WHITE], func(g: float) -> bool: return (sin(g) >= 0.0) == near)
		if near:
			p.glow(0.0, y, rx + 6.0, C[5], 0.25)


# the floor where the beam stands: a pool of light, ripples where rings land, the slam's shockwave
func floor_(p: Px.Painter, near: bool) -> void:
	var on := Px.smooth(0.0, SLAM, t) * 0.5 if t < SLAM else 1.0 - Px.smooth(SNAP, SNAP + 0.5, t)
	if not near and on > 0.01:
		var rx := W * 1.9 + (0.0 if t < SLAM else 2.0 * sin(t * 6.0))
		var ry := 4.0
		for yi in range(-4, 5):
			var y := float(yi)
			var x := floorf(-rx)
			while x <= ceilf(rx):
				var d := Px.hypot((x + 0.5) / rx, (y + 0.5) / ry)
				if d > 1.0:
					x += 1.0
					continue
				p.dot(x, y, C[7] if d < 0.35 else (C[6] if d < 0.6 else (C[5] if d < 0.85 else C[4])), on * Px.clamp((1.05 - d) * 2.4))
				x += 1.0
		for x: float in [-rx * 0.6, 0.0, rx * 0.6]:
			p.glow(x, -1.0, rx * 1.3, C[4], 0.3 * on)
	var keep := func(g: float) -> bool: return (sin(g) >= 0.0) == near
	for r: Dictionary in rings:
		var k: float = (t - r.t0 - 0.5) / 0.35
		if k >= 0.0 and k < 1.0:
			Px.band(p, 0.0, 0.0, W * (1.2 + 1.3 * Px.Ease.outCubic(k)), 0.16, 1.5, 1.0 - k, [C[3], C[4], C[5], C[6]], keep)
	for ds: Array in [[0.0, 1.0], [0.08, 0.65]]:
		var d: float = ds[0]
		var s: float = ds[1]
		var k := (t - SLAM - d) / 0.55
		if k >= 0.0 and k < 1.0:
			Px.band(p, 0.0, 0.5, 92.0 * s * Px.Ease.outCubic(k), 0.16, maxf(1.0, 5.0 * (1.0 - k)), 1.15 - k, [C[3], C[5], C[6], WHITE], keep, k < 0.25)
	var k := (t - SNAP) / 0.45
	if k >= 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.0, 10.0 + 26.0 * Px.Ease.outCubic(k), 0.16, 2.0 * (1.0 - k) + 0.5, 1.1 - k, [C[4], C[5], C[6], WHITE], keep, k < 0.3)


# the hero, built out of light: the blueprint first, then each row as the scanline crosses it, white-hot
# and cooling through the beam's color to its own
func hero(p: Px.Painter) -> void:
	if t >= DONE or t < SCAN0 - 0.2:
		return
	var blink := floori(t * 24.0)
	for b: Dictionary in body:
		var a: float = t - b.ts
		if a < 0.0:
			if b.edge and Px.rand(b.x, b.y, blink) < 0.6:
				p.dot(b.x, b.y, C[1], 0.8 * Px.smooth(SCAN0 - 0.25, SCAN0 - 0.05, t))
			continue
		var k := a / COOL
		# the newest rows jitter sideways a pixel, as if still arriving
		var dx := (-1.0 if b.j < 0.15 else 1.0) if (a < 0.06 and b.j < 0.3) else 0.0
		p.px(b.x + dx, b.y, WHITE if k < 0.18 else (Px.mix(b.c, C[6], 0.72) if k < 0.45 else (Px.mix(b.c, C[5], 0.38) if k < 0.75 else b.c)))
		if k < 0.5:
			p.light(b.x + dx, b.y, C[5], 0.22 * (1.0 - k / 0.5))


# the scanline: a white rule across the beam, hottest where it crosses the body, sparking at its edges
func scanline(p: Px.Painter) -> void:
	if t < SCAN0 or t > SCAN1:
		return
	var y := floori(scanY(t, A.y))
	var w := widthAt(t, W) * 1.5
	var r: Variant = rows.get(y)
	var x := floorf(-w)
	while x <= ceilf(w):
		var inside: bool = r != null and x >= r[0] and x <= r[1]
		p.dot(x, y, WHITE if inside else C[6], 1.0 if inside else 1.0 - absf(x + 0.5) / (w + 1.0))
		x += 1.0
	p.glowLine(-w, y, w, y, 5.0, C[5], 0.5)
	if r:
		for rx: int in r:
			Px.sparkle(p, rx + 0.5, y, 2.0, C[6], C[5], 0.3)


func update(dt: float) -> void:
	t += dt
	# gathering: energy streaks in toward the spot, vapour slides along the floor
	if t < SLAM - 0.04:
		if R.chance(0.8):
			var a := R.range(-PI * 0.95, -PI * 0.05)
			var D := R.range(30.0, 64.0)
			var T := R.range(0.18, 0.28)
			var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
			var x := cos(a) * D
			var y := sin(a) * D * 0.8 - 2.0
			var l := Px.hypot(x, y + 2.0)
			if not l:
				l = 1.0
			ps.spawn(P.STREAK, x, y, (-x / l) * v, (-(y + 2.0) / l) * v, T, C[6] if R.chance(0.5) else C[5])
		if R.chance(0.12):
			var s := R.sign()
			ps.spawn(P.VAPOUR, s * R.range(30.0, 56.0), -R.range(0.0, 2.0), -s * R.range(40.0, 70.0), -R.range(0.0, 4.0), R.range(0.3, 0.45), C[5], R.range(2.0, 3.0))
	if t >= SLAM and not slammed:
		slammed = true
		lights.add(0.0, -40.0, 120.0, C[4], 1.0, 0.55)
		lights.add(0.0, -10.0, 44.0, WHITE, 0.9, 0.14)
		for i in 34:
			var a := -PI / 2.0 + R.sign() * R.range(0.35, 1.45)
			var sp := R.range(110.0, 270.0)
			ps.spawn(P.SPARK, R.range(-W, W) * 0.6, -1.0, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.75))
		for i in 18:
			var s := R.sign()
			ps.spawn(P.VAPOUR, s * R.range(4.0, 18.0), -R.range(0.0, 4.0), s * R.range(40.0, 150.0), -R.range(2.0, 18.0), R.range(0.5, 0.95), C[6] if R.chance(0.6) else C[5], R.range(3.0, 6.0))
		for i in 10:
			ps.spawn(P.STAR, R.range(-W, W) * 1.3, -R.range(2.0, 40.0), R.range(-20.0, 20.0), -R.range(10.0, 40.0), R.range(0.4, 0.8), WHITE if R.chance(0.5) else C[6], R.range(1.0, 2.2))
	if slammed and t < CLOSE:
		# rings ride down, light falls down the beam, glints wink at its walls
		if t >= nextRing:
			rings.append({"t0": nextRing})
			nextRing += 0.17
		var w := widthAt(t, W)
		if R.chance(0.5):
			ps.spawn(P.STREAK, R.range(-0.8, 0.8) * w, TOP + R.range(9.0, 36.0), 0.0, R.range(60.0, 110.0), R.range(0.3, 0.45), WHITE if R.chance(0.5) else C[6])
		if R.chance(0.18):
			ps.spawn(P.STAR, R.sign() * w * R.range(0.8, 1.3), -R.range(4.0, 70.0), 0.0, -R.range(5.0, 20.0), R.range(0.3, 0.6), C[6], R.range(0.6, 1.8))
		if R.chance(0.1):
			var s := R.sign()
			ps.spawn(P.VAPOUR, s * R.range(8.0, 16.0), -R.range(0.0, 3.0), s * R.range(20.0, 50.0), -R.range(2.0, 8.0), R.range(0.5, 0.8), C[5], R.range(2.5, 4.0))
	# the scanline spits light off the edges of the body as it crosses
	if t > SCAN0 and t < SCAN1:
		var y := floori(scanY(t, A.y))
		if y != lastRow:
			lastRow = y
			var r: Variant = rows.get(y)
			if r and R.chance(0.7):
				for xs: Array in [[r[0], -1], [r[1] + 1, 1]]:
					var x: int = xs[0]
					var s: int = xs[1]
					if R.chance(0.6):
						ps.spawn(P.MOTE, x, y, s * R.range(40.0, 90.0), R.range(-20.0, 10.0), R.range(0.15, 0.3), WHITE if R.chance(0.5) else C[6], 0.6)
	if t >= DONE and t - dt < DONE:
		# set: a glint or two on the new body
		for i in 6:
			var b: Dictionary = body[floori(R.next() * body.size())]
			ps.spawn(P.STAR, b.x + 0.5, b.y + 0.5, R.range(-6.0, 6.0), -R.range(6.0, 20.0), R.range(0.4, 0.8), WHITE if R.chance(0.5) else C[6], R.range(1.0, 2.0))
	if t >= SNAP and not snapped:
		snapped = true
		lights.add(0.0, -1.0, 32.0, C[4], 0.5, 0.25)
		lights.add(0.0, -1.0, 10.0, WHITE, 0.5, 0.08)
		for i in 22:
			var a := -PI / 2.0 + R.range(-1.4, 1.4)
			var sp := R.range(90.0, 260.0)
			ps.spawn(P.SPARK, R.range(-2.0, 2.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.6))
		for i in 12:
			ps.spawn(P.STAR, R.range(-16.0, 16.0), -R.range(0.0, 46.0), R.range(-10.0, 10.0), -R.range(8.0, 26.0), R.range(0.5, 0.9), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.8))
		# where the beam stood, motes keep rising for a while
		for i in 18:
			ps.spawn(P.STAR if R.chance(0.6) else P.MOTE, R.range(-6.0, 6.0), -R.range(10.0, 100.0), R.range(-6.0, 6.0), -R.range(14.0, 40.0), R.range(0.5, 0.75), WHITE if R.chance(0.4) else (C[6] if R.chance(0.5) else C[5]), R.range(0.5, 1.4), R.range(0.0, 0.25))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	floor_(p, false)
	ring(p, false)
	column(p)
	# the guide thread: a dotted line pricking down to the spot, brightening
	if t < SLAM:
		var a := Px.smooth(0.0, SLAM * 0.8, t) * 0.8
		var head := Px.lerp(TOP, 0.0, Px.Ease.outCubic(Px.clamp(t / (SLAM * 0.6))))
		var y := TOP
		while y < head:
			p.dot(0.0, y, C[6] if (int(y) & 1) == 0 else C[5], a * (0.35 + 0.65 * ((y - TOP) / -TOP)))
			y += 1.0
		p.glow(0.0, head, 10.0, C[5], 0.5 * a)
		# a target on the floor, closing in
		var rx := Px.lerp(34.0, 12.0, Px.Ease.outCubic(t / SLAM))
		var k := Px.smooth(0.0, 0.15, t)
		for i in 48:
			var g := (i / 48.0) * TAU + t * 3.0
			if floori(i / 4.0) % 2:
				continue
			p.dot(cos(g) * rx, sin(g) * rx * 0.16, WHITE if i % 4 == 0 else C[5], k)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	hero(p)
	scanline(p)
	ring(p, true)
	floor_(p, true)
	# the set body's outline flares as it lands, then fades
	if t >= DONE and t < DONE + 0.3:
		p.outline(A.mask, A.x, A.y, C[6], 1.0 - (t - DONE) / 0.3)
	if t > SLAM and t < SLAM + 0.16:
		Px.sparkle(p, 0.0, -2.0, 12.0 * (1.0 - (t - SLAM) / 0.16), C[6], C[5], 0.6)
	ps.draw(p, "front")
	lights.draw(p)
