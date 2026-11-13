# port-of: src/fx/critters/butterfly.js@ebb916c077997a34d948548b7680676e69a38530
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Butterfly",
	"desc": "An iridescent butterfly wanders a loop in bursts of quick wingbeats and open-winged glides, its veined, spotted wings shedding a twinkling trail of glowing dust.",
	"tags": ["critter", "butterfly", "insect", "flying", "magic", "glow", "loop"],
	"size": [128, 88],
	"origin": [64, 44],
	"duration": 3.2,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#0b0f24", "#16224f", "#1f3f8a", "#2f74c8", "#4fb4f0", "#a0e6ff", "#ffffff"],
		"spots": ["#3a1a08", "#c8641a", "#ffb43c", "#fff0b0"],
		"seed": 1,
	},
}

static var D: float = meta.duration
static var GRID := Lib.Grid.new(-22, -20, 44, 40)
# the right wings, unfolded, in px from the wing root (y forward is negative)
const FORE := [[0.0, -1.0], [3.0, -6.0], [8.0, -11.0], [13.0, -12.5], [16.5, -10.5], [16.5, -6.0], [13.0, -1.5], [7.0, 1.0], [2.0, 1.5]]
const HIND := [[0.0, 1.0], [6.0, 1.5], [11.0, 4.0], [12.5, 8.5], [10.5, 12.5], [6.5, 13.5], [3.0, 11.0], [0.5, 6.0]]

# flight: bursts of wingbeats (rising) and glides (sinking), wandering round a loop
const BURSTS := [[0.0, 0.95], [1.5, 2.55]]


static func flapping(t: float) -> bool:
	for q in BURSTS:
		var a: float = q[0]
		var b: float = q[1]
		if t >= a and t < b:
			return true
	return false


# the wing's fold, 1 flat open .. 0 edge-on: quick beats while flapping, held open while gliding
static func fold(t: float) -> float:
	t = Px.wrap(t, D)
	for q in BURSTS:
		var a: float = q[0]
		var b: float = q[1]
		if t >= a and t < b:
			var n := Px.round((b - a) * 6.3)
			var ph := ((t - a) / (b - a)) * n
			return 0.14 + 0.86 * (0.5 + 0.5 * cos(ph * TAU))
	return 1.0


static func at(t: float) -> Dictionary:
	t = Px.wrap(t, D)
	var a := (t / D) * TAU
	# a lift while it beats, a sink while it glides, so the path bobs in steps
	var lift := 0.0
	for q in BURSTS:
		var s: float = q[0]
		var e: float = q[1]
		lift += -3.0 * sin(PI * Px.clamp((t - s) / (e - s)))
	return {"x": 30.0 * sin(a) + 6.0 * sin(3.0 * a), "y": 12.0 * sin(2.0 * a + 0.4) + lift, "vx": cos(a)}


static func inPoly(pts: Array, x: float, y: float) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in pts.size():
		var xi: float = pts[i][0]
		var yi: float = pts[i][1]
		var xj: float = pts[j][0]
		var yj: float = pts[j][1]
		if (yi > y) != (yj > y) and x < ((xj - xi) * (y - yi)) / (yj - yi) + xi:
			inside = not inside
		j = i
	return inside


static func edgeDist(pts: Array, x: float, y: float) -> float:
	var m := INF
	var j := pts.size() - 1
	for i in pts.size():
		var ax: float = pts[j][0]
		var ay: float = pts[j][1]
		var bx: float = pts[i][0]
		var by: float = pts[i][1]
		var dx := bx - ax
		var dy := by - ay
		var L2 := dx * dx + dy * dy
		if not L2:
			L2 = 1.0
		var u := Px.clamp(((x - ax) * dx + (y - ay) * dy) / L2)
		var px := ax + dx * u - x
		var py := ay + dy * u - y
		m = minf(m, Px.hypot(px, py))
		j = i
	return m


# a wing's pattern at an unfolded point: dark at the root, iridescent blue brightest along the leading edge,
# thin dark veins, a black apex dotted white on the forewing, a gold eyespot on the hindwing
const FSPOTS := [[13.2, -10.2], [15.2, -8.4], [14.6, -5.6], [11.6, -11.4]]


