# The hit recipe (a tracer from the right, a flash and a ripple over a hex shell mapped by longitude and
# latitude, sparks glancing off) is adapted from Sprite Fusion's open-source shield
# (https://www.spritefusion.com/pixel-art-vfx/shield), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/scifi/force-field.js@2297fe09c7ab0673a0b21af19301730e2eb85acd
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Force field",
	"desc": "A glassy dome of hex plates over the hero: plates glint, tracers from the right slam into it, a ripple and cracks of light race across, sparks glance off.",
	"tags": ["scifi", "shield", "barrier", "dome", "hex", "hit", "defense", "loop"],
	"size": [184, 104],
	"origin": [76, 84],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#0b1030", "#152a63", "#1d4f9e", "#2582d2", "#36b9ee", "#8ae8ff", "#d4fbff", "#ffffff"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"radius": 44,
		"seed": 5,
	},
}

static var HOLD := {"turn": 1, "crouch": 3, "lean": 1, "fx": -9, "fy": -38, "bx": 10, "by": -38, "ffx": -5, "fbx": 6}
static var HIT_ := Px.merge(HOLD, {"x": -2, "crouch": 5, "lean": -3})
static var act := {
	"poses": [
		[0, HOLD],
		[0.42, HOLD],
		[0.42, HIT_, "snap"],
		[0.7, Px.merge(HOLD, {"x": -1})],
		[1.1, HOLD],
		[1.5, HOLD],
		[1.5, Px.merge(HIT_, {"crouch": 4, "lean": -2}), "snap"],
		[1.75, HOLD],
		[2.4, HOLD],
	],
	"hits": [{"t": 0.42, "stop": 0.07, "shake": 0.16, "amp": 2}, {"t": 1.5, "stop": 0.03, "shake": 0.08, "amp": 1}],
}

static var S3 := sqrt(3.0)
const SA := 0.13
static var CA := sqrt(1.0 - SA * SA)  # we look down on the dome a little
const G := 6.3
const KY := 1.12  # hex plates per radian of longitude, and their stretch in latitude
# the shots, once a loop: a heavy one that cracks the shell, a lighter one lower down that it shrugs off
static var SHOTS := _shots()


static func _shots() -> Array:
	var out := []
	for s: Dictionary in [{"t": 0.42, "lon": 0.66, "lat": 0.62, "big": true}, {"t": 1.5, "lon": 0.95, "lat": 0.26, "big": false}]:
		var lon: float = s.lon
		var lat: float = s.lat
		out.append(Px.merge(s, {"N": [cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon)]}))
	return out


# the pointy-top hex (corner radius 1) under grid point (gx, gy): its axial coords and center, how near its
# edge (1 on it) and how near one of its corners (0 on it)
static func cell(gx: float, gy: float) -> Dictionary:
	var fq := (S3 / 3.0) * gx - gy / 3.0
	var fr := (2.0 / 3.0) * gy
	var fs := -fq - fr
	var q := Px.round(fq)
	var r := Px.round(fr)
	var s := Px.round(fs)
	var dq := absf(q - fq)
	var dr := absf(r - fr)
	var ds := absf(s - fs)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	var hx := S3 * (q + r / 2.0)
	var hy := 1.5 * r
	var dx := gx - hx
	var dy := gy - hy
	var ax := absf(dx)
	var e := maxf(maxf(ax, absf(ax / 2.0 + (dy * S3) / 2.0)), absf(ax / 2.0 - (dy * S3) / 2.0)) / (S3 / 2.0)
	var k := Px.round((atan2(dy, dx) - PI / 6.0) / (PI / 3.0))
	var ca := PI / 6.0 + (k * PI) / 3.0
	return {"q": q, "r": r, "hx": hx, "hy": hy, "e": e, "corner": Px.hypot(dx - cos(ca), dy - sin(ca))}


# a point on the dome (longitude, latitude) to the screen: [x, y, facing (> 0 on the near side)]
static func project(R: float, lon: float, lat: float) -> Array:
	var X := cos(lat) * sin(lon)
	var Y := sin(lat)
	var Z := cos(lat) * cos(lon)
	return [R * X, -R * (Y * CA - Z * SA), Y * SA + Z * CA]


# every pixel of the near and far shell, worked out once: where it sits on the sphere and on the plates, and
# whether it's a seam (the last pixel of a plate before the next) or a plate's lit top-left edge
static var shells := {}


