# The cut's tapered smear (white at the rim, cooling down the ramp with age), the dotted trace it leaves, the
# tip glint, the sparks off the end and the shavings flung off the line are adapted from Sprite Fusion's
# open-source slash (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/slash-wipe.js@f8d811858b6a43e03eefddb36ea52799d4108406
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE
const W := Lib.W
const H := Lib.H

static var meta := Lib.screenMeta({
	"name": "Slash wipe",
	"desc": "A white-hot blade edge slices across the screen, light ahead of it and sparks spraying back over the cover; a second cut flashes through and the cover splits apart.",
	"tags": ["slash", "blade", "cut", "sparks", "wipe"],
	"duration": 1.7,
	"options": {
		"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#b8c9e8", "#e8f1ff", "#ffffff"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"seed": 2,
	},
})

static var D: float = meta.duration
const SL := 0.55
static var CS := 1.0 / Px.hypot(1.0, SL)
const HALO := 18.0
const T0 := 0.06
const SWEEP := 0.62
const E0 := -(H / 2.0) * SL - 4.0
const E1 := W + (H / 2.0) * SL + 24.0
const CUT := 0.84
const CSW := 0.07
const CHOLD := 0.05
const CTRAIL := 0.12
const SLIP := CUT + 0.12
const SPLIT := CUT + CSW + CHOLD + CTRAIL


# the blade edge: x where it crosses row y, and how fast it's moving
static func edgeAt(t: float) -> float:
	return E0 + (E1 - E0) * Px.Ease.outCubic(Px.clamp((t - T0) / SWEEP))

static func speedAt(t: float) -> float:
	return 0.0 if (t < T0 or t > T0 + SWEEP) else ((E1 - E0) * 3.0 * (1.0 - (t - T0) / SWEEP) ** 2) / SWEEP

static func xAt(e: float, y: float) -> float:
	return e + (H / 2.0 - y) * SL


var C: Array
var ink: int
var R: Px.Rng
var n: int
var ps: Px.Particles
var lights: Px.Lights
var ux: float
var uy: float
var nx: float
var ny: float
var cx: float
var cy: float
var A: Array
var B: Array
var LC: float
var halves: Array
var t := 0.0
var acc := 0.0
var entered := false
var tipped := false
var split := false
var end: float


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	ink = Px.hex(o.color)
	R = Px.Rng.new(o.seed)
	n = C.size()
	ps = Px.Particles.new({"rng": R, "sparks": o.sparks})
	lights = Px.Lights.new()
	# the second cut: a "\\" through the middle, from where it enters the screen to where it leaves
	var th := R.range(0.42, 0.56)
	ux = cos(th)
	uy = sin(th)
	nx = uy
	ny = -ux
	cx = W / 2.0 + R.range(-24, 24)
	cy = H / 2.0 + R.range(-10, 10)
	# the halves overhang the screen a little, so slipping along the cut never uncovers an edge
	var area := [[-24.0, -24.0], [W + 24.0, -24.0], [W + 24.0, H + 24.0], [-24.0, H + 24.0]]
	var ends := []
	for s in [-1.0, 1.0]:
		# walk out along the cut until it leaves the screen
		var lo := 0.0
		var hi := 400.0
		for k in 30:
			var m := (lo + hi) / 2.0
			var x: float = cx + s * ux * m
			var y: float = cy + s * uy * m
			if x >= 0.0 and x <= W and y >= 0.0 and y <= H:
				lo = m
			else:
				hi = m
		ends.append([cx + s * ux * lo, cy + s * uy * lo])
	A = ends[0]
	B = ends[1]
	LC = Px.hypot(B[0] - A[0], B[1] - A[1])
	halves = []
	for s in [1.0, -1.0]:
		var pts := Lib.halfPlane(area, cx, cy, s * nx, s * ny)
		var mx := 0.0
		var my := 0.0
		for q in pts:
			mx += q[0] / pts.size()
			my += q[1] / pts.size()
		halves.append({"s": s, "pts": pts, "mx": mx, "my": my, "spin": s * R.range(0.5, 0.9)})
	t = 0.0
	acc = 0.0
	entered = false
	tipped = false
	split = false
	end = D - 0.05


# where a half of the cover is: it slips along the cut, then the halves fly apart, turning a little
func placeOf(hf: Dictionary) -> Dictionary:
	var slip := 5.0 * Px.Ease.outCubic(Px.clamp((t - SLIP) / 0.12)) * (1.0 if hf.s > 0.0 else -0.4)
	var u := maxf(0.0, t - SPLIT)
	var sep := 30.0 * u + 0.5 * 1500.0 * u * u
	var rot: float = hf.spin * u * u
	return {"dx": ux * slip + hf.s * nx * sep, "dy": uy * slip + hf.s * ny * sep, "rot": rot, "sep": sep}


func moved(hf: Dictionary, pl: Dictionary, q: Array) -> Array:
	var x: float = q[0]
	var y: float = q[1]
	var c := cos(pl.rot)
	var s := sin(pl.rot)
	var lx: float = x - hf.mx
	var ly: float = y - hf.my
	return [hf.mx + lx * c - ly * s + pl.dx, hf.my + lx * s + ly * c + pl.dy]


