# The rays and the white-hearted glints follow Sprite Fusion's open-source sparkle
# (https://www.spritefusion.com/pixel-art-vfx/sparkle), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/power-star.js@03a5ab9dcb67f0ae26ece7ae9fbb36b81d89b711
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Power star",
	"desc": "A fat bevelled star rocks side to side and swells on each beat, rays of light turning slowly behind it, sparks spinning off its points.",
	"tags": ["pickup", "star", "power-up", "invincible", "bonus", "loop"],
	"size": [88, 84],
	"origin": [44, 76],
	"duration": 1.6,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#2a1604", "#5e3208", "#a05c0c", "#e09414", "#ffc626", "#ffe866", "#fff8c4", "#ffffff"], "seed": 9},
}

static var L := Lib.Layer.new(44, 44)
const HOVER := 25.0
const RO := 11.5
const RI := 5.2
static var INK := Px.hex("#1a0e04")
const BEATS := [0.25, 0.75]
const RAYS := 10
static var LA := atan2(-0.8, -0.6)


# a beat: it swells fast and settles slowly
static func swell(ph: float) -> float:
	var s := 0.0
	for b: float in BEATS:
		var u := fmod(fmod(ph - b, 1.0) + 1.0, 1.0)
		s += Px.exp(-u * 14.0) * (1.0 if 1.0 - u * 2.5 > 0.0 else 0.0)
	return s


