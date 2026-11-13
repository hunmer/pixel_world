# The layered flame tongues and the licks, embers and smoke shed off a burning edge follow Sprite Fusion's
# open-source fire (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/burn-away.js@3b2f70286158e1a568f0dd1f84a0592abc9a0077
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE
const SMOKE_RAMP := Px.SMOKE_RAMP
const W := Lib.W
const H := Lib.H

static var meta := Lib.screenMeta({
	"name": "Burn away",
	"desc": "The screen burns in from its edges behind a ragged ember line of licking flames, embers and smoke; then the black smoulders and burns open from the middle.",
	"tags": ["burn", "fire", "embers", "smoke", "wipe"],
	"duration": 3.0,
	"options": {"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"], "seed": 3},
})

static var D: float = meta.duration
const CLOSE := 1.18
const COVER := 1.35
const SMOULDER := 1.5
const POP := 1.8
const OPEN := 2.62
const SC := 90.0
const HALO := 24.0
const POOL := 48.0
const ASH := ["#a39cab", "#7b7484", "#5c5664", "#433e4b"]
# a tongue's layers: [width, height, palette step], outermost (red) to the white core
const LAYERS := [[1.0, 1.0, 2], [0.76, 0.86, 4], [0.54, 0.68, 6], [0.3, 0.42, 8]]


# where the fire reaches when: rising from the edges' midpoints (the corners go first), ragged at two scales,
# and the bottom burns a little faster because fire climbs
static func inField(seed: float) -> Dictionary:
	return Lib.field(func(x: float, y: float) -> float:
		var ux := (x - W / 2.0) / (W / 2.0)
		var uy := (y - H / 2.0) / (H / 2.0)
		var m := pow(ux ** 4 + uy ** 4, 0.25)
		return (1.0 - m) * SC + 14.0 * Px.fbm(x / 44.0, y / 44.0, seed, 3) + 2.4 * Px.fbm(x / 7.0, y / 7.0, seed + 9.0, 2) + 7.0 * (0.5 - y / H))


# the hole: from a spot near the middle (and two smaller ones that catch a beat later) out to the corners
static func outField(seed: float) -> Dictionary:
	var R := Px.Rng.new(seed * 31.0 + 5.0)
	var ox := W / 2.0 + R.range(-26, 26)
	var oy := H / 2.0 + R.range(-14, 6)
	var sats := []
	for s in [-1.0, 1.0]:
		sats.append({"x": ox + s * R.range(70, 110), "y": oy + R.range(-40, 40), "d": R.range(30, 44)})
	var f := Lib.field(func(x: float, y: float) -> float:
		var v := Px.hypot((x - ox) / (W / 2.0), (y - oy) / (H / 2.0)) * SC
		for s: Dictionary in sats:
			v = minf(v, s.d + Px.hypot((x - s.x) / (W / 2.0), (y - s.y) / (H / 2.0)) * SC * 1.15)
		return v + 13.0 * Px.fbm(x / 40.0, y / 40.0, seed + 21.0, 3) + 2.4 * Px.fbm(x / 7.0, y / 7.0, seed + 33.0, 2))
	f.ox = ox
	f.oy = oy
	return f


# a flame standing on (x, y): four layers of the ramp, each narrower, shorter and hotter, swaying at the tip
static func tongue(p: Px.Painter, F: Array, x: float, y: float, h: float, w: float, sway: float, t: float, n: int) -> void:
	for layer: Array in LAYERS:
		var lw: float = layer[0]
		var lh: float = layer[1]
		var ri: int = layer[2]
		var Ht := h * lh
		var col: int = F[ri]
		var r := 0
		while r <= Ht:
			var u := r / maxf(1.0, Ht)
			var half := w * lw * pow(1.0 - u, 0.85) * minf(1.0, (r + 1.5) / 3.5) + Px.noise(t * 9.0 + r * 0.45, n) * 0.5
			if half < 0.3:
				r += 1
				continue
			var cx := x + sway * u * u * lh + Px.noise(t * 4.0 + r * 0.2, n + 7) * u * 1.1
			for px in range(int(Px.round(cx - half)), int(Px.round(cx + half)) + 1):
				p.px(px, Px.round(y - r), col)
			r += 1