static func wingColor(C: Array, Sp: Array, hind: bool, u: float, v: float) -> int:
	var pts: Array = HIND if hind else FORE
	var e := edgeDist(pts, u, v)
	var r := Px.hypot(u, v)
	var ang := atan2(v, u)
	if e < 1.0:
		return C[0]
	if not hind:
		if u + v * -0.45 > 14.2 or (r > 12.5 and v < -4.0):
			for q in FSPOTS:
				var sx: float = q[0]
				var sy: float = q[1]
				if Px.hypot(u - sx, v - sy) < 0.9:
					return C[6]
			return C[0]
	else:
		if e < 2.0 and r > 8.0:
			return C[5] if sin(ang * 10.0) > 0.5 else C[1]
		var d := Px.hypot(u - 7.6, v - 9.4)
		if d < 0.7:
			return C[6]
		if d < 1.4:
			return C[0]
		if d < 2.2:
			return Sp[2]
	for va in ([0.5, 1.0, 1.45] if hind else [-1.2, -0.75, -0.3]):
		if absf(ang - va) * r < 0.45 and r > 3.5:
			return C[1]
	if r < 3.0:
		return C[2]
	if r < 6.0:
		return C[3]
	if not hind and e < 2.4 and v < -3.0:
		return C[5]
	return C[4]


static func butterfly(g: Lib.Grid, C: Array, Sp: Array, w: float, t: float) -> void:
	g.clear()
	for s in [-1.0, 1.0]:
		for hind in [true, false]:
			var pts: Array = HIND if hind else FORE
			g.shade(-20.0, -15.0, 20.0, 16.0, func(x, y):
				if Px.sign(x + 0.001) != s:
					return 0
				var u: float = (absf(x) - 1.0) / w
				var v: float = y
				if u < 0.0 or not inPoly(pts, u, v):
					return 0
				var c := wingColor(C, Sp, hind, u, v)
				# folding up, the far side of each wing turns away from the light
				if w < 0.5 and c != C[0]:
					c = Px.mix(c, C[1], (0.5 - w) * 1.6)
				return c)
	# the body: a fuzzy thorax, a tapering abdomen, a round head, curled antennae with bright tips
	g.ellipse(0.0, 0.5, 1.6, 2.6, func(nx, ny): return C[3] if nx + ny < -0.4 else C[1])
	for y in range(3, 10):
		g.setc(-1, y, C[2] if y < 6 else C[1])
		if y < 8:
			g.setc(0, y, C[1])
	g.setc(-1, -3, C[3])
	g.setc(0, -3, C[2])
	g.setc(-1, -4, C[2])
	g.setc(0, -4, C[1])
	for s in [-1.0, 1.0]:
		var tip := [s * 4.0 - (0.0 if s > 0.0 else 1.0), -9.5]
		g.line(0.0 if s > 0.0 else -1.0, -5.0, tip[0], tip[1], C[2])
		g.setc(tip[0], tip[1], C[6])
	g.outline(func(x, y, nx, ny): return C[0])


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var Sp := Px.fit(o.spots, 4)
	var S := at(t)
	var w := fold(t)
	# a trail of glowing dust shaken off the wings, drifting down and twinkling out
	Px.cycle(t, D, 56, o.seed * 7 + 1, func(r): return r.range(1.0, 1.8), func(age, L, r, i):
		var born := Px.wrap(t - age, D)
		var B := at(born)
		var k: float = age / L
		if not flapping(born) and r.chance(0.45):
			return
		var x: float = B.x + r.range(-9.0, 9.0) + sin(age * 3.0 + i) * 1.5
		var y: float = B.y + r.range(-4.0, 8.0) + 7.0 * age + 3.0 * age * age
		var tw: float = 0.5 + 0.5 * sin(age * 11.0 + i * 2.1)
		var a := minf(1.0, k * 8.0) * (1.0 - k)
		p.dot(x, y, C[6] if tw > 0.7 else (Sp[2] if r.chance(0.3) else C[5]), a * 1.2)
		p.glow(x, y, 6.0, C[4], 0.5 * a * tw)
		if i % 9 == 0 and tw > 0.85 and k < 0.5:
			Px.sparkle(p, x, y, 2.0, C[6], C[5], 0.3 * a))
	var g := GRID
	butterfly(g, C, Sp, w, t)
	g.draw(p, 1.0, S.x, S.y)
	# the wings shine: a soft blue light round it, brighter when they open
	p.glow(S.x, S.y, 38.0, C[4], 0.16 + 0.14 * w)
	p.glow(S.x, S.y, 12.0, C[5], 0.12 + 0.1 * w)