static func shell(R: float) -> Dictionary:
	if shells.has(R):
		return shells[R]
	var near := []
	var far := []
	var N := ceili(R) + 1
	var W := 2 * N + 1
	var ids := [{}, {}]
	for y in range(-N, ceili(R * SA) + 2):
		for x in range(-N, N + 1):
			var u := (x + 0.5) / R
			var vy := -(y + 0.5) / R
			var q := u * u + vy * vy
			if q > 1.0:
				continue
			var vz := sqrt(1.0 - q)
			for s: float in [1.0, -1.0]:
				var Y := vy * CA + s * vz * SA
				var Z := -vy * SA + s * vz * CA
				if Y < 0.0:
					continue
				var lon := atan2(u, Z)
				var lat := asin(minf(1.0, Y))
				var c := cell(lon * G, lat * G * KY)
				var id: float = c.q * 1000.0 + c.r
				(near if s > 0.0 else far).append({"x": x, "y": y, "X": u, "Y": Y, "Z": Z, "lon": lon, "lat": lat, "q": c.q, "r": c.r, "id": id, "e": c.e, "corner": c.corner, "rim": 1.0 - vz, "sil": (1.0 - sqrt(q)) * R})
				ids[0 if s > 0.0 else 1][(y + N) * W + x + N] = id
	var lists := [near, far]
	for i in 2:
		var m: Dictionary = ids[i]
		for q: Dictionary in lists[i]:
			var qx: int = q.x
			var qy: int = q.y
			var r: Variant = m.get((qy + N) * W + qx + 1 + N)
			var d: Variant = m.get((qy + 1 + N) * W + qx + N)
			var l: Variant = m.get((qy + N) * W + qx - 1 + N)
			var u: Variant = m.get((qy - 1 + N) * W + qx + N)
			q.seam = (r != null and r != q.id) or (d != null and d != q.id)
			q.bevel = not q.seam and ((l != null and l != q.id) or (u != null and u != q.id))
	var g := {"near": near, "far": far}
	shells[R] = g
	return g


static func _toScreen(R: float, path: Array, u0: float, u1: float) -> Array:
	var pts := []
	for i in path.size():
		var lon: float = path[i][0]
		var lat: float = path[i][1]
		if lat < 0.03 or lat > 1.52 or absf(lon) > 1.5:
			break
		var pr := project(R, lon, lat)
		pts.append([pr[0], pr[1], pr[2], u0 + ((u1 - u0) * i) / (path.size() - 1)])
	return pts


# fractures: jagged forked paths from the hit across the plates, laid out by longitude and latitude so they
# bend with the dome; each point carries how far along it is, so they can race out from the hit
static var crackCache := {}


static func cracks(R: float, seed: float, s: Dictionary) -> Array:
	var key := "%s:%s" % [R, seed]
	if crackCache.has(key):
		return crackCache[key]
	var rn := Px.Rng.new(seed * 13.0 + 5.0)
	var out := []
	var slon: float = s.lon
	var slat: float = s.lat
	for i in 5:
		var a := (i / 5.0) * TAU + rn.range(-0.35, 0.35)
		var L := rn.range(0.42, 0.8)
		var path := Px.bolt(rn, slon, slat, slon + (cos(a) * L) / cos(slat), slat + sin(a) * L, {"jag": 0.2, "depth": 4})
		out.append(_toScreen(R, path, 0.0, 1.0))
		for f: Array in Px.forks(rn, path, {"count": rn.int_(0, 2), "len": L * 0.5, "jag": 0.25, "spread": 0.9}):
			var j := -1
			for pi_ in path.size():
				if path[pi_][0] == f[0][0] and path[pi_][1] == f[0][1]:
					j = pi_
					break
			var u0 := maxi(0, j) / float(path.size() - 1)
			out.append(_toScreen(R, f, u0, u0 + 0.5))
	crackCache[key] = out
	return out


# what the shots throw off and the glints on the plates, born once a loop
static var ghostCache := {}


