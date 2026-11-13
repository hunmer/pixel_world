# port-of: src/fx/scifi/hologram.js@e7d1ccd898099f842c303e7a8caa7b9a6aa8d211
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Hologram",
	"desc": "A floor projector throws a cone of light holding a turning wireframe model: scanlines roll through it, a data ring circles it, and it flickers, tears and jitters.",
	"tags": ["scifi", "hologram", "projector", "wireframe", "display", "glitch", "ground", "loop"],
	"size": [112, 104],
	"origin": [56, 92],
	"duration": 4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#050c1e", "#0a1f48", "#123b80", "#1d64b8", "#2e98e8", "#6cd0ff", "#c8f0ff", "#ffffff"],
		"metal": ["#0e0d14", "#1e1c27", "#312e3e", "#4b4759", "#6f6a82", "#9d98b0"],
		"split": "#ff4fd8",
		"seed": 21,
	},
}

static var D: float = meta.duration
const OY := -50.0
const RAD := 16.0
const LENS := -6.0
# the model: a tall six-sided crystal, a point at each end and a ring of six round its waist
static var VERTS := _verts()
static var FACES := _faces()
static var EDGES := _edges()
# when it glitches: [start, length, how hard]
const GLITCHES := [[0.92, 0.12, 1.0], [2.55, 0.2, 1.4], [3.42, 0.06, 0.7]]


static func _verts() -> Array:
	var v := [[0.0, 1.45, 0.0], [0.0, -1.45, 0.0]]
	for i in 6:
		v.append([cos((i / 6.0) * TAU) * 0.9, 0.12, sin((i / 6.0) * TAU) * 0.9])
	return v


static func _faces() -> Array:
	var out := []
	for i in 6:
		out.append([0, 2 + i, 2 + ((i + 1) % 6)])
		out.append([1, 2 + ((i + 1) % 6), 2 + i])
	return out


static func _edges() -> Array:
	var out := []
	for i in 6:
		out.append([0, 2 + i])
		out.append([1, 2 + i])
		out.append([2 + i, 2 + ((i + 1) % 6)])
	return out


static func tearAt(tears: Array, y: int) -> float:
	for tr: Array in tears:
		if y >= tr[0] and y < tr[0] + tr[1]:
			return tr[2]
	return 0.0


