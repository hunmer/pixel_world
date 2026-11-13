# The plasma ball (a lit rim, filaments from a white-hot heart, motes riding round it, zaps that spark where
# they land) follows Sprite Fusion's open-source energy orb (https://www.spritefusion.com/pixel-art-vfx/energy),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/scifi/energy-core.js@e0b4c8f981aee6a9630c9810f717cb7a25684e67
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Energy core",
	"desc": "A plasma core beating in a steel cage: it swells and throws a shock ring on each beat, two tilted rings orbit it, and arcs jump to the bars and spark.",
	"tags": ["scifi", "reactor", "core", "power", "plasma", "machine", "prop", "ground", "loop"],
	"size": [112, 100],
	"origin": [56, 88],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#1a0516", "#3d0a33", "#701560", "#b0228f", "#f53cd1", "#ff86e6", "#ffd2f6", "#ffffff"],
		"metal": ["#0e0d14", "#1e1c27", "#312e3e", "#4b4759", "#6f6a82", "#9d98b0"],
		"seed": 35,
	},
}

static var D: float = meta.duration
const CY := -36.0
const R0 := 11.0
const RC := 24.0
const TOPY := -64.0
const BOTY := -9.0
const SLOT := 0.1
static var NS := Px.roundi(D / SLOT)
# two heartbeats a loop, each a strong thump and a softer echo
const BEATS := [[0.05, 1.0, true], [0.25, 0.5, false], [1.25, 1.0, true], [1.45, 0.5, false]]


static func env(a: float) -> float:
	return a / 0.03 if a < 0.03 else exp(-(a - 0.03) / 0.12)


static func pulseAt(t: float) -> float:
	var m := 0.0
	for bk: Array in BEATS:
		m = maxf(m, bk[1] * env(Lib.since(t, bk[0], D)))
	return m


# the cage's bars round the core: angle, x, depth (> 0 in front)
static var BARS := _bars()


static func _bars() -> Array:
	var out := []
	for i in 6:
		var a := (i / 6.0) * TAU + PI / 6.0
		out.append({"x": RC * sin(a), "z": cos(a)})
	return out


# a point on an orbiting ring, tilted and turning: [x, y, depth]
static func ringPt(r: float, tilt: float, spin: float, a: float) -> Array:
	var x := r * cos(a)
	var z0 := r * sin(a)
	var y := -z0 * sin(tilt)
	var z := z0 * cos(tilt)
	return [x * cos(spin) + z * sin(spin), CY - y, -x * sin(spin) + z * cos(spin)]


static var RINGS := [
	{"r": 17.0, "tilt": 1.15, "spin": func(t: float) -> float: return TAU * (t / D)},
	{"r": 19.0, "tilt": -0.9, "spin": func(t: float) -> float: return -TAU * 2.0 * (t / D) + 1.0},
]

static var cache := {}


