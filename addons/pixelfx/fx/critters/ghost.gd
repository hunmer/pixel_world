# port-of: src/fx/critters/ghost.js@d50863cfe7cc0590910d3b14631e64c0b0d0cbaf
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Ghost",
	"desc": "A sheet ghost bobs over the floor: its scalloped hem ripples and trails its drift, little arms flutter, it glances about and blinks, motes trickle off its hem.",
	"tags": ["critter", "ghost", "spirit", "undead", "spooky", "float", "loop"],
	"size": [96, 100],
	"origin": [48, 90],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#10142a", "#232c52", "#3e4f86", "#6b84bb", "#a3b8e2", "#d8e4ff", "#ffffff"], "hover": 14, "seed": 1},
}

static var D: float = meta.duration
static var GRID := Lib.Grid.new(-20, -40, 40, 46)
const R := 10.5


# where the ghost is: a lazy drift side to side and a bob, both looping
static func at(t: float, hover: float) -> Dictionary:
	var a := (t / D) * TAU
	return {"x": 4.0 * sin(a), "y": -hover - 3.0 * sin(2.0 * a + 0.8)}


# the sheet's half-width v px above the hem (0 hem .. 1 crown): a dome over a body that flares toward the hem
static func halfW(h: float) -> float:
	var top := 2.0 * R + 9.0
	if h > top or h < -1.0:
		return -1.0
	if h > top - R:
		return sqrt(maxf(0.0, R * R - (h - (top - R)) ** 2))
	return Px.lerp(R + 2.2, R, (h / (top - R)) ** 0.7)


