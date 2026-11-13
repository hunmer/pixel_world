# port-of: src/fx/critters/bat.js@bb60862a9fe26d3e00fe58773a460dbcd266bc5c
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Bat",
	"desc": "A bat flaps in four snappy wing frames along a figure-eight, its body lifting on each downbeat, moonlight on its wing bones, red eyes glowing and glinting.",
	"tags": ["critter", "bat", "night", "flying", "spooky", "loop"],
	"size": [112, 80],
	"origin": [56, 40],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {"palette": ["#0c0912", "#1f1629", "#382645", "#5b3f66", "#866089", "#b88fb0", "#e8cfe0"], "eyes": ["#8a1020", "#ff3b30", "#ffb04a", "#fff0c0"], "seed": 1},
}

static var D: float = meta.duration
const FLAPS := 6.0
static var GRID := Lib.Grid.new(-24, -22, 48, 40)
# the four wing frames for the right wing: arm angle and length, three fingers' angles and lengths, the lift
const FRAMES := [
	{"arm": -58.0, "al": 8.0, "f": [-112.0, -76.0, -38.0], "fl": [9.0, 11.0, 9.0], "lift": 1.0},
	{"arm": -18.0, "al": 9.0, "f": [-40.0, -12.0, 16.0], "fl": [10.0, 11.0, 9.0], "lift": 0.0},
	{"arm": 28.0, "al": 8.0, "f": [50.0, 72.0, 94.0], "fl": [9.0, 10.0, 8.0], "lift": -2.0},
	{"arm": -42.0, "al": 6.0, "f": [-66.0, -38.0, -10.0], "fl": [7.0, 8.0, 6.0], "lift": -1.0},
]


static func rad(d: float) -> float:
	return (d * PI) / 180.0


# figure-eight flight, and which wing frame it's on
static func at(t: float) -> Dictionary:
	var a := (t / D) * TAU
	return {"x": 22.0 * sin(a), "y": 7.0 * sin(2.0 * a), "vx": cos(a)}


static func frameAt(t: float) -> int:
	return floori(Px.wrap((t / D) * FLAPS, 1.0) * 4.0) % 4


static func wingPts(F: Dictionary, s: float) -> Dictionary:
	var sh := [s * 2.5, -2.0]
	var ar := rad(F.arm)
	var wr := [sh[0] + s * cos(ar) * F.al, sh[1] + sin(ar) * F.al]
	var tips := []
	for i in F.f.size():
		var d: float = F.f[i]
		tips.append([wr[0] + s * cos(rad(d)) * F.fl[i], wr[1] + sin(rad(d)) * F.fl[i]])
	var pull := func(a: Array, b: Array, k: float) -> Array:
		return [Px.lerp((a[0] + b[0]) / 2.0, wr[0], k), Px.lerp((a[1] + b[1]) / 2.0, wr[1], k)]
	var hip := [s * 2.0, 3.5]
	return {"sh": sh, "wr": wr, "tips": tips, "hip": hip, "poly": [sh, wr, tips[0], pull.call(tips[0], tips[1], 0.22), tips[1], pull.call(tips[1], tips[2], 0.22), tips[2], pull.call(tips[2], hip, 0.38), hip]}