static func setup(o: Dictionary) -> Dictionary:
	var key := "%s:%s" % [o.seed, o.palette]
	if cache.has(key):
		return cache[key]
	var C := Px.fit(o.palette, 8)
	var rn := Px.Rng.new(o.seed)
	var g := Lib.Ghosts.new(D, {"ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]], "haze": C[5], "box": [-54.0, -98.0, 54.0, 11.0]})
	# arcs: each slot of the loop may fire one or two, more just after a thump
	var arcs := []
	var front := BARS.filter(func(b): return b.z > -0.2)
	for s in NS:
		var ts := s * SLOT
		var hot := false
		for bk: Array in BEATS:
			if bk[2] and Lib.since(ts, bk[0], D) < 0.16:
				hot = true
				break
		for n in (2 if hot else 1):
			if not hot and not rn.chance(0.4):
				continue
			var bar: Dictionary = rn.pick(front)
			var bx: float = bar.x
			var ty := rn.range(TOPY + 8.0, BOTY - 6.0)
			var ang := atan2(ty - CY, bx)
			var sx := cos(ang) * R0
			var sy := CY + sin(ang) * R0
			var path := Px.bolt(rn, sx, sy, bx - Px.sign(bx) * 1.5, ty, {"jag": 0.3, "depth": 4})
			arcs.append({"s": s, "path": path, "fk": Px.forks(rn, path, {"count": rn.int_(0, 1), "len": 7.0, "jag": 0.35})})
			for i in 5:
				var a := atan2(ty - sy, bx - sx) + PI + rn.range(-1.2, 1.2)
				var sp := rn.range(60.0, 170.0)
				g.add(ts, P.SPARK, bx, ty, cos(a) * sp, sin(a) * sp - 40.0, rn.range(0.2, 0.5))
	# each thump throws motes off the core
	for bk: Array in BEATS:
		if not bk[2]:
			continue
		var b: float = bk[0]
		for i in 12:
			var a := rn.range(0.0, TAU)
			var sp := rn.range(40.0, 110.0)
			g.add(b + 0.02, P.MOTE, cos(a) * R0, CY + sin(a) * R0, cos(a) * sp, sin(a) * sp, rn.range(0.25, 0.5), rn.pick([WHITE, C[6], C[5]]), 0.7)
	var v := {"C": C, "arcs": arcs, "g": g}
	cache[key] = v
	return v


# the plinth on the floor: a steel drum with a lit top and a row of status lights
static func plinth(p: Px.Painter, C: Array, H: Array, t: float, pulse: float) -> void:
	p.shade(-30.0, -10.0, 30.0, 2.0, func(x: float, y: float, out):
		var top := (pow(x / 29.0, 2.0) + pow((y + 7.0) / 4.0, 2.0)) <= 1.0
		var side := absf(x) <= 29.0 and y > -7.0 and y <= 0.0
		if not top and not side:
			return
		if top:
			out.c = H[0] if (pow(x / 29.0, 2.0) + pow((y + 7.0) / 4.0, 2.0)) > 0.82 else (H[5] if y < -8.0 else (H[4] if x < 0.0 else H[3]))
		else:
			out.c = H[0] if (absf(x) > 28.0 or y == 0.0) else (H[4] if y == -6.0 else (H[3] if x < -14.0 else (H[1] if x > 14.0 else H[2]))))
	for i in 7:
		var x := -18.0 + i * 6
		var k := 0.5 + 0.5 * cos(TAU * (2.0 * (t / D) - i / 7.0))
		p.px(x, -3.0, WHITE if k > 0.75 else (C[5] if k > 0.4 else C[2]))
		if k > 0.6:
			p.glow(x, -3.0, 4.0, C[4], 0.3 * k)
	p.glow(0.0, -8.0, 26.0, C[4], 0.25 + 0.3 * pulse)


# a cage bar: steel, lit on the face toward the core
static func barDraw(p: Px.Painter, b: Dictionary, C: Array, H: Array, pulse: float, back: bool) -> void:
	var lit: int = C[3] if back else (C[6] if pulse > 0.5 else C[5])
	var inward := -Px.sign(b.x)
	var y := TOPY + 2.0
	while y < BOTY:
		for i in range(-1, 2):
			var face := i == inward
			p.px(b.x + i, y, ((lit if face else H[1]) if back else (lit if face else (H[3] if i == 0 else H[1]))))
		y += 1.0


# the cage's rings top and bottom: the far half or the near half of a steel hoop
static func hoop(p: Px.Painter, y: float, rx: float, H: Array, C: Array, near: bool, pulse: float) -> void:
	var n := ceili(rx * 8.0)
	for i in n:
		var g := (i / float(n)) * TAU
		var s := sin(g)
		if (s >= 0.0) != near:
			continue
		var x := cos(g) * rx
		var yy := y + s * 4.0
		p.px(x, yy, (H[4] if s > 0.6 else H[3]) if near else H[1])
		p.px(x, yy + 1.0, H[1] if near else H[0])
		if near and s < 0.3:
			p.px(x, yy - 1.0, C[5] if pulse > 0.5 else C[3])


# the core: dark plasma held in a hard rim, thin bright bands churning round a white-hot heart, filaments
# flickering out from it; a thump floods it with light
static func core(p: Px.Painter, t: float, C: Array, R: float, pulse: float, seed: float) -> void:
	var ph := t / D
	p.shade(-R - 2.0, CY - R - 2.0, R + 2.0, CY + R + 2.0, func(x: float, y: float, out):
		var dx := x
		var dy := y - CY
		var d := sqrt(dx * dx + dy * dy) / R
		if d > 1.1:
			return
		if d > 1.0:
			out.c = C[2]
			return
		if d > 0.9:
			out.c = C[6] if (dy < -R * 0.3 and dx < R * 0.3) else C[4]
			return
		var a := atan2(dy, dx)
		var n := 0.5 + 0.5 * Px.tileFbm((a / TAU) * 6.0 + ph * 6.0 + d * 1.5, d * 2.2 - ph * 4.0, 6.0, 4.0, seed, 2)
		var band := absf(n - 0.5) < 0.05 + 0.05 * pulse
		var heat := pow(1.0 - d, 2.0) + pulse * 0.45
		if band:
			out.c = WHITE if heat > 0.5 else (C[6] if heat > 0.2 else C[5])
		else:
			out.c = C[6] if heat > 0.7 else (C[5] if heat > 0.42 else (C[3] if heat > 0.2 else (C[2] if n > 0.5 else C[1]))))
	# filaments, redrawn every other frame
	var f := floori(t * 15.0)
	var r := Px.rng(seed, f, 5)
	for i in 3:
		var a := (i / 3.0) * TAU + f * 0.7 + r.range(-0.4, 0.4)
		var pts := Px.bolt(r, 0.0, CY, cos(a) * R * 0.88, CY + sin(a) * R * 0.88, {"jag": 0.32, "depth": 3})
		p.polyline(pts, func(u: float): return WHITE if u < 0.4 else C[6])
		var ex: float = pts[pts.size() - 1][0]
		var ey: float = pts[pts.size() - 1][1]
		p.px(ex, ey, WHITE)
		p.glow(ex, ey, 4.0, C[5], 0.4)
	p.circle(0.0, CY, 1.8 + pulse * 2.0, WHITE)
	p.circle(0.0, CY, 3.0 + pulse * 2.0, func(d: float): return C[6] if d > 0.6 else WHITE, 0.0001)
	# a glassy highlight top left
	p.px(-R * 0.45, CY - R * 0.55, WHITE)
	p.px(-R * 0.45 + 1.0, CY - R * 0.55, C[6])


static func ring(p: Px.Painter, t: float, rg: Dictionary, C: Array, front: bool, pulse: float) -> void:
	var spin: float = rg.spin.call(t)
	var bead := (t / D) * TAU * 3.0
	var rr: float = rg.r
	var n := ceili(rr * 9.0)
	for i in n:
		var a := (i / float(n)) * TAU
		var xyz := ringPt(rr, rg.tilt, spin, a)
		var z: float = xyz[2]
		if (z >= 0.0) != front:
			continue
		var u := fmod(fmod((a - bead) / TAU, 1.0) + 1.0, 1.0)
		var head := u > 0.9
		p.px(xyz[0], xyz[1], WHITE if head else (C[3] if not front else (C[6] if (z > 0.5 * rr or pulse > 0.6) else C[5])))
	if front:
		var xy := ringPt(rr, rg.tilt, spin, bead)
		p.glow(xy[0], xy[1], 6.0, C[5], 0.5)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var H := Px.fit(o.metal, 6)
	var pulse := pulseAt(t)
	hoop(p, BOTY, RC, H, C, false, pulse)
	hoop(p, TOPY, RC, H, C, false, pulse)
	for b: Dictionary in BARS:
		if b.z < 0.0:
			barDraw(p, b, C, H, pulse, true)
	for rg: Dictionary in RINGS:
		ring(p, t, rg, C, false, pulse)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var st := setup(o)
	var C: Array = st.C
	var arcs: Array = st.arcs
	var g: Lib.Ghosts = st.g
	var H := Px.fit(o.metal, 6)
	var pulse := pulseAt(t)
	var R := R0 * (1.0 + 0.14 * pulse)
	plinth(p, C, H, t, pulse)
	core(p, t, C, R, pulse, o.seed)
	for rg: Dictionary in RINGS:
		ring(p, t, rg, C, true, pulse)
	for b: Dictionary in BARS:
		if b.z >= 0.0:
			barDraw(p, b, C, H, pulse, false)
	hoop(p, BOTY, RC, H, C, true, pulse)
	hoop(p, TOPY, RC, H, C, true, pulse)
	# the cap: a steel dome with an emitter on top
	p.shade(-15.0, TOPY - 7.0, 15.0, TOPY, func(x: float, y: float, out):
		var d := pow(x / 14.5, 2.0) + pow((y - TOPY) / 6.5, 2.0)
		if d > 1.0:
			return
		var l := -x * 0.05 - (y - TOPY) * 0.12
		out.c = H[0] if d > 0.8 else (H[5] if l > 0.55 else (H[4] if l > 0.3 else H[3])))
	p.px(0.0, TOPY - 7.0, WHITE if pulse > 0.4 else C[5])
	p.glow(0.0, TOPY - 7.0, 5.0, C[4], 0.4 + 0.4 * pulse)
	# the arcs firing now
	var s := floori(t / SLOT) % NS
	var k := 1.0 - (t - floorf(t / SLOT) * SLOT) / SLOT
	for a: Dictionary in arcs:
		if a.s != s:
			continue
		Lib.strokeArc(p, a.path, [C[2], C[5], C[4]], k)
		for f: Array in a.fk:
			Lib.strokeArc(p, f, [C[2], C[5], C[4]], k, 0.6)
		var last: Array = a.path[a.path.size() - 1]
		p.glow(last[0], last[1], 8.0, C[5], 0.6 * k)
	# each thump: a shock ring rolls out from the core
	for bk: Array in BEATS:
		var a := Lib.since(t, bk[0], D)
		if not bk[2] or a > 0.45:
			continue
		var q := a / 0.45
		var r := R0 + 34.0 * Px.Ease.outCubic(q)
		p.ring(0.0, CY, r, maxf(1.0, 3.0 * (1.0 - q)), WHITE if q < 0.25 else (C[6] if q < 0.5 else C[5]), 1.1 - q)
		p.glowRing(0.0, CY, r, 6.0, C[4], 0.35 * (1.0 - q))
	g.at(t).draw(p)
	# light: the core's heat, its white heart, the steel lit round it
	p.glow(0.0, CY, 46.0, C[4], 0.2 + 0.3 * pulse)
	p.glow(0.0, CY, 9.0, WHITE, 0.35 + 0.4 * pulse)