var F: Array
var ink: int
var R: Px.Rng
var seed: float
var CHAR: int
var SCORCH: int
var WARM: int
var SMOKE: int
var A: Dictionary
var B: Dictionary
# per pixel: how hot the ember line burns there (two smooth fields), and the odd fleck that glows on
# (ph: a smooth phase 0..63 that the flicker tables are read with; jit: a ragged char rim)
# (vein: near 0 along a web of thin curving cracks, where the char smoulders before it burns open)
var heat := PackedFloat32Array()
var ph := PackedByteArray()
var fleck := PackedFloat32Array()
var jit := PackedFloat32Array()
var vein := PackedFloat32Array()
var FL := PackedFloat32Array()
var HV := PackedFloat32Array()
var TW := PackedByteArray()
var ps: Px.Particles
var ash: Px.Particles
var lights: Px.Lights
var line := []  # the white-hot line's pixels this frame: where flames stand
var t := 0.0
var pin := 0
var pout := 0
var closed := false
var popped := false
var LIT: int
var DIM: int

# what a patch of edge gives off as the front crosses it: licks of flame, embers, ash, now and then a cloud
# of smoke (a run of puffs from one spot, so it rolls up as a wisp, not a dot) and a flicker of light. Per
# pixel crossed: [flame, ember, smoke, smoke on the hottest stretches, ash, light]. The black burning open
# sheds fewer embers and less ash, so the picture it uncovers stays clear.
const RATE := {"in": [0.006, 0.0014, 0.0006, 0.0024, 0.0012, 0.0004], "out": [0.006, 0.0005, 0.0004, 0.0012, 0.0004, 0.0004]}


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 9)
	ink = Px.hex(o.color)
	R = Px.Rng.new(o.seed)
	seed = o.seed * 13.0
	CHAR = Px.mix(ink, F[0], 0.45)
	SCORCH = Px.mix(ink, Px.hex("#3a2216"), 0.6)
	WARM = Px.mix(F[4], F[5], 0.4)
	SMOKE = Px.mix(Px.hex("#8a7276"), F[2], 0.2)
	A = inField(seed)
	B = outField(seed + 1.0)
	heat.resize(W * H)
	ph.resize(W * H)
	fleck.resize(W * H)
	jit.resize(W * H)
	vein.resize(W * H)
	for i in W * H:
		var x := i % W
		var y := floori(i / float(W))
		heat[i] = 0.5 + 0.5 * Px.noise2(x / 13.0, y / 13.0, seed + 41.0)
		ph[i] = mini(63, floori((0.5 + 0.5 * Px.noise2(x / 23.0, y / 23.0, seed + 43.0)) * 64.0))
		fleck[i] = 9.0 + 22.0 * Px.rand(x, y, seed + 47.0) if Px.rand(x, y, seed + 45.0) < 0.04 else 0.0
		jit[i] = (Px.rand(x, y, seed + 49.0) - 0.5) * 1.5
		var rx := x * 0.8 + y * 0.6  # off the pixel grid, so cracks don't run square
		var ry := y * 0.8 - x * 0.6
		vein[i] = minf(absf(Px.noise2(rx / 11.0, ry / 9.0, seed + 61.0)), absf(Px.noise2(ry / 5.5, rx / 5.0, seed + 63.0)) * 1.5)
	FL.resize(64)
	HV.resize(64)
	TW.resize(64)
	ps = Px.Particles.new({"rng": R, "sparks": [F[7], F[6], F[4], F[2]]})
	ash = Px.Particles.new({"rng": R, "sparks": ASH})
	lights = Px.Lights.new()
	line = []
	t = 0.0
	pin = 0
	pout = 0
	closed = false
	popped = false
	# smoke shows where firelight catches it: lit warm near the burning line, dark over the picture, all but lost
	# in the black away from the fire (the sim's smoke puff, three soft discs, shaded by that light)
	LIT = Px.mix(Px.hex("#8a7276"), F[3], 0.25)
	DIM = Px.hex(SMOKE_RAMP[3])