static func ghosts(o: Dictionary, C: Array, R: float) -> Lib.Ghosts:
	var key := "%s:%s:%s:%s" % [R, o.seed, o.sparks, o.palette]
	if ghostCache.has(key):
		return ghostCache[key]
	var W: float = meta.size[0] - meta.origin[0]
	var rn := Px.Rng.new(o.seed)
	var D: float = meta.duration
	var g := Lib.Ghosts.new(D, {"ground": func(): return 0.0, "sparks": o.sparks, "box": [-70.0, -80.0, W - 6.0, 14.0]})
	for s: Dictionary in SHOTS:
		var hxy := project(R, s.lon, s.lat)
		var hx: float = hxy[0]
		var hy: float = hxy[1]
		var n := 1.0 if s.big else 0.55
		var st: float = s.t
		# glancing off the curve: up and away to the right, the way the shot was going when it was turned
		var i := 0
		while i < 24.0 * n:
			var a := (-0.9 if s.big else -0.55) + rn.range(-0.7, 0.65)
			var sp := rn.range(100.0, 280.0) * (0.7 + 0.3 * n)
			g.add(st + rn.range(0.0, 0.02), P.SPARK, hx, hy, cos(a) * sp, sin(a) * sp - 30.0, rn.range(0.25, 0.75))
			i += 1
		i = 0
		while i < 7.0 * n:
			var a := -0.9 + rn.range(-1.2, 1.2)
			var sp := rn.range(30.0, 90.0)
			g.add(st + rn.range(0.0, 0.05), P.MOTE, hx, hy, cos(a) * sp, sin(a) * sp - 15.0, rn.range(0.3, 0.6), rn.pick([C[5], C[6], C[4]]), 0.7)
			i += 1
		i = 0
		while i < 3.0 * n:
			g.add(st + 0.04 + i * 0.07, P.STAR, hx + rn.range(-6.0, 6.0), hy + rn.range(-5.0, 5.0), 0.0, -4.0, rn.range(0.3, 0.5), C[6], rn.range(1.0, 2.0))
			i += 1
		i = 0
		while i < 3.0 * n:
			g.add(st + 0.03 + i * 0.04, P.SMOKE, hx + 2.0 + rn.range(-2.0, 2.0), hy - 1.0, rn.range(8.0, 22.0), rn.range(-14.0, -4.0), rn.range(0.9, 1.3), Px.hex("#5b5f78"), rn.range(2.2, 3.4))
			i += 1
	# a star on each plate as it glints
	for r in 12:
		for q in range(-14, 15):
			if not glints(o.seed, q, r):
				continue
			var lon := (S3 * (q + r / 2.0)) / G
			var lat := (1.5 * r) / (G * KY)
			var xyf := project(R, lon, lat)
			var f: float = xyf[2]
			if f < 0.25 or lat < 0.15 or lat > 1.45 or absf(lon) > 1.3:
				continue
			g.add(glintAt(o.seed, q, r) + 0.03, P.STAR, xyf[0], xyf[1], 0.0, -3.0, 0.4, C[6], 1.4 + Px.rand(q, r, 9))
	ghostCache[key] = g
	return g


static func glints(S: Variant, q: Variant, r: Variant) -> bool:
	return Px.rand(S, q, r, 3) < 0.2


# when a plate glints: only in the quiet part of the loop, so nothing competes with the big hit
static func glintAt(S: Variant, q: Variant, r: Variant) -> float:
	var g := Px.rand(S, q, r) * 1.7
	return 1.0 + g if g < 1.4 else g - 1.4