func update(dt: float) -> void:
	t += dt
	# the blade grinds through: sparks spray back over the cover, shavings flake off, light rides the edge
	var sp := speedAt(t)
	var e := edgeAt(t)
	if not entered and t >= T0:
		entered = true
		lights.add(4, 4, 60, C[5], 0.6, 0.25)
	# in bursts: each a fountain of sparks off one spot where the edge bites
	acc += sp * dt * 0.035
	while acc > 1.0:
		var y := R.range(4, H - 4)
		var x := xAt(e, y) - 1.0
		var a0 := PI + R.range(-0.1, 0.6)
		var nn := R.int_(5, 10)
		if x < 0.0 or x >= W:
			acc -= 1.0
			continue
		for i in nn:
			var a := a0 + R.range(-0.75, 0.75)
			var v := R.range(0.2, 1) * (140.0 + 0.22 * sp)
			ps.spawn(P.SPARK, x, y + R.range(-2, 2), cos(a) * v, sin(a) * v, R.range(0.15, 0.4))
			if R.chance(0.4):
				ps.spawn(P.MOTE, x, y, cos(a) * v * 0.45, sin(a) * v * 0.45 - 20.0, R.range(0.2, 0.5), C[6] if R.chance(0.5) else C[5], 0.7)
		lights.add(x, y, R.range(30, 46), C[5], 0.35, 0.14)
		acc -= 1.0
	# the second cut lands: a glint at its end, sparks thrown on along it, shavings off its length
	if not tipped and t >= CUT + CSW:
		tipped = true
		for i in 12:
			var a := atan2(uy, ux) + R.range(-0.5, 0.5)
			var v := R.range(150, 400)
			ps.spawn(P.SPARK, B[0] - ux * 2.0, B[1] - uy * 2.0, cos(a) * v, sin(a) * v, R.range(0.12, 0.35))
		for i in 18:
			var k := R.range(0.1, 1)
			var x: float = A[0] + (B[0] - A[0]) * k
			var y: float = A[1] + (B[1] - A[1]) * k
			var s := R.sign()
			var v := R.range(30, 100)
			ps.spawn(P.MOTE, x, y, s * nx * v + ux * 20.0, s * ny * v - 10.0, R.range(0.25, 0.55), C[5] if R.chance(0.5) else C[4], 0.6)
		for i in 5:
			lights.add(A[0] + (B[0] - A[0]) * (i + 0.5) / 5.0, A[1] + (B[1] - A[1]) * (i + 0.5) / 5.0, 46, C[5], 0.45, 0.3)
	# and the halves break apart: sparks spray out of the opening seam both ways
	if not split and t >= SPLIT:
		split = true
		for i in 46:
			var k := R.range(0, 1)
			var x: float = A[0] + (B[0] - A[0]) * k
			var y: float = A[1] + (B[1] - A[1]) * k
			var s := R.sign()
			var v := R.range(80, 320)
			var a := atan2(s * ny, s * nx) + R.range(-0.7, 0.7)
			ps.spawn(P.SPARK, x, y, cos(a) * v, sin(a) * v, minf(R.range(0.15, 0.45), end - t))
		for i in 6:
			lights.add(A[0] + (B[0] - A[0]) * (i + 0.5) / 6.0, A[1] + (B[1] - A[1]) * (i + 0.5) / 6.0, 56, C[5], 0.5, 0.35)
	ps.update(dt)
	lights.update(dt)


