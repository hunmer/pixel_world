# port-of: src/fx/holy/divine-shield.js@0fb54d67ab10c4b06c3255562c441a709480fbe2
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Divine shield",
	"desc": "A bubble of gold light round the character: a bright rim and a thin gold film, meridians turning like a slow globe, a sheen sweeping across and sparkles winking on it.",
	"tags": ["holy", "shield", "bubble", "barrier", "buff", "character", "loop"],
	"size": [88, 84],
	"origin": [44, 68],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Lib.GOLD, "radius": 29, "seed": 8},
}

static var BRACE := {"turn": 0.7, "crouch": 3, "lean": 1, "fx": 5, "fy": -33, "bx": 10, "by": -20, "ffx": 4, "fbx": -2}
static var act := {
	"onBody": true,
	"poses": [
		[0, BRACE],
		[0.6, Px.merge(BRACE, {"crouch": 4})],
		[1.2, Px.merge(BRACE, {"fy": -35, "crouch": 3})],
		[1.8, Px.merge(BRACE, {"crouch": 4})],
		[2.4, BRACE],
	],
}

const CY := -22.0
const TILT := 0.34
const N := 4.0
const FLOOR_SY := 0.26

# a point of the sphere (lat, lon) seen from a little above: screen x, y and depth z (> 0 faces us)
static func onSphere(r: float, lat: float, lon: float) -> Array:
	var X := r * cos(lat) * sin(lon)
	var Y := r * sin(lat)
	var Z := r * cos(lat) * cos(lon)
	return [X, CY - (Y * cos(TILT) - Z * sin(TILT)), Y * sin(TILT) + Z * cos(TILT)]


# the sheen: a diagonal band crossing the bubble once a loop, then a rest
static func sheen(t: float, T: float) -> float:
	return -1.7 + 3.4 * Px.clamp(fmod(t / T, 1.0) / 0.55)


static func lattice(p: Px.Painter, t: float, o: Dictionary, back: bool) -> void:
	var C := Px.fit(o.palette, 8)
	var r: float = o.radius
	var T: float = meta.duration
	var phi := (t / T) * (PI / N)
	var sw := sheen(t, T)
	var seen := {}
	# gather the lines' pixels first, so each is drawn once
	var dot := func(xyz: Array) -> void:
		var x: float = xyz[0]
		var y: float = xyz[1]
		var z: float = xyz[2]
		if (z < 0.0) != back:
			return
		var key := floori(x) * 1000 + floori(y)
		var f := absf(z) / r
		var q := (x - (y - CY)) / (r * 1.414)
		var hot := 1 if absf(q - sw) < 0.12 else 0
		var v: Variant = seen.get(key)
		if not v or f < v[2]:
			seen[key] = [x, y, f, hot if hot else (v[3] if v else 0)]
	# meridians, turning
	for k in int(2 * N):
		var lon := phi + (k * PI) / N
		var lat := -PI / 2.0
		while lat <= PI / 2.0:
			dot.call(onSphere(r, lat, lon))
			lat += 0.7 / r
	# the equator
	var lon := 0.0
	while lon < TAU:
		dot.call(onSphere(r, 0.0, lon))
		lon += 0.7 / r
	# behind: faint and broken. In front: bright where the surface turns away, a translucent wash of gold
	# where it faces us, so the character still shows through
	for e: Array in seen.values():
		var x: float = e[0]
		var y: float = e[1]
		var f: float = e[2]
		var hot: int = e[3]
		if back:
			p.blend(x, y, C[4], 0.32)
		elif hot:
			p.px(x, y, WHITE)
		elif f < 0.4:
			p.px(x, y, C[6])
		else:
			p.blend(x, y, C[6] if f < 0.7 else C[5], 0.8 if f < 0.7 else 0.55)