static func drawShell(p: Px.Painter, t: float, o: Dictionary, C: Array, near: bool) -> void:
	var R: float = o.radius
	var D: float = meta.duration
	var S: float = o.seed
	var ph := t / D
	var sh := shell(R)
	var ages := []
	for s: Dictionary in SHOTS:
		ages.append(Lib.since(t, s.t, D))
	# the scan: a band of light climbing the dome once a loop
	var sk := Px.clamp((ph - 0.72) / 0.26)
	var scanLat := -0.2 + sk * 2.0
	var scanK := sin(PI * sk)
	for q: Dictionary in (sh.near if near else sh.far):
		var ff: float = q.rim * q.rim
		# the ripples: a front racing out over the sphere from each hit, the plates behind it still humming
		var rp := 0.0
		var hot := 0.0
		for i in SHOTS.size():
			var s: Dictionary = SHOTS[i]
			var age: float = ages[i]
			if age >= 1.0:
				continue
			var sN: Array = s.N
			var d := acos(Px.clamp(q.X * sN[0] + q.Y * sN[1] + q.Z * sN[2], -1.0, 1.0))
			var f := 0.06 + 3.1 * age
			var k := (1.0 - age) * (1.0 if s.big else 0.7)
			rp = maxf(maxf(rp, exp(-(pow((d - f) / 0.15, 2.0))) * k), 0.22 * k * k * (1.0 - d / f) if d < f else 0.0)
			var hr := 0.3 if s.big else 0.17
			if age < 0.55 and d < hr:
				hot = maxf(hot, 2.0 if (age < 0.07 and d < hr * 0.75) else pow(1.0 - age / 0.55, 1.5) * (1.1 - (0.6 * d) / hr))
		# plates glint now and then
		var gl := 0.0
		if glints(S, q.q, q.r):
			var a := Lib.since(t, glintAt(S, q.q, q.r), D)
			if a < 0.45:
				gl = 1.0 - a / 0.45
		var sc := scanK * exp(-(pow((q.lat - scanLat) / 0.09, 2.0)))
		if not near:
			# the far side, seen through the glass: dim seams, a breath of tint
			if q.seam:
				p.blend(q.x + 0.5, q.y + 0.5, C[5] if rp > 0.3 else C[3], Px.clamp(0.18 + 0.25 * ff + 0.6 * rp + 0.3 * sc))
			else:
				p.blend(q.x + 0.5, q.y + 0.5, C[2], 0.04 + 0.06 * ff + 0.15 * rp)
			continue
		if q.sil < 1.15:
			# the rim: a hard bright edge, whiter where the light catches it
			var lit: float = -q.X * 0.55 + q.Y * 0.85
			p.px(q.x, q.y, WHITE if (rp > 0.4 or lit > 0.8) else (C[6] if lit > 0.3 else C[5]))
			p.light(q.x, q.y, C[4], 0.3)
			continue
		if hot >= 2.0:
			# the hero frame: the struck plates go white
			p.px(q.x, q.y, C[6] if q.seam else WHITE)
			continue
		if q.seam:
			var I: float = 0.12 + 0.5 * ff + 0.08 * sin(q.lon * 2.3 + q.lat * 3.0 - ph * TAU) + (0.18 if q.corner < 0.32 else 0.0) + 0.9 * gl + 0.7 * sc + 1.3 * rp + hot
			var c: int = WHITE if (gl > 0.6 or rp > 0.55 or hot > 0.5) else (C[6] if I > 0.8 else (C[5] if I > 0.55 else C[4]))
			if I > 0.36:
				p.px(q.x, q.y, c)
			else:
				p.blend(q.x + 0.5, q.y + 0.5, c, 0.3 + I)
			p.light(q.x, q.y, C[4], 0.04 + 0.08 * I)
		else:
			# the glass: thin face-on, thicker toward the rim, a lit top-left edge on every plate
			var a: float = 0.05 + 0.34 * ff * q.rim + 0.1 * pow(q.e, 4.0) + (0.12 + 0.2 * ff if q.bevel else 0.0) + 0.35 * gl + 0.1 * sc + 0.3 * rp + 0.6 * hot
			var c: int = WHITE if hot > 0.6 else (C[6] if (hot > 0.3 or gl > 0.5) else (C[5] if (rp > 0.4 or q.bevel) else (C[4] if ff > 0.5 else C[3])))
			p.blend(q.x + 0.5, q.y + 0.5, c, Px.clamp(a))
			if rp > 0.1 or hot > 0.0 or gl > 0.0:
				p.light(q.x, q.y, C[4], 0.06 * (rp + hot + gl))