func kIn(t: float) -> float:
	return A.lo - 8.0 + (A.hi - A.lo + 8.0) * pow(maxf(0.0, t) / CLOSE, 1.25)


func kOut(t: float) -> float:
	return B.lo - 24.0 + 24.0 * Px.Ease.inQuad(Px.clamp((t - SMOULDER) / (POP - SMOULDER))) if t < POP else B.lo + (B.hi - B.lo + 16.0) * Px.Ease.outQuad(Px.clamp((t - POP) / (OPEN - POP)))


func shed(i: int, inA: bool) -> void:
	# what burns in is gone before the black burns open, so the uncovered picture starts clean
	var rt: Array = RATE["in"] if inA else RATE.out
	var fl: float = rt[0]
	var em: float = rt[1]
	var sm: float = rt[2]
	var sh: float = rt[3]
	var as_: float = rt[4]
	var li: float = rt[5]
	var x := (i % W) + 0.5
	var y := floorf(i / float(W)) + 0.5
	var end := POP + 0.1 if inA else D - 0.05
	var r := R.next()
	r -= fl
	if r < 0.0:
		var life := Lib.lifeLeft(R.range(0.18, 0.4), t, end)
		if life > 0.08:
			ps.spawn(P.FIRE, x, y - 3.0, R.range(-8, 8), -R.range(25, 50), life, 0, R.range(0.8, 1.7))
		return
	r -= em
	if r < 0.0:
		var life := Lib.lifeLeft(R.range(0.6, 1.3) if inA else R.range(0.5, 1), t, end)
		if life > 0.2:
			ps.spawn(P.EMBER, x, y - 2.0, R.range(-30, 30), -R.range(40, 100), life, 0, 2 if R.chance(0.25) else 1)
		return
	r -= sm + sh * heat[i] ** 2
	if r < 0.0:
		# smoke lives long only where the front chases it upward; elsewhere the front leaves it, so it's a wisp
		var n := R.int_(4, 6)
		var vx := R.range(-6, 6)
		var up: bool = (A if inA else B).ny[i] < -0.25
		for j in n:
			var life := Lib.lifeLeft(R.range(0.8, 1.3) if up else R.range(0.35, 0.65), t + j * 0.05, end)
			if life > 0.4:
				ps.spawn(P.SMOKE, x + R.range(-3.5, 3.5), y - 4.0 - j * 1.2, vx + R.range(-3, 3), -R.range(18, 34), life, SMOKE, R.range(2.8, 4.8), j * 0.05)
		return
	r -= as_
	if r < 0.0:
		var life := Lib.lifeLeft(R.range(0.9, 1.6), t, end)
		if life > 0.3:
			ash.spawn(P.EMBER, x, y - 2.0, R.range(-18, 18), -R.range(25, 60), life)
		return
	r -= li
	if r < 0.0:
		lights.add(x, y - 4.0, R.range(20, 32), WARM, R.range(0.14, 0.26), R.range(0.18, 0.4))