func draw(p0: Px.Painter) -> void:
	var p := Lib.clipTo(p0)
	if t < CUT + CSW + CHOLD + 0.02 or t < SLIP:
		# the cover behind the blade, row by row: ink, then the smear cooling from the white-hot edge, light ahead
		var e := edgeAt(t)
		var sp := speedAt(t)
		var Ls := Px.clamp(sp * 0.0065, 1.5, 8.0)
		var echo := Px.clamp(sp / 900.0) * 0.6
		for y in H:
			var xe := xAt(e, y + 0.5)
			var ia := Px.clamp(floorf(xe - (Ls + 10.0) / CS), 0.0, W)
			var ib := Px.clamp(ceilf(xe + HALO / CS), 0.0, W)
			if ia > 0.0:
				Lib.rect(p0, 0.0, y, ia, 1.0, ink)
			for x in range(int(ia), int(ib)):
				var d := (xe - (x + 0.5)) * CS
				if d < 0.0:
					var u := 1.0 + d / HALO
					p0.light(x, y, C[5], 0.32 * u * u)
					if d > -4.0:
						p0.light(x, y, WHITE, 0.3 * (1.0 + d / 4.0) ** 2)
					continue
				if d < 1.0:
					p0.px(x, y, WHITE)
				elif d < 2.0:
					p0.px(x, y, C[6])
				else:
					var q := (d - 2.0) / Ls
					p0.px(x, y, C[5] if q < 0.3 else (C[4] if q < 0.55 else (C[3] if q < 0.8 else (C[2] if q < 1.0 else ink))))
					# a dotted trace a beat behind the edge, while it's moving fast
					if echo > 0.0 and absf(d - Ls - 7.0) < 0.5 and (x + y) % 3 == 0:
						p0.dot(x, y, C[4], echo)
				if d < Ls + 2.0:
					p0.light(x, y, C[5], 0.3 * (1.0 - d / (Ls + 2.0)))
	if t >= SLIP:
		# the two halves: dark, their cut edges white-hot and cooling to ice; light pours out of the seam
		var heat := 1.0 - Px.clamp((t - CUT - 0.05) / 0.5)
		for hf: Dictionary in halves:
			var pl := placeOf(hf)
			var pts := []
			for q in hf.pts:
				pts.append(moved(hf, pl, q))
			var a := moved(hf, pl, A)
			var b := moved(hf, pl, B)
			# the cut face of this half: white-hot at the edge, cooling and narrowing to an ice rim
			var c := cos(pl.rot)
			var sn := sin(pl.rot)
			var mx: float = hf.s * (nx * c - ny * sn)
			var my: float = hf.s * (nx * sn + ny * c)
			var rim := [WHITE if heat > 0.55 else (C[6] if heat > 0.25 else C[5]), C[6] if heat > 0.4 else C[4], C[5] if heat > 0.3 else C[3], C[4] if heat > 0.3 else ink]
			var deep := Px.clamp(1.0 + pl.sep * 0.5, 1.0, 4.0)  # the cut face shows more as the halves part
			var a0: float = a[0]
			var a1: float = a[1]
			var C5: int = C[5]
			var ink_ := ink
			Lib.fillConvex(p0, pts, func(x: float, y: float) -> Variant:
				var d := (x - a0) * mx + (y - a1) * my
				if d < deep:
					if d < 2.0:
						p0.light(x, y, C5, 0.4 * heat * (1.0 - d / 2.0))
					return rim[maxi(0, floori(d))]
				return ink_)
			if heat > 0.0:
				for i in 8:
					var k := (i + 0.5) / 8.0
					p.glow(a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, 12.0 + pl.sep * 0.15, C[5], 0.3 * heat)
	# the second cut: a smear that rips along the line, thickest just behind its head, white at its core,
	# cooling down the ramp, its tail dissolving; a dotted trace where it's gone; light riding its head
	var u := t - CUT
	if u >= 0.0 and u < CSW + CHOLD + CTRAIL + 0.25:
		var head := LC * Px.Ease.outExpo(Px.clamp(u / CSW))
		var tail := LC * Px.smooth(CSW + CHOLD, CSW + CHOLD + CTRAIL, u)
		var age := Px.clamp(u / (CSW + CHOLD + CTRAIL))
		var Wc := 3.6 * (1.0 - (tail / LC) * 0.55)
		var span := head - tail
		var sn := absf(nx)
		if span > 1.0 and tail < LC - 1.0 and t < SPLIT:
			for y in H:
				# the cut crosses row y at x0; the smear spans Wc either side of it, measured square to the cut
				var x0: float = A[0] + ((y + 0.5 - A[1]) * ux) / uy
				var hw := (Wc + 1.0) / sn
				for x in range(int(maxf(0.0, floorf(x0 - hw))), int(minf(W, ceilf(x0 + hw)))):
					var px: float = x + 0.5 - A[0]
					var py: float = y + 0.5 - A[1]
					var s := px * ux + py * uy
					var v := (s - tail) / span
					if v < 0.0 or v > 1.0:
						continue
					var w := Wc * pow(sin(PI * pow(v, 2.2)), 0.6)
					if w < 0.35:
						continue
					var q := absf(px * nx + py * ny) / w
					if q > 1.0:
						continue
					var ci := 0.0 if (q < 0.34 and age < 0.5) else Px.round(q * (n - 1) * 0.75 + age * 2.4 - v * 0.8 + 0.4)
					p0.dot(x, y, C[n - 1 - int(Px.clamp(ci, 0.0, n - 1))], minf(1.0, v / 0.4))
					if q < 0.5:
						p0.light(x, y, C[5], 0.4 * (1.0 - age))
		# the trace it leaves behind, until the cover parts
		if tail > 2.0 and t < SPLIT:
			var s := 0.0
			while s < tail:
				p.dot(A[0] + ux * s, A[1] + uy * s, C[5], 0.7 * (0.4 + (0.6 * s) / LC))
				s += 1.6
		if u < 0.3:
			var hx: float = A[0] + ux * head
			var hy: float = A[1] + uy * head
			p.glow(hx, hy, 46.0, C[4], 0.55 * (1.0 - u / 0.3))
		var g := u - CSW * 0.6
		if g > 0.0 and g < 0.24:
			Px.sparkle(p, B[0] - ux * 3.0, B[1] - uy * 3.0, 11.0 * Px.Ease.outBack(minf(1.0, g / 0.05)) * (1.0 - g / 0.24), C[6], C[4], 0.7)
	ps.draw(p)
	lights.draw(p)