# the dome's foot: a ring on the floor with emitters round it, chasing
static func drawFoot(p: Px.Painter, t: float, C: Array, R: float, near: bool) -> void:
	var D: float = meta.duration
	var keep := func(g: float) -> bool: return (sin(g) >= 0.0) == near
	Px.band(p, 0.0, 0.0, R + 1.0, SA, 2.0, 1.0, [C[1], C[3], C[5], C[6]], keep)
	for i in 10:
		var g := (i / 10.0) * TAU + 0.31
		if not keep.call(g):
			continue
		var x := cos(g) * (R - 0.5)
		var y := sin(g) * R * SA
		var k := 0.5 + 0.5 * cos(TAU * (2.0 * (t / D) - i / 10.0))
		p.px(x - 1.0, y, C[2])
		p.px(x + 1.0, y, C[2])
		p.px(x, y, WHITE if k > 0.6 else C[5])
		p.glow(x, y, 6.0 + 4.0 * k, C[4], (0.25 if near else 0.15) * (0.4 + k))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var R: float = o.radius
	var x := -R
	while x <= R:
		p.glow(x, -1.0, 22.0, C[3], 0.1)
		x += R / 3.0
	drawFoot(p, t, C, R, false)
	drawShell(p, t, o, C, false)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var SP := Px.fit(o.sparks, 4)
	var R: float = o.radius
	var D: float = meta.duration
	var W: float = meta.size[0] - meta.origin[0]
	drawShell(p, t, o, C, true)
	drawFoot(p, t, C, R, true)
	for s: Dictionary in SHOTS:
		var age := Lib.since(t, s.t, D)
		var hxy := project(R, s.lon, s.lat)
		var hx: float = hxy[0]
		var hy: float = hxy[1]
		var n := 1.0 if s.big else 0.6
		# the fractures: race out from the hit white-hot, then cool down the ramp and fade
		if s.big and age < 0.9:
			var fade := 1.0 - Px.smooth(0.35, 0.9, age)
			var reach := Px.clamp(age / 0.09)
			for pass_ in [0, 1]:
				for c: Array in cracks(R, o.seed, s):
					for i in range(1, c.size()):
						var x0: float = c[i - 1][0]
						var y0: float = c[i - 1][1]
						var f0: float = c[i - 1][2]
						var x1: float = c[i][0]
						var y1: float = c[i][1]
						var f1: float = c[i][2]
						var u: float = c[i][3]
						if u > reach or f0 < 0.05 or f1 < 0.05:
							continue
						var k := fade * (1.2 - u * 0.4)
						if pass_ == 0:
							if age < 0.32:
								for oo: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
									p.line(x0 + oo[0], y0 + oo[1], x1 + oo[0], y1 + oo[1], C[6] if age < 0.12 else C[5], k * (1.0 - age / 0.32))
							continue
						p.line(x0, y0, x1, y1, WHITE if age < 0.12 + u * 0.08 else (C[6] if age < 0.3 + u * 0.1 else C[5]), k)
						if i % 3 == 0:
							p.glow(x1, y1, 6.0, C[4], 0.35 * fade * (1.0 - u * 0.5))
		# the tracer, in from the right: a streak that comes out of the edge, its tail never past where it entered
		var tk: float = (t - (s.t - 0.1)) / 0.1
		if tk >= 0.0 and tk < 1.0:
			var sx := W - 3.0
			var sy := hy - 12.0
			var L := Px.hypot(sx - hx, sy - hy)
			var at := func(d: float) -> Array: return [sx + ((hx - sx) * maxf(0.0, d)) / L, sy + ((hy - sy) * maxf(0.0, d)) / L]
			var h := L * tk
			var p0: Array = at.call(h)
			var p2: Array = at.call(h - 2.0)
			var p7: Array = at.call(h - 7.0)
			var p16: Array = at.call(h - 16.0)
			p.line(p16[0], p16[1], p7[0], p7[1], SP[3])
			p.line(p7[0], p7[1], p2[0], p2[1], SP[1])
			p.line(p2[0], p2[1], p0[0], p0[1], SP[0])
			p.px(p0[0], p0[1], WHITE)
			p.glow(p0[0], p0[1], 9.0, SP[1], 0.55)
		# the impact: a white star, light that flares and dies
		if age < 0.14:
			Px.sparkle(p, hx, hy, (7.0 * (1.0 - age / 0.14) + 1.0) * n, C[6], C[5], 0.4)
		Lib.flash(p, t, s.t, hx, hy, 56.0 * n, C[4], 0.45, 0.45)
		Lib.flash(p, t, s.t, hx, hy, 12.0, WHITE, 0.5 * n, 0.08)
		Lib.flash(p, t, s.t, hx + 3.0, hy, 22.0, SP[1], 0.4 * n, 0.15)
	# the dome's own light, and what glances off
	var a0 := Lib.since(t, SHOTS[0].t, D)
	p.glow(0.0, -R * 0.45, R * 1.3, C[3], 0.11 + 0.1 * maxf(0.0, 1.0 - a0 * 2.0))
	ghosts(o, C, R).at(t).draw(p)
