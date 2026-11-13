# A floating pickup that bobs, glints, glows and has motes circling in front and behind follows the recipe
# in Sprite Fusion's open-source pickup gem (https://www.spritefusion.com/pixel-art-vfx/pickup),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ice/ice-crystal.js@cf0330c93189518219ee68e86f6c49ee04ba2c1c
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Ice crystal",
	"desc": "A floating ice crystal turning slowly in its own cold light: its facets brighten and darken as they turn, glints flash on them, frost motes circle it.",
	"tags": ["ice", "crystal", "gem", "pickup", "float", "magic", "loop"],
	"size": [96, 100],
	"origin": [48, 92],
	"duration": 3,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "height": 34, "seed": 21},
}

const TIP := 0.28  # how far it leans toward us, so the upper facets show
static var LIGHT := norm([-0.55, -0.75, -0.45])  # toward the light: upper left, in front


static func norm(v: Array) -> Array:
	var x: float = v[0]
	var y: float = v[1]
	var z: float = v[2]
	var l := Px.hypot(x, y, z)
	if not l:
		l = 1.0
	return [x / l, y / l, z / l]


# the crystal: a hexagonal prism with a tall point above and a shorter one below, turned by th, tipped toward
# the viewer. Returns the visible faces (projected corners, brightness, glint) and the silhouette.
static func crystalFaces(th: float, R: float) -> Array:
	var ct := cos(TIP)
	var st := sin(TIP)
	var P := func(x: float, y: float, z: float) -> Array: return [x, y * ct - z * st, y * st + z * ct]  # tip toward the viewer (z toward us is negative)
	var ring := func(y: float) -> Array: return Px.arr(6, func(k: int) -> Array: return P.call(cos(th + (k * TAU) / 6.0) * R, y, sin(th + (k * TAU) / 6.0) * R))
	var top: Array = ring.call(-R * 0.45)
	var bot: Array = ring.call(R * 0.45)
	var A: Array = P.call(0.0, -R * 2.2, 0.0)
	var Z: Array = P.call(0.0, R * 1.7, 0.0)
	var faces := []
	for k in 6:
		var j := (k + 1) % 6
		faces.append([A, top[j], top[k]])
		faces.append([top[k], top[j], bot[j], bot[k]])
		faces.append([bot[k], bot[j], Z])
	var out := []
	for f: Array in faces:
		var a: Array = f[0]
		var b: Array = f[1]
		var c: Array = f[2]
		var u := [b[0] - a[0], b[1] - a[1], b[2] - a[2]]
		var v := [c[0] - a[0], c[1] - a[1], c[2] - a[2]]
		var n := norm([u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]])
		var cx: float = f.reduce(func(s, q): return s + q[0], 0.0) / f.size()
		var cy: float = f.reduce(func(s, q): return s + q[1], 0.0) / f.size()
		var cz: float = f.reduce(func(s, q): return s + q[2], 0.0) / f.size()
		if n[0] * cx + n[1] * cy + n[2] * cz < 0.0:
			n = n.map(func(q): return -q)  # outward
		if n[2] >= -0.02:
			continue  # facing away
		var lit := maxf(0.0, n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2])
		# a glint where the face mirrors the light toward the viewer (half way between the light and the eye)
		var h := norm([LIGHT[0], LIGHT[1], LIGHT[2] - 1.0])
		var spec := maxf(0.0, n[0] * h[0] + n[1] * h[1] + n[2] * h[2])
		out.append({"pts": f.map(func(q): return [q[0], q[1]]), "lit": lit, "spec": spec, "cx": cx, "cy": cy})
	return out


# the convex hull of a set of points (monotone chain), for the crystal's silhouette
static func hullOf(pts: Array) -> Array:
	var P := Px.sort(pts.duplicate(), func(a, b):
		var d: float = a[0] - b[0]
		return d if d else a[1] - b[1])
	var cross := func(o, a, b) -> float: return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
	var lo := []
	var hi := []
	for q in P:
		while lo.size() >= 2 and cross.call(lo[lo.size() - 2], lo[lo.size() - 1], q) <= 0.0:
			lo.pop_back()
		lo.append(q)
	P.reverse()
	for q in P:
		while hi.size() >= 2 and cross.call(hi[hi.size() - 2], hi[hi.size() - 1], q) <= 0.0:
			hi.pop_back()
		hi.append(q)
	return lo.slice(0, -1) + hi.slice(0, -1)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph: float = t / meta.duration
	var bob := sin(TAU * ph) * 2.5
	var Y: float = -o.height + bob
	# its shadow on the floor, smaller and darker as it dips, and a cold pool of light
	var s := 1.0 - bob / 12.0
	var rx := 11.0 * s
	var x := floorf(-rx)
	while x <= rx:
		var f := 1.0 - pow(x / rx, 2.0)
		p.blend(x + 0.5, 0.0, C[0], 0.65 * f)
		if absf(x) < rx * 0.6:
			p.blend(x + 0.5, 1.0, C[0], 0.4 * f)
		x += 1.0
	p.glow(0.0, -1.0, 24.0, C[4], 0.2 + 0.05 * sin(TAU * ph * 2.0))
	motes(p, C, t, o, Y, false)