# the star: five arms, each with a ridge down its middle, the two halves catching the light differently
static func star(p: Px.Painter, C: Array, cx: float, cy: float, rot: float, sc: float) -> void:
	L.begin(floorf(cx) - 21.0, floorf(cy) - 21.0)
	L.fill(floorf(cx) - 21.0, floorf(cy) - 21.0, floorf(cx) + 20.0, floorf(cy) + 20.0, func(px: float, py: float) -> Variant:
		var dx := (px - cx) / sc
		var dy := (py - cy) / sc
		var r := Px.hypot(dx, dy)
		if r > RO + 0.5:
			return 0
		var a := atan2(dy, dx) - rot + PI / 2.0
		a = fmod(fmod(a, TAU) + TAU, TAU)
		var k := floori(a / (PI / 5.0))
		var half := k % 2
		var tip := (floori(k / 2.0) + half) * ((2.0 * PI) / 5.0)
		# inside the edge from this arm's tip to the inner corner beside it
		var tA := tip - PI / 2.0 + rot
		var iA := tA + (-1.0 if half else 1.0) * (PI / 5.0)
		var tx := cos(tA) * RO
		var ty := sin(tA) * RO
		var ix := cos(iA) * RI
		var iy := sin(iA) * RI
		var ex := ix - tx
		var ey := iy - ty
		var side := (dx - tx) * ey - (dy - ty) * ex
		var cside := -tx * ey + ty * ex
		if side * cside < 0.0:
			return 0
		# the facet slopes down from the ridge towards the inner corner: light it by that direction
		var n := tA + (-1.0 if half else 1.0) * (PI / 2.0)
		var l := cos(n - LA)
		var ridge := absf(sin(atan2(dy, dx) - tA)) * r < 0.6
		if r < 1.2:
			return WHITE
		var toLight := cos(tA - LA)
		if ridge:
			return WHITE if toLight > 0.3 else (C[6] if toLight > -0.4 else C[5])
		return C[6 if l > 0.6 else (5 if l > 0.15 else (4 if l > -0.35 else (3 if l > -0.75 else 2)))])
	L.outline(INK).draw(p)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var ph := t / D
	var y := -HOVER - 1.5 * sin(ph * TAU * 2.0)
	var sw := swell(ph)
	Lib.blobShadow(p, 0.0, 9.0 + 2.0 * sw, 0.7)
	# rays turning behind it: long and short by turns, one ray's width a loop, swelling with the beat
	var spin := ph * ((TAU / RAYS) * 2.0)
	for i in RAYS:
		var a := spin + (i * TAU) / RAYS
		var len := (22.0 if i % 2 else 34.0) * (1.0 + 0.18 * sw)
		var ca := cos(a)
		var sa := sin(a)
		var w := 0.06 if i % 2 else 0.09
		p.shade(-len - 2.0, y - len - 2.0, len + 2.0, y + len + 2.0, func(x: float, yy: float, out) -> void:
			var rx := x
			var ry := yy - y
			var d := rx * ca + ry * sa
			if d < 8.0 or d > len:
				return
			var q := absf(rx * sa - ry * ca)
			var hw := 0.5 + d * w
			if q > hw + 1.5:
				return
			out.l = C[6] if q < hw * 0.5 else C[5]
			out.k = (0.32 + 0.22 * sw) * (1.0 if q < hw else 1.0 - (q - hw) / 1.5) * pow(1.0 - d / len, 1.2) * minf(1.0, (d - 8.0) / 4.0))
		# a fine bright line down each long ray
		if i % 2 == 0:
			# (clipped at the floor)
			var d0 := RO + 3.0
			var d1 := minf(len * 0.88, (-2.0 - y) / sa if sa > 0.05 else INF)
			if d1 > d0:
				p.line(ca * d0, y + sa * d0, ca * d1, y + sa * d1, func(u: float) -> int: return C[6] if u < 0.35 else C[5], func(u: float) -> float: return (1.0 if u < 0.5 else 1.6 - u * 1.4) * (0.75 + 0.35 * sw))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var ph := t / D
	var y := -HOVER - 1.5 * sin(ph * TAU * 2.0)
	var sw := swell(ph)
	var rot := 0.22 * sin(ph * TAU)
	var sc := 1.0 + 0.13 * sw
	p.glowRing(0.0, y, RO * sc + 3.0, 13.0, C[4], 0.32 + 0.25 * sw)
	p.glow(0.0, y, 6.0, C[6], 0.12 + 0.2 * sw)
	star(p, C, 0.0, y, rot, sc)
	# on each beat a spark spins off every point
	for b: float in BEATS:
		var age := fmod(fmod(ph - b, 1.0) + 1.0, 1.0) * D
		if age > 0.45:
			continue
		for i in 5:
			var a := rot + (i * TAU) / 5.0 - PI / 2.0
			var sp := 70.0 + Px.rand(i, b * 10.0, 3) * 30.0
			var tan_ := 35.0
			var vx := cos(a) * sp - sin(a) * tan_
			var vy := sin(a) * sp + cos(a) * tan_
			var xy := Px.fly(cos(a) * RO * sc, y + sin(a) * RO * sc, vx, vy, age, 60.0, 4.0)
			var k := 1.0 - age / 0.45
			Lib.glint(p, xy[0], xy[1], Px.round(2.0 * k), WHITE if k > 0.5 else C[6], 0.45 * k)
	# specks of light winking round it, and small stars popping one after another
	var f := floorf(ph * 24.0)
	for i in 18:
		if Px.rand(f + i * 3, i, o.seed) > 0.32:
			continue
		var a := Px.rand(i, 1, o.seed) * TAU
		var d := 13.0 + Px.rand(i, 2, o.seed) * 20.0
		var sy := y + sin(a) * d * 0.85
		if sy < -2.0:
			p.px(cos(a) * d, sy, WHITE if Px.rand(f, i, 5) < 0.5 else C[6])
	for i in 4:
		var life := 0.3
		var age := fmod(fmod(t - ((i + 0.3) / 4.0) * D, D) + D, D)
		if age > life:
			continue
		var a := Px.rand(i, 7, o.seed) * TAU
		var d := 15.0 + Px.rand(i, 8, o.seed) * 12.0
		var k := sin((age / life) * PI)
		Lib.glint(p, cos(a) * d, y + sin(a) * d * 0.85, Px.round(2.5 * k), C[6] if i % 2 else WHITE, 0.4 * k)
	# a glint on the top arm now and then
	var g := fmod(ph + 0.1, 0.5) / 0.5
	if g < 0.14:
		Lib.glint(p, -2.0 + rot * 4.0, y - 6.0, 3.0 * sin((g / 0.14) * PI), WHITE, 0.5)