func drawSmoke(p: Px.Painter, p0: Px.Painter) -> void:
	var inPhase := t < COVER
	var open := t >= SMOULDER and t < OPEN + 0.25
	var k := kIn(t) if inPhase else kOut(t)
	var f: PackedFloat32Array = A.f if inPhase else B.f
	for q: Dictionary in ps.list:
		if q.k != P.SMOKE or q.delay > 0.0:
			continue
		var kk: float = q.life / q.max
		var age := 1.0 - kk
		var r: float = q.size * (0.65 + minf(1.0, age * 2.5) * 0.45 + age * 0.4)
		var i := int(Px.clamp(floorf(q.y), 0.0, H - 1.0)) * W + int(Px.clamp(floorf(q.x), 0.0, W - 1.0))
		var e := ((k - f[i]) if inPhase else (f[i] - k)) if (inPhase or open) else 99.0
		var lit := Px.clamp(1.0 - absf(e) / 30.0)
		var a := minf(1.0, age * 12.0) * minf(1.0, kk * 2.4) * 0.58 * (0.05 + 0.95 * lit if e > 0.0 else (1.0 if inPhase else 0.2 + 0.8 * lit))
		if a < 0.04:
			continue
		# a puff wholly on screen needs no clipping
		var c := Px.mix(Px.mix(DIM, LIT, lit), SMOKE_RAMP[2], age * 0.5)
		var d: Px.Painter = p0 if (q.x - r > 0.0 and q.y - r > 0.0 and q.x + r < W - 1.0 and q.y + r < H - 1.0) else p
		d.disc(q.x, q.y, r, c, a * 0.45)
		d.disc(q.x + r * 0.05, q.y + r * 0.06, r * 0.74, c, a * 0.62)
		if age < 0.5:
			d.disc(q.x - r * 0.22, q.y - r * 0.3, r * 0.5, Px.mix(c, WHITE, 0.15), a * 0.4 * (1.0 - age * 2.0))


func update(dt: float) -> void:
	t += dt
	# the front eats inward: everything it passes this step gives off flame, embers, ash and smoke
	if t < COVER:
		var k := kIn(t)
		var ord: PackedInt32Array = A.order
		var af: PackedFloat32Array = A.f
		while pin < ord.size() and af[ord[pin]] <= k:
			pin += 1
			shed(ord[pin - 1], true)
		if not closed and t >= CLOSE:
			# the last of the picture goes up in a puff
			closed = true
			var i: int = ord[ord.size() - 1]
			var x := i % W
			var y := floori(i / float(W))
			lights.add(x, y, 64, WARM, 0.5, 0.4)
			for j in 12:
				ps.spawn(P.EMBER, x + R.range(-6, 6), y + R.range(-3, 3), R.range(-50, 50), -R.range(40, 120), R.range(0.5, 0.75), 0, 2 if R.chance(0.3) else 1)
			for j in 5:
				ps.spawn(P.SMOKE, x + R.range(-8, 8), y + R.range(-4, 2), R.range(-10, 10), -R.range(12, 28), R.range(1.1, 1.6), SMOKE, R.range(3.5, 5.5), R.range(0, 0.15))
	# the black smoulders in the middle, then burns open
	if t >= SMOULDER and t < POP and R.chance(0.1):
		var i: int = B.order[R.int_(0, 400)]
		var x := (i % W) + 0.5
		var y := floorf(i / float(W)) + 0.5
		if R.chance(0.6):
			ps.spawn(P.SMOKE, x, y, R.range(-4, 4), -R.range(8, 16), Lib.lifeLeft(R.range(0.9, 1.4), t, D - 0.05), SMOKE, R.range(2, 3.5))
		else:
			ps.spawn(P.EMBER, x, y, R.range(-12, 12), -R.range(15, 40), R.range(0.4, 0.8))
	if not popped and t >= POP:
		popped = true
		lights.add(B.ox, B.oy, 90, WARM, 0.6, 0.45)
		lights.add(B.ox, B.oy, 34, F[7], 0.7, 0.12)
		for j in 12:
			var a := R.range(0, TAU)
			var sp := R.range(50, 150)
			ps.spawn(P.EMBER, B.ox + cos(a) * 3.0, B.oy + sin(a) * 2.0, cos(a) * sp, sin(a) * sp * 0.7 - 40.0, R.range(0.4, 0.9), 0, 2 if R.chance(0.3) else 1)
		for j in 10:
			var a := R.range(0, TAU)
			var sp := R.range(120, 260)
			ps.spawn(P.SPARK, B.ox, B.oy, cos(a) * sp, sin(a) * sp - 50.0, R.range(0.15, 0.35))
	if t >= POP and t < OPEN + 0.2:
		var k := kOut(t)
		var ord: PackedInt32Array = B.order
		var bf: PackedFloat32Array = B.f
		while pout < ord.size() and bf[ord[pout]] <= k:
			pout += 1
			shed(ord[pout - 1], false)
	ps.update(dt)
	ash.update(dt)
	lights.update(dt)