# every pixel of the hologram goes through here: interlaced, torn, split
static func put(p: Px.Painter, g: Dictionary, x: float, y: float, c: int, a: float = 1.0) -> void:
	var yy := floori(y)
	if g.flick and (yy & 1):
		return
	var dx := tearAt(g.tears, yy)
	if dx:
		p.dot(x + dx, y, g.SPLIT, a * 0.8)
		p.dot(x + dx + Px.sign(dx), y, c, a)
		return
	p.dot(x, y, c, a)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var H := Px.fit(o.metal, 6)
	var SPLIT := Px.hex(o.split)
	var S: float = o.seed
	var ph := t / D
	var frame := floori(t * 30.0)
	var gl := 0.0
	for gg: Array in GLITCHES:
		gl = maxf(gl, gg[2]) if (t >= gg[0] and t < gg[0] + gg[1]) else gl
	var flick := 1 if (gl > 0.0 and Px.rand(S, frame) < 0.5) else 0
	# where it sits: a slow bob, a jolt when it glitches
	var cx := (-2.0 if Px.rand(S, frame, 2) < 0.5 else 2.0) * gl if gl else 0.0
	var cy := OY + 1.5 * sin(TAU * ph * 2.0)
	# the tears this frame: bands of rows knocked sideways
	var tears := []
	if gl:
		for i in 2:
			tears.append([floori(cy - RAD + Px.rand(S, frame, i) * RAD * 2.0), 2 + floori(Px.rand(S, frame, i, 1) * 4.0), Px.round((Px.rand(S, frame, i, 2) - 0.5) * 10.0 * gl)])
	var g := {"flick": flick, "tears": tears, "SPLIT": SPLIT}

	# the projector: a steel drum on the floor with a lens on top and lights round it
	p.shade(-16.0, -8.0, 16.0, 2.0, func(x: float, y: float, out):
		var top := pow(x / 15.0, 2.0) + pow((y + 5.0) / 3.0, 2.0) <= 1.0
		var side := absf(x) <= 15.0 and y > -5.0 and y <= 0.0
		if not top and not side:
			return
		if top:
			out.c = H[0] if pow(x / 15.0, 2.0) + pow((y + 5.0) / 3.0, 2.0) > 0.8 else (H[5] if y < -6.0 else H[3])
		else:
			out.c = H[0] if (absf(x) > 14.0 or y == 0.0) else (H[4] if y == -4.0 else (H[3] if x < -6.0 else (H[1] if x > 6.0 else H[2]))))
	p.ellipse(0.0, LENS + 0.5, 5.5, 1.6, func(d: float): return WHITE if d < 0.4 else (C[6] if d < 0.8 else C[4]))
	for i in 4:
		var k := 0.5 + 0.5 * cos(TAU * (2.0 * ph - i / 4.0))
		p.px(-9.0 + i * 6, -2.0, C[6] if k > 0.7 else C[3])
	# the cone of light up to the model: thin, fading as it rises, scanlines climbing it
	var top := cy + RAD * 1.3
	var y := ceilf(top)
	while y < LENS:
		var v := (y - LENS) / (top - LENS)
		var w := Px.lerp(4.0, RAD + 4.0, v)
		var lineOn := fmod(fmod(y + t * 24.0, 5.0) + 5.0, 5.0) < 1.0
		var x := floorf(-w)
		while x <= ceilf(w):
			var q := absf(x + 0.5) / w
			if q > 1.0:
				x += 1.0
				continue
			if q > 1.0 - 1.0 / w:
				put(p, g, x, y, C[5] if v < 0.5 else C[4])
			else:
				p.blend(x + 0.5, y + 0.5, C[5] if lineOn else C[4], (0.05 + 0.12 * (1.0 - v)) * (1.0 - 0.6 * q * q) + (0.06 if lineOn else 0.0))
			x += 1.0
		y += 1.0
	p.glow(0.0, LENS, 12.0, C[5], 0.6)
	# the stage the model stands on: a thin ring where the cone ends
	for i in 56:
		var a := (i / 56.0) * TAU - ph * TAU
		var x := cos(a) * (RAD + 4.0)
		var yy := top + sin(a) * 3.0
		if i % 7 < 5:
			put(p, g, x, yy, C[6] if sin(a) > 0.0 else C[4], 1.0 if sin(a) > 0.0 else 0.7)
	p.glowLine(-RAD - 4.0, top, RAD + 4.0, top, 4.0, C[4], 0.2)
	# data bits rising through the cone
	Px.cycle(t, D, 18, S + 1.0, func(r: Px.Rng): return r.range(0.8, 1.4), func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var yy := Px.lerp(LENS - 2.0, top, k)
		var w := Px.lerp(4.0, RAD + 2.0, k)
		put(p, g, r.range(-0.8, 0.8) * w, yy, WHITE if r.chance(0.3) else C[5], minf(1.0, (1.0 - k) * 2.0)))

	# the model: turning once a loop, tilted toward us
	var spin := TAU * ph
	var tilt := 0.32
	var P3 := []
	for vv: Array in VERTS:
		var vx: float = vv[0]
		var vy: float = vv[1]
		var vz: float = vv[2]
		var x1 := vx * cos(spin) + vz * sin(spin)
		var z1 := -vx * sin(spin) + vz * cos(spin)
		var y2 := vy * cos(tilt) - z1 * sin(tilt)
		var z2 := vy * sin(tilt) + z1 * cos(tilt)
		P3.append([cx + x1 * RAD, cy - y2 * RAD, z2])
	# a scan bar climbing through it, twice a loop
	var scanY := Px.lerp(cy + RAD * 1.5, cy - RAD * 1.5, fmod(ph * 2.0, 1.0) / 0.8)
	# the faces that face us, filled with scanlines
	for f: Array in FACES:
		var a: Array = P3[f[0]]
		var b: Array = P3[f[1]]
		var c: Array = P3[f[2]]
		var nz: float = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
		if nz >= 0.0:
			continue
		var shade := Px.clamp(0.3 + 0.7 * ((a[2] + b[2] + c[2]) / 3.0 + 0.5))
		p.poly([a, b, c], func(_x: float, yp: float): return C[6] if absf(yp - scanY) < 2.0 else (C[4] if shade > 0.6 else C[3]), func(_x: float, yp: float):
			var yy := floori(yp)
			return 1.0 if ((yy % 3 == 0 and not (flick and yy & 1)) or absf(yp - scanY) < 1.5) else 0.0)
	# the edges: the far ones dim, the near ones bright, hot where the scan bar crosses them
	var edges := []
	for e: Array in EDGES:
		edges.append([P3[e[0]], P3[e[1]], (P3[e[0]][2] + P3[e[1]][2]) / 2.0])
	Px.sort(edges, func(a, b): return a[2] - b[2])
	for e: Array in edges:
		var a: Array = e[0]
		var b: Array = e[1]
		var z: float = e[2]
		var L := Px.hypot(b[0] - a[0], b[1] - a[1])
		var d := 0.0
		while d <= L:
			var x := Px.lerp(a[0], b[0], d / L)
			var yy := Px.lerp(a[1], b[1], d / L)
			var hot := absf(yy - scanY) < 1.5
			if z < -0.15:
				put(p, g, x, yy, C[5] if hot else C[3], 0.7)
			else:
				put(p, g, x, yy, WHITE if hot else (C[6] if z > 0.4 else C[5]))
			d += 0.5
	for v3: Array in P3:
		var x: float = v3[0]
		var yy: float = v3[1]
		var z: float = v3[2]
		if z < -0.15:
			continue
		put(p, g, x, yy, WHITE)
		p.glow(x, yy, 4.0, C[5], 0.3)
	# a dashed data ring round its waist, its far half behind
	for i in 64:
		var a := (i / 64.0) * TAU + ph * TAU * 2.0
		var x := cx + cos(a) * (RAD + 9.0)
		var yy := cy + 3.0 + sin(a) * 4.0
		if floori(i / 3.0) % 3 == 2:
			continue
		put(p, g, x, yy, ((WHITE if i % 9 == 0 else C[5]) if sin(a) > 0.0 else C[3]), 1.0 if sin(a) > 0.0 else 0.6)
	# light: the model glows, the scan bar glows, a flicker drops the light too
	var lk := 0.5 if flick else 1.0
	p.glow(cx, cy, RAD * 2.2, C[4], 0.36 * lk)
	p.glow(cx, cy - RAD * 0.6, RAD, C[5], 0.15 * lk)
	if absf(scanY - cy) < RAD * 1.4:
		p.glowLine(cx - RAD, scanY, cx + RAD, scanY, 5.0, C[5], 0.3 * lk)
	p.glow(0.0, -2.0, 22.0, C[4], 0.2)