static func bat(g: Lib.Grid, C: Array, E: Array, F: Dictionary, t: float) -> void:
	g.clear()
	# wings: a membrane, darker near the body, lit along the leading edge; finger bones over it
	for s in [-1.0, 1.0]:
		var w := wingPts(F, s)
		var lead := func(x: float, y: float) -> float:
			var ax: float = w.wr[0]
			var ay: float = w.wr[1]
			var bx: float = w.tips[0][0]
			var by: float = w.tips[0][1]
			var dx := bx - ax
			var dy := by - ay
			var L := Px.hypot(dx, dy)
			if not L:
				L = 1.0
			return absf(((x - ax) * dy - (y - ay) * dx) / L)
		g.poly(w.poly, func(x, y):
			var near := Px.hypot(x - w.sh[0], y - w.sh[1])
			if lead.call(x, y) < 1.2 and F.arm < 20.0:
				return C[3]
			return C[1] if near < 4.5 else C[2])
		g.line(w.sh[0], w.sh[1], w.wr[0], w.wr[1], C[4])
		for tip in w.tips:
			g.line(w.wr[0], w.wr[1], tip[0], tip[1], func(u): return C[4] if u < 0.6 else C[3])
		g.setc(w.wr[0], w.wr[1] - 1.0, C[5])
	# the body: fur lit top-left, a paler belly, big ears with pink insides
	g.ellipse(0.0, 0.5, 3.8, 4.8, func(nx, ny): return C[4] if nx * -0.6 + ny * -0.8 > 0.45 else (C[2] if nx * 0.6 + ny * 0.8 > 0.55 else (C[4] if ny > 0.1 and absf(nx) < 0.5 else C[3])))
	for s in [-1.0, 1.0]:
		g.poly([[s * 0.6, -3.5], [s * 3.6, -9.5], [s * 3.8, -3.0]], C[4] if s < 0.0 else C[3])
		g.line(s * 2.6, -4.0, s * 3.2, -7.5, C[5])
	# eyes, a snout, two fangs, tucked feet
	g.setc(-2, -1, E[1])
	g.setc(1, -1, E[1])
	g.setc(-1, 0, C[1])
	g.setc(0, 0, C[1])
	g.setc(-1, 1, C[6])
	g.setc(0, 1, C[6])
	g.setc(-2, 5, C[3])
	g.setc(1, 5, C[3])
	g.outline(C[0])


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var E := Px.fit(o.eyes, 4)
	var S := at(t)
	var fi := frameAt(t)
	var F: Dictionary = FRAMES[fi]
	var X := Px.round(S.x)
	var Y := Px.round(S.y + F.lift)
	# its glowing eyes leave a fading streak of red light along its flight
	for k in range(2, 17):
		var A := at(t - (k - 1) * 0.022)
		var B2 := at(t - k * 0.022)
		var u := 1.0 - k / 17.0
		for ex in [-1.5, 1.5]:
			p.glowLine(A.x + ex, A.y - 0.5, B2.x + ex, B2.y - 0.5, 2.6, E[1], 0.16 * u)
	# moonlit dust drifting in the night air
	Px.cycle(t, D, 9, o.seed * 11 + 1, D, func(age, L, r):
		var x: float = r.range(-50.0, 50.0) + sin(age * 1.1 + r.next() * 6.0) * 3.0
		var y: float = r.range(-34.0, 34.0) + age * r.range(-2.0, 3.0)
		var tw: float = sin(age * 2.6 + r.next() * 6.0)
		var a: float = minf(minf(1.0, age * 2.0), (L - age) * 2.0) * (0.4 + 0.5 * tw)
		p.dot(x, y, C[6] if tw > 0.7 else C[5], a)
		if tw > 0.5:
			p.glow(x, y, 3.0, C[5], 0.2 * a))
	var g := GRID
	# on the downbeat the wings leave a see-through echo of where they just were
	if fi == 2:
		bat(g, C, E, FRAMES[1], t)
		g.recolor(func(x, y, c): return Px.mix(c, C[4], 0.35))
		g.a.fill(0.35)
		g.draw(p, 1.0, X, Y - FRAMES[1].lift + F.lift)
	bat(g, C, E, F, t)
	g.draw(p, 1.0, X, Y)
	# moonlight catches the top of the head and wings
	p.glow(X - 3.0, Y - 6.0, 10.0, C[5], 0.12)
	# the eyes glow, and glint now and then
	for ex in [-1.5, 1.5]:
		p.glow(X + ex, Y - 0.5, 7.0, E[1], 0.6)
		p.glow(X + ex, Y - 0.5, 2.5, E[2], 0.5)
	p.glow(X, Y, 22.0, E[0], 0.25)
	for g0 in [0.3, 1.5]:
		var k := (Px.wrap(t - g0, D)) / 0.24
		if k < 1.0:
			Px.sparkle(p, X - 2.0, Y - 1.0, 1.0 + 2.5 * sin(PI * k), E[3], E[2], 0.4 * sin(PI * k))