# what shadeAt reads (the JS closure's captures), set by draw each frame
var _inPhase := false
var _k := 0.0
var _f: PackedFloat32Array
var _g: PackedFloat32Array
var _px: Lib.Pixels
var _sk := 0.0
var _SR := 0.0
var _fade := 1.0
var _Blo := 0.0


func shadeAt(i: int) -> void:
	# e: how far into the cover this pixel is in field units (smooth, for light); s: in px from the
	# burning line (sharp near it, for the line itself)
	var px := _px
	var e := (_k - _f[i]) if _inPhase else (_f[i] - _k)
	var s := e * _g[i]
	px.at(i)
	if e < 0.0:
		# the picture just ahead of the fire: scorched, and lit by it
		if _inPhase and s > -2.5:
			px.blend(SCORCH, 0.5 * (1.0 + s / 2.5))
		var u := maxf(0.0, 1.0 + e / HALO)
		var v := 1.0 + e / POOL
		px.add(WARM, (0.3 * u * u + 0.12 * v * v) * FL[ph[i]])
		return
	var hv := Px.clamp(heat[i] + HV[ph[i]])
	var th := 0.6 + 0.6 * hv
	var u := s / th
	if u < 6.4:
		# the ember line: white-hot at the edge, cooling down the ramp into char
		if u < 0.9:
			line.append(i)
		px.put((F[8] if hv > 0.6 else F[7]) if u < 0.9 else (F[6] if u < 1.7 else (F[5] if u < 2.4 else (F[4] if u < 3.1 else (F[3] if u < 3.8 else (F[2] if u < 4.6 else (F[1] if u < 5.5 else F[0])))))))
		if u < 4.6:
			px.add(WARM, 0.45 * (1.0 - u / 4.6) * (0.7 + 0.3 * hv))
		return
	if _sk > 0.0 and _f[i] < _Blo + _SR:
		var hm := (1.0 - (_f[i] - _Blo) / _SR) * _sk * (0.7 + 0.6 * hv)
		if vein[i] < 0.04 + 0.08 * hm:
			px.put(F[6] if hm > 0.95 else (F[5] if hm > 0.75 else (F[4] if hm > 0.55 else (F[3] if hm > 0.38 else (F[2] if hm > 0.22 else F[1])))))
			px.add(WARM, 0.4 * hm)
			return
		px.add(WARM, 0.2 * hm * hm)
	# char, with the odd fleck still glowing in it
	var L := fleck[i] * (0.8 + 0.4 * hv)
	if L > 0.0 and s < L:
		var v := (s - 6.4 * th) / maxf(1.0, L - 6.4 * th)
		if v < 1.0 and TW[(ph[i] * 5) & 63] and not (_fade < 1.0 and _fade <= jit[i] / 1.5 + 0.5):
			px.put(F[4] if v < 0.3 else (F[3] if v < 0.55 else (F[2] if v < 0.8 else F[1])))
			px.add(WARM, 0.3 * (1.0 - v))
			return
	if e < 22.0:
		px.add(WARM, 0.2 * (1.0 - e / 22.0) ** 2)
	px.put(CHAR if u - 6.4 < 1.6 * th + jit[i] else ink)