static func sheet(g: Lib.Grid, C: Array, t: float, o: Dictionary, lagX: float) -> Dictionary:
	g.clear()
	var top := 2.0 * R + 9.0
	var ph := (t / D) * TAU * 2.0
	var NL := 4
	var HW := R + 2.2
	var LW := (2.0 * HW) / NL
	# the lower sheet trails behind the head as it drifts
	var off := func(h: float) -> float: return lagX * (1.0 - Px.clamp(h / top)) ** 1.4
	# four rounded lobes along the hem, lifting one after another in a ripple
	var lobe := func(X: float) -> Dictionary:
		var j := Px.clamp(floorf((X + HW) / LW), 0.0, NL - 1)
		var c := -HW + (j + 0.5) * LW
		var u := (X - c) / (LW / 2.0)
		return {"j": j, "u": u, "d": (2.2 + 1.1 * sin(ph - j * 1.5)) * sqrt(maxf(0.0, 1.0 - u * u))}
	var inside := func(x: float, y: float) -> bool:
		var h := -y
		var X: float = x - off.call(h)
		if h < 0.0 and -h > lobe.call(X).d:
			return false
		var hw := halfW(maxf(0.0, h))
		return hw >= 0.0 and absf(X) <= hw
	# little arms: rounded nubs that flutter
	var arm := func(x: float, y: float) -> bool:
		for s in [-1.0, 1.0]:
			var ax: float = s * (R + 1.2) + off.call(13.0)
			var ay: float = -13.0 + 1.6 * sin(ph + s * 1.3)
			if ((x - ax) / 3.0) ** 2 + ((y - ay) / 2.2) ** 2 <= 1.0:
				return true
		return false
	var any := func(x: float, y: float) -> bool: return inside.call(x, y) or arm.call(x, y)
	var lx := -9.0
	var ly := -top - 1.0
	var lit := func(x: float, y: float, k: float) -> bool: return any.call(lx + (x - lx) / k, ly + (y - ly) / k)
	g.shade(-19.0, -top - 2.0, 19.0, 5.0, func(x, y, o2):
		if not any.call(x, y):
			return 0
		var h: float = -y
		var X: float = x - off.call(h)
		var i := 5 if lit.call(x, y, 0.62) else 4
		if not any.call(x + 2.4, y + 1.8):
			i = 3
		if not any.call(x + 1.2, y + 1.0) and X > 2.0:
			i = 2
		# the gloss: a thin bright arc just inside the top-left of the dome
		if h > top - R - 2.0 and X < 1.0 and not any.call(x - 1.5, y - 1.5) and any.call(x - 0.6, y - 0.6):
			i = 6
		# the hem: each lobe darker underneath and to its right, a crease where two lobes meet
		if h < 1.0:
			var L: Dictionary = lobe.call(X)
			if L.u > 0.1 or -h > L.d - 1.2:
				i = mini(i, 3)
		# folds: short creases running down into the notches between the lobes, lit on their left
		if h < 7.0 and h >= -0.5:
			for j in range(1, NL):
				var cx := -HW + j * LW + 0.6 * sin(ph - j)
				var w := (7.0 - h) * 0.09
				if absf(X - cx) <= w + 0.3:
					i = mini(i, 3)
				elif cx - X > w + 0.3 and cx - X < w + 1.3 and i == 4:
					i = 5
		o2.a = 0.86 if h < 2.0 else 0.95
		return C[i])
	return {"inside": inside, "off": off, "top": top}


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var S := at(t, o.hover)
	var lagX: float = at(t - 0.3, o.hover).x - S.x
	var g := GRID
	var sh := sheet(g, C, t, o, lagX)
	var top: float = sh.top
	# the face: two eyes that glance about and blink, a little mouth that oohs
	var look := 0.0 if Px.wrap(t, D) < 0.7 else (1.0 if Px.wrap(t, D) < 1.3 else (-1.0 if Px.wrap(t, D) < 1.9 else 0.0))
	var blink := Px.wrap(t, D) > 1.95 and Px.wrap(t, D) < 2.03
	var ey := -top + R - 1.0
	var mo := 0.5 + 0.5 * sin((t / D) * TAU * 2.0)
	for s in [-1.0, 1.0]:
		var ex: float = s * 4.0 - (1.0 if s > 0.0 else 0.0) + look
		if blink:
			g.setc(ex, ey + 2.0, C[1])
			g.setc(ex + 1.0, ey + 2.0, C[1])
		else:
			for k in 4:
				g.setc(ex, ey + k, C[0])
				g.setc(ex + 1.0, ey + k, C[0])
			g.setc(ex + (0.0 if look < 0.0 else 1.0), ey, C[2])
	var my := ey + 6.0
	g.setc(look - 1.0, my, C[1])
	g.setc(look, my, C[1])
	if mo > 0.4:
		g.setc(look - 1.0, my + 1.0, C[0])
		g.setc(look, my + 1.0, C[0])
	g.outline(func(x, y, nx, ny): return C[2] if ny > 0.0 else C[1], 0.95)
	g.draw(p, 1.0, S.x, S.y)
	# motes trickle off the hem and fade as they sink and drift
	Px.cycle(t, D, 12, o.seed * 3 + 1, func(r): return r.range(1.0, 1.7), func(age, L, r, i):
		var S0 := at(Px.wrap(t - age, D), o.hover)
		var k: float = age / L
		var x0: float = S0.x + r.range(-10.0, 10.0)
		var y0: float = S0.y + 1.5
		var x: float = x0 + sin(age * 2.2 + i) * 2.4
		var y: float = y0 + r.range(5.0, 11.0) * age - 3.0 * age * age
		var a := minf(1.0, k * 6.0) * minf(1.0, (1.0 - k) * 2.2)
		var tw: float = 0.6 + 0.4 * sin(age * 8.0 + i * 1.7)
		p.dot(x, y, C[6] if tw > 0.8 else C[5], a)
		if r.chance(0.3):
			p.dot(x, y - 1.0, C[4], a * 0.7)
		p.glow(x, y, 7.0, C[4], 0.42 * a * tw))
	# a cold glow round it
	p.glow(S.x, S.y - top * 0.55, 54.0, C[3], 0.3)
	p.glow(S.x - 3.0, S.y - top * 0.72, 14.0, C[5], 0.12)


static func drawBack(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var S := at(t, o.hover)
	var hgt := Px.clamp((-S.y - 8.0) / 16.0)
	# its shadow on the floor, and the floor lit cold under it
	Lib.shadow(p, S.x, 0.0, 11.0 - 3.0 * hgt, 1.6, C[0], 0.55 - 0.2 * hgt)
	for x in range(-24, 25, 6):
		p.glow(S.x + x, -1.0, 16.0, C[4], 0.14 * (1.0 - absf(x) / 34.0) * (1.0 - 0.4 * hgt))