static func motes(p: Px.Painter, C: Array, t: float, o: Dictionary, Y: float, front: bool) -> void:
	var D: float = meta.duration
	Px.cycle(t, D, 16, o.seed, func(g: Px.Rng) -> float: return g.range(1.6, 2.6), func(age: float, life: float, r: Px.Rng, i: int) -> void:
		var th := r.range(0.0, TAU) + age * r.range(1.6, 2.6)
		var R := r.range(14.0, 22.0)
		var y := Y + r.range(-14.0, 12.0) - age * r.range(3.0, 7.0)
		var s := sin(th)
		var k := age / life
		if (s >= 0.0) != front:
			return
		var x := cos(th) * R
		var yy := y + s * R * 0.3
		var a := minf(1.0, age / 0.2) * ((1.0 - k) / 0.25 if k > 0.75 else 1.0)
		if front:
			p.dot(x, yy, WHITE if i % 4 == 0 else C[6], a)
			if i % 4 == 0:
				for d: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					p.dot(x + d[0], yy + d[1], C[5], a)
			p.glow(x, yy, 4.0, C[5], 0.3 * a)
		else:
			p.dot(x, yy, C[4], a * 0.9))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph: float = t / meta.duration
	var bob := sin(TAU * ph) * 2.5
	var Y: float = -o.height + bob
	var R := 8.0
	# its own cold light
	p.glow(0.0, Y, 34.0, C[3], 0.26)
	p.glow(0.0, Y, 14.0, C[5], 0.18 + 0.08 * sin(TAU * ph * 3.0))
	# a sixth of a turn a loop: a hexagon looks the same after it, so the loop never seams
	var faces := crystalFaces((TAU / 6.0) * ph, R)
	# a dark rim round the silhouette, then the facets: deep in shadow, pale toward the light, white in a glint
	var all := []
	for f: Dictionary in faces:
		all.append_array(f.pts)
	var hull := hullOf(all)
	var mx := 0.0
	var my := 0.0
	for q: Array in hull:
		mx += q[0]
		my += q[1]
	mx /= hull.size()
	my /= hull.size()
	p.poly(hull.map(func(q: Array) -> Array:
		var x: float = q[0]
		var y: float = q[1]
		var d := Px.hypot(x - mx, y - my)
		if not d:
			d = 1.0
		return [x + ((x - mx) / d) * 1.2, y + Y + ((y - my) / d) * 1.2]), C[1])
	for f: Dictionary in faces:
		var c: int = WHITE if f.spec > 0.985 else C[int(Px.clamp(Px.round(1.0 + pow(f.lit, 1.4) * 6.6), 1.0, 7.0))]
		p.poly(f.pts.map(func(q: Array) -> Array: return [q[0], q[1] + Y]), c)
	# edges: pale where two faces meet, a dark rim round the outside, a white ridge on the lit side
	for f: Dictionary in faces:
		for i in f.pts.size():
			var x0: float = f.pts[i][0]
			var y0: float = f.pts[i][1]
			var x1: float = f.pts[(i + 1) % f.pts.size()][0]
			var y1: float = f.pts[(i + 1) % f.pts.size()][1]
			p.line(x0, y0 + Y, x1, y1 + Y, C[7] if f.lit > 0.6 else (C[6] if f.lit > 0.3 else C[4]))
	# glints: a star flashes on a face as it turns into the light
	for f: Dictionary in faces:
		if f.spec > 0.96:
			Px.sparkle(p, f.cx, f.cy + Y, Px.round(2.0 + (f.spec - 0.96) * 150.0), C[6], C[4], 0.5)
	# a glint at the tip now and then
	var g := fmod(ph * 2.0, 1.0)
	if g < 0.12:
		Px.sparkle(p, 0.0, Y - R * 2.2 * cos(TIP), Px.round(5.0 * sin((g / 0.12) * PI)), C[6], C[4], 0.6)
	motes(p, C, t, o, Y, true)