func draw(p0: Px.Painter) -> void:
	var p := Lib.clipTo(p0)
	line.clear()
	if t >= COVER and t < SMOULDER:
		Lib.rect(p0, 0.0, 0.0, W, H, ink)
	elif t < OPEN + 0.25:
		var inPhase := t < COVER
		var k := kIn(t) if inPhase else kOut(t)
		var Fd: Dictionary = A if inPhase else B
		var f: PackedFloat32Array = Fd.f
		var g: PackedFloat32Array = Fd.g
		var fade := 1.0 - Px.smooth(COVER - 0.15, COVER, t) if inPhase else 1.0
		for j in 64:
			var q := j / 63.0
			FL[j] = 0.75 + 0.25 * sin(t * 7.0 + q * 9.0)
			HV[j] = 0.3 * sin(t * 5.5 + q * 11.0)
			TW[j] = 1 if sin(t * 13.0 + q * 40.0) > -0.5 else 0
		# only the pixels near the burning line need working out (a slice of the field's order): the cover
		# behind it is plain ink, the picture far ahead of it untouched. Straight to the frame: all on screen.
		var px := Lib.pixels(p0)
		var ord: PackedInt32Array = Fd.order
		var N := ord.size()
		# before the black burns open it smoulders: a web of cracks in the hole's own shape glows, spreads and
		# heats from dark red, then the hole bursts through it and it cools
		var su := Px.clamp((t - SMOULDER) / (POP - SMOULDER))
		var SR := 5.0 + 17.0 * su
		var sk := 0.0 if (inPhase or t < SMOULDER) else (0.3 + 0.7 * su if t < POP else 1.0 - (t - POP) / 0.3)
		_inPhase = inPhase
		_k = k
		_f = f
		_g = g
		_px = px
		_sk = sk
		_SR = SR
		_fade = fade
		_Blo = B.lo
		# [c0, c1): deep in the cover; [a0, a1): near the line
		var lo: int = Fd.below.call(k - (33.0 if inPhase else POOL))
		var hi: int = Fd.below.call(maxf(k + (POOL if inPhase else 33.0), B.lo + SR if sk > 0.0 else -1e9))
		var c0 := 0 if inPhase else hi
		var c1 := lo if inPhase else N
		var a0 := lo
		var a1 := hi
		for j in range(c0, c1):
			var i := ord[j]
			if fleck[i]:
				shadeAt(i)
			else:
				px.at(i)
				px.put(ink)
		for j in range(a0, a1):
			shadeAt(ord[j])
		# flames stand on the white-hot line: tall and many where the char lies below it and they rise clear,
		# short and few where they'd only lick up over the char
		var ny: PackedFloat32Array = Fd.ny
		for i: int in line:
			var x := i % W
			var y := floori(i / float(W))
			var dn := -ny[i] if inPhase else ny[i]
			var h0 := Px.rand(x, y >> 3, seed + 51.0)
			if h0 > 0.12 + 0.6 * maxf(0.0, dn):
				continue
			var n := (x * 7 + (y >> 4) * 131) % 977
			var hv := heat[i]
			var leap := 1.0 + maxf(0.0, Px.noise(t * 2.6 + n * 3.1, n + 70) - 0.5) * 1.8
			var h := (5.0 + 7.0 * Px.rand(x, 1, seed + 53.0)) * (0.6 + 0.4 * Px.noise(t * 3.3 + n * 1.7, n)) * (0.6 + 0.6 * hv) * leap * fade * (0.65 + 0.5 * dn if dn > 0.0 else 0.5)
			if h >= 1.5:
				tongue(p, F, x + 0.5, y + 1.0, h, (1.1 + 0.7 * hv) * (0.8 + h / 16.0), Px.noise(t * 2.2 + n, n + 40) * 1.5, t, n)
	drawSmoke(p, p0)
	ash.draw(p, "front")
	ps.draw(p, "front")
	lights.draw(p)