static func film(p: Px.Painter, t: float, o: Dictionary, back: bool) -> void:
	var C := Px.fit(o.palette, 8)
	var r: float = o.radius
	var sw := sheen(t, meta.duration)
	p.each(-r - 1.0, CY - r - 1.0, r + 1.0, CY + r + 1.0, func(x: float, y: float, sx: int, sy: int) -> void:
		var d := Px.hypot(x, y - CY) / r
		if d >= 1.0:
			return
		var q := (x - (y - CY)) / (r * 1.414)
		var hot := maxf(0.0, 1.0 - absf(q - sw) / 0.22)
		var a := (0.07 if back else 0.03) + 0.26 * pow(d, 6.0) + 0.2 * hot * (0.3 if back else 1.0)
		p.blendPx(sx, sy, C[6] if (hot > 0.5 and not back) else C[5], a))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var r: float = o.radius
	var rf := sqrt(r * r - CY * CY)
	film(p, t, o, true)
	lattice(p, t, o, true)
	# where it meets the floor: the far half of a bright seal
	Lib.oval(p, 0.0, 0.0, rf, rf * FLOOR_SY, C[5], 0.8, func(g): return sin(g) < 0.0)
	p.glow(0.0, CY, r * 1.1, C[4], 0.14)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var r: float = o.radius
	var T: float = meta.duration
	var rf := sqrt(r * r - CY * CY)
	var A: Variant = o.get("actor")
	# the bubble lights the character from all round
	if A:
		for xy: Array in Lib.shapeOf(A).out:
			p.light(xy[0], xy[1], C[5], 0.3)
	film(p, t, o, false)
	lattice(p, t, o, false)
	# the rim: bright where the light sits (top left) and where the sheen crosses it
	var sw := sheen(t, T)
	var n := ceilf(r * TAU * 1.4)
	var j := 0
	while j < n:
		var g := (j / n) * TAU
		var x := cos(g) * r
		var y := CY + sin(g) * r
		var q := (x - (y - CY)) / (r * 1.414)
		var lit := cos(g + 2.36)
		var hot := absf(q - sw) < 0.15
		p.dot(x, y, WHITE if (hot or lit > 0.75) else (C[6] if lit > -0.2 else C[5]), 1.0)
		p.dot(cos(g) * (r - 1.0), CY + sin(g) * (r - 1.0), C[4], 0.35 + 0.3 * lit)
		j += 1
	p.glowRing(0.0, CY, r, 6.0, C[4], 0.32)
	# where the meridians cross the equator, and at the pole they all turn round, the lattice catches the light
	var phi := (t / T) * (PI / N)
	for k in int(2 * N):
		var xyz := onSphere(r, 0.0, phi + (k * PI) / N)
		var x: float = xyz[0]
		var y: float = xyz[1]
		var z: float = xyz[2]
		if z < r * 0.15:
			continue
		p.px(x, y, WHITE)
		if z > r * 0.45:
			for dd: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				p.blend(x + dd[0], y + dd[1], C[6], 0.7)
		p.glow(x, y, 4.0, C[5], 0.3)
	var p0 := onSphere(r, PI / 2.0, 0.0)
	Px.sparkle(p, p0[0], p0[1], 2.0 + Px.round(1.5 + 1.5 * sin((t / T) * TAU * 2.0)), WHITE, C[6], 0.45)
	# two glints chase each other round the rim
	for off: float in [0.0, PI]:
		var g := (t / T) * TAU + off + 0.8
		Px.sparkle(p, cos(g) * r, CY + sin(g) * r, 2.0, WHITE, C[6], 0.4)
	# a bubble's shine: a bright curl up on the left, a dot under it, a faint one low on the right
	var g := 3.55
	while g < 4.2:
		p.px(cos(g) * r * 0.74, CY + sin(g) * r * 0.74, WHITE if (g > 3.7 and g < 4.05) else C[6])
		g += 0.04
	p.px(cos(3.4) * r * 0.62, CY + sin(3.4) * r * 0.62, WHITE)
	g = 0.45
	while g < 0.8:
		p.dot(cos(g) * r * 0.8, CY + sin(g) * r * 0.8, C[5], 0.6)
		g += 0.05
	# the near half of the floor seal and a pool of light
	Lib.oval(p, 0.0, 0.0, rf, rf * FLOOR_SY, func(gg): return WHITE if sin(gg) > 0.6 else C[6], 1.0, func(gg): return sin(gg) >= 0.0)
	for i in range(-2, 3):
		p.glow(i * rf * 0.5, 0.0, 12.0, C[4], 0.18)
	# sparkles winking on its skin as it turns, motes rising inside
	Px.cycle(t, T, 9, o.seed, func(gg): return gg.range(0.35, 0.6), func(age, life, R):
		var xyz := onSphere(r, R.range(-1.2, 1.3), R.range(0.0, TAU) + phi)
		var k := sin((age / life) * PI)
		if xyz[2] < 0.0:
			return
		Px.sparkle(p, xyz[0], xyz[1], 1.0 + 2.5 * k * R.range(0.6, 1.0), WHITE, C[6], 0.45 * k))
	Px.cycle(t, T, 12, o.seed + 1, func(gg): return gg.range(1.2, 2.2), func(age, life, R):
		var x0: float = R.range(-0.7, 0.7) * r
		var u: float = age / life
		var x: float = x0 + sin(u * 6.0 + R.range(0.0, 6.0)) * 2.0
		var y := CY + r * 0.75 - u * r * 1.4
		if Px.hypot(x, y - CY) > r - 2.0:
			return
		p.dot(x, y, C[6] if u < 0.5 else C[5], sin(u * PI))
		p.light(x, y, C[5], 0.4 * sin(u * PI)))
