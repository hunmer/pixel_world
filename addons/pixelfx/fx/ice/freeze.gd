# The crack-and-burst recipe (cracks walking out from a point, a white frame, the ice flung apart as shards
# with ice dust and glints) is adapted from Sprite Fusion's open-source ice
# (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ice/freeze.js@471f08c7fcdb2f031927a0456498f543d2d64fbe
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Freeze",
	"desc": "Frost races in and climbs the character, turning it to ice; a faceted block crystallizes round it pane by pane, glints, cracks and bursts, and the character thaws free.",
	"tags": ["ice", "freeze", "frozen", "status", "crowd-control", "one-shot"],
	"size": [176, 128],
	"origin": [88, 108],
	"duration": 4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "seed": 5},
}

static var FEAR := {"turn": 0.9, "lean": -2, "crouch": 2, "fx": -8, "fy": -31, "bx": 9, "by": -31, "ffx": -3, "fbx": 4}
static var FREE := {"turn": 1, "crouch": 5, "fx": -12, "fy": -18, "bx": 12, "by": -18, "ffx": -5, "fbx": 6}
static var act := {
	"onBody": true,
	"poses": [
		[-0.2, Px.READY],
		[0.05, Px.READY],
		[0.16, FEAR, "snap"],
		[0.3, Px.merge(FEAR, {"lean": -1, "fx": -10, "fy": -34})],
		[0.45, Px.merge(FEAR, {"lean": -3, "bx": 11, "by": -34, "fx": -7, "fy": -29})],
		[0.62, FEAR],
		[2.52, FEAR],
		[2.54, FREE, "snap"],
		[2.9, Px.merge(FREE, {"crouch": 4})],
		[3.1, Px.merge(FREE, {"crouch": 3, "lean": 1})],
		[3.3, Px.merge(FREE, {"crouch": 3, "lean": -1})],
		[4, Px.READY],
	],
	"hits": [{"t": 0.62, "stop": 0.03, "shake": 0.08, "amp": 1}, {"t": 2.52, "stop": 0.05, "shake": 0.2, "amp": 2}],
}

const SNAP := 0.16  # frost lines race in along the floor to the feet
const CLIMB := [0.14, 0.62]  # and climb the character
const SEAL := 0.6  # the block crystallizes, pane by pane
const SWEEPS := [1.12, 1.82]  # light slides across the faces while it holds
const CRACK := 2.2
const CRACK2 := 2.34
const FLASH := 2.46
const BURST := 2.52
const THAW := 0.36
const MELT := [2.95, 3.7]  # the floor frost goes
const REACH := 38
const CORE := [0, -21]

# the block: a crown of three crystal points over straight sides, eleven corners round the character and
# eight inside, cut into thirteen panes. Each pane: its corners, how much light it catches (0 shadow .. 1 lit)
# and when it crystallizes after SEAL (from the floor up).
static var V := {
	"l0": [-15, 0], "l1": [-17, -10], "l2": [-17, -31], "p1": [-12, -45], "n1": [-6, -42], "p2": [0, -52], "n2": [6, -43], "p3": [12, -47], "r2": [17, -30], "r1": [16, -9], "r0": [14, 0],
	"i0": [-6, -36], "i1": [6, -35], "i2": [-9, -21], "i3": [3, -25], "i4": [9, -13], "i5": [-5, -8], "i6": [2, 0], "i7": [0, -40],
}
static var FACETS := _facets([
	["l0 l1 i5 i6", 0.62, 0], ["i5 i4 i6", 0.42, 0.03], ["i4 r2 r1 r0 i6", 0.2, 0.05], ["l1 l2 i2 i5", 0.74, 0.08], ["i2 i3 i4 i5", 0.5, 0.1],
	["i1 r2 i4 i3", 0.28, 0.13], ["l2 i0 i2", 0.7, 0.15], ["i0 i1 i3 i2", 0.58, 0.18], ["n1 i7 n2 i1 i0", 0.52, 0.2], ["i1 n2 p3 r2", 0.4, 0.23],
	["l2 p1 n1 i0", 0.88, 0.25], ["p2 n2 i7", 0.66, 0.28], ["n1 p2 i7", 1, 0.31],
])
static var OUTLINE := _verts("l0 l1 l2 p1 n1 p2 n2 p3 r2 r1 r0")
const X0 := -18
const X1 := 18
const Y0 := -53
const Y1 := 0
const BW := X1 - X0


static func _verts(k: String) -> Array:
	return Array(k.split(" ")).map(func(v: String) -> Array: return V[v])


static func _facets(list: Array) -> Array:
	var out := []
	for i in list.size():
		var e: Array = list[i]
		out.append({"pts": _verts(e[0]), "lit": float(e[1]), "at": SEAL + e[2], "i": i})
	return out


# frost on the floor: a crust on the floor line, rime ferns standing up from it, a cold bloom under the surface
static func floorFrost(p: Px.Painter, C: Array, t: float, out: float) -> void:
	for x in range(-REACH, REACH + 1):
		var d := absf(x + 0.5) / REACH
		var arrive := SNAP * (1.0 - d)
		var age := t - arrive
		if age < 0.0:
			continue
		var a := out * Px.clamp((1.12 - d) / 0.2)
		var g := Px.smooth(0.0, 0.4, age)
		var h := Px.rand(x, 31)
		var s := -1 if x < 0 else 1
		if a <= 0.0:
			continue
		p.dot(x, 0.0, WHITE if (age < 0.05 or h < 0.3) else C[6], a)
		if h < 0.55:
			var L := Px.round(g * (1.0 + Px.rand(x, 7) * 3.4) * (1.0 - d * 0.55))
			var j := 1.0
			while j <= L:
				p.dot(x, -j, WHITE if j == L else C[5], a)
				j += 1.0
			if L >= 2.0:
				p.dot(x + s, -L + 1.0, C[6], a)
			if L >= 4.0:
				p.dot(x - s, -L + 2.0, C[5], a)
		var D := g * (2.0 + Px.rand(x, 11) * 4.0) * (1.0 - d * 0.5)
		var j := 1.0
		while j <= D:
			p.dot(x, j, WHITE if Px.rand(x * 13 + j, 5) < 0.07 else (C[5] if j < 2.0 else (C[4] if j < 4.0 else C[3])), a * (1.05 - j / (D + 1.0)))
			j += 1.0


static func inBlock(x: float, y: float) -> bool:
	return Lib.inPoly(OUTLINE, x, y)


var C: Array
var R: Px.Rng
var A: Dictionary
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var panes: Lib.Panes
var W: int
var H: int
var N: int
var ice := PackedInt32Array()
var reach := PackedFloat32Array()
var order: Array = []
var feathers: Array = []
var fid := PackedInt32Array()
var EDGES: Array = []
var VERTS: Array = []
var cracks: Array
var cracks2: Array
var t := 0.0
var formed := 0
var sealed := false
var struck := 0
var burst := false
var white := false


func on(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and A.mask.data[y * W + x] > 0


func at(x: int, y: int) -> int:
	return -1 if (x < X0 or x >= X1 or y < Y0 or y >= Y1) else fid[(y - Y0) * BW + (x - X0)]


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	A = o.actor
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]], "haze": C[5]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	panes = Lib.Panes.new({
		"ground": floor_,
		"onLand": func(q: Dictionary, x: float, y: float, _v: float) -> void:
			# a pane that lands breaks into splinters that skip along the floor, with a puff of ice dust and a glint
			for i in 3:
				bits.add({"kind": B.SHARD, "x": x + R.range(-2.0, 2.0), "y": y - 1.0, "vx": q.vx * 0.6 + R.range(-50.0, 50.0), "vy": -R.range(30.0, 100.0), "g": 0.8, "drag": 0.6, "bounce": 0.35, "life": R.range(0.4, 0.8), "a": R.range(0.0, TAU), "va": R.range(-18.0, 18.0), "s": R.range(1.2, 2.4), "c": C[R.int_(5, 7)]})
			ps.spawn(P.VAPOUR, x, y - 1.0, R.range(-25.0, 25.0), -R.range(2.0, 10.0), R.range(0.4, 0.7), C[6], R.range(1.4, 2.4))
			if R.chance(0.4):
				ps.spawn(P.STAR, x, y - 2.0, 0.0, -6.0, R.range(0.2, 0.4), WHITE, R.range(0.8, 1.6)),
	})

	# ---- the character: each pixel's frozen color and when the frost reaches it. A randomized flood up from the
	# feet, quicker round the outline, so the front creeps up the edges first in ragged fingers.
	W = A.w
	H = A.h
	N = W * H
	var dist := PackedFloat32Array()
	dist.resize(N)
	dist.fill(INF)
	ice = PackedInt32Array()
	ice.resize(N)
	var rim := PackedByteArray()
	rim.resize(N)
	var open := []
	for y in H:
		for x in W:
			if not on(x, y):
				continue
			var i := y * W + x
			rim[i] = 1 if (not on(x - 1, y) or not on(x + 1, y) or not on(x, y - 1)) else 0
			var up := not on(x - 1, y) or not on(x, y - 1)
			ice[i] = Px.mix(C[mini(7, C.find(Lib.iceOf(A.pixels[i], C)) + 1)] if up else Lib.iceOf(A.pixels[i], C), C[6], 0.2)
			if y == H - 1 or not on(x, y + 1):
				if y >= H - 4:
					dist[i] = R.range(0.0, 1.5)
					open.append(i)
	var done := PackedByteArray()
	done.resize(N)
	while open.size():
		var bi := 0
		for j in range(1, open.size()):
			if dist[open[j]] < dist[open[bi]]:
				bi = j
		var i: int = open[bi]
		open[bi] = open[open.size() - 1]
		open.pop_back()
		if done[i]:
			continue
		done[i] = 1
		var x := i % W
		var y := floori(i / float(W))
		for e: Array in [[1, 0], [-1, 0], [0, -1], [0, 1]]:
			var nx: int = x + e[0]
			var ny: int = y + e[1]
			if not on(nx, ny):
				continue
			var j := ny * W + nx
			var w := (0.55 if rim[j] else 1.0) * (1.0 if e[1] < 0 else 1.3) + R.range(0.0, 1.5)
			if dist[i] + w < dist[j]:
				dist[j] = dist[i] + w
				open.append(j)
	var maxD := 0.0
	for i in N:
		if dist[i] < INF:
			maxD = maxf(maxD, dist[i])
	reach = PackedFloat32Array()
	reach.resize(N)
	order = []
	for i in N:
		if dist[i] < INF:
			reach[i] = CLIMB[0] + (CLIMB[1] - CLIMB[0]) * pow(dist[i] / maxD, 0.85)
			order.append(i)
	Px.sort(order, func(a: int, b: int) -> float: return reach[a] - reach[b])
	# rime feathers: little ticks of frost standing out from the outline once the frost has passed
	feathers = []
	for i: int in order:
		var x := i % W
		var y := floori(i / float(W))
		if not rim[i] or Px.rand(i, o.seed, 3) > 0.42 or y > H - 3:
			continue
		var dx := -1 if not on(x - 1, y) else (1 if not on(x + 1, y) else (-1 if Px.rand(i, 9) < 0.5 else 1))
		var dy := -1 if not on(x, y - 1) else (-1 if Px.rand(i, 4) < 0.5 else 0)
		feathers.append({"x": A.x + x + dx, "y": A.y + y + dy, "dx": dx, "dy": dy, "L": 1.0 + floorf(Px.rand(i, 7) * 2.6), "at": reach[i] + 0.04})

	# ---- the block: which pane every pixel belongs to, the panes' looks, the edges they share
	fid = PackedInt32Array()
	fid.resize(BW * (Y1 - Y0))
	fid.fill(-1)
	for y in range(Y0, Y1):
		for x in range(X0, X1):
			if not inBlock(x + 0.5, y + 0.5):
				continue
			var f := -1
			for k in FACETS.size():
				if Lib.inPoly(FACETS[k].pts, x + 0.5, y + 0.5):
					f = k
					break
			if f < 0:
				var b := 0
				for k in FACETS.size():
					var F: Dictionary = FACETS[k]
					if Px.hypot(Lib.centroid(F.pts).x - x, Lib.centroid(F.pts).y - y) < Px.hypot(Lib.centroid(FACETS[b].pts).x - x, Lib.centroid(FACETS[b].pts).y - y):
						b = k
				f = b
			fid[(y - Y0) * BW + (x - X0)] = f
	for F: Dictionary in FACETS:
		F.c = Lib.centroid(F.pts)
		F.tint = C[3 + Px.roundi(F.lit * 3.0)]
		F.alpha = 0.2 + 0.24 * F.lit
		F.d = Px.clamp((F.c.x + 0.55 * F.c.y + 36.0) / 46.0)
		var n: int = F.pts.size()
		var len := 0.0
		for k in n:
			var q: Array = F.pts[k]
			len += Px.hypot(F.pts[(k + 1) % n][0] - q[0], F.pts[(k + 1) % n][1] - q[1])
		F.len = len
	# every edge once: its ends, the panes it borders, whether it's on the outline and how it faces the light
	EDGES = []
	for F: Dictionary in FACETS:
		for k in F.pts.size():
			var a: Array = F.pts[k]
			var b: Array = F.pts[(k + 1) % F.pts.size()]
			var e: Variant = null
			for E: Dictionary in EDGES:
				if (is_same(E.a, a) and is_same(E.b, b)) or (is_same(E.a, b) and is_same(E.b, a)):
					e = E
					break
			if e == null:
				e = {"a": a, "b": b, "fs": []}
				EDGES.append(e)
			e.fs.append(F)
	for e: Dictionary in EDGES:
		var x0: float = e.a[0]
		var y0: float = e.a[1]
		var x1: float = e.b[0]
		var y1: float = e.b[1]
		var c: Dictionary = e.fs[0].c
		var nx := y1 - y0
		var ny := x0 - x1
		if nx * ((x0 + x1) / 2.0 - c.x) + ny * ((y0 + y1) / 2.0 - c.y) < 0.0:
			nx = -nx
			ny = -ny
		e.outer = e.fs.size() == 1
		e.lit = (-nx * 0.55 - ny * 0.84) / Px.hypot(nx, ny)
		e.floor = y0 == 0.0 and y1 == 0.0
		e.at = e.fs.map(func(F: Dictionary) -> float: return F.at).min()
	VERTS = V.values()
	cracks = Lib.fractures(R, func(x: float, y: float) -> bool: return inBlock(x, y), CORE[0], CORE[1], 3, {"len": 9.0, "a0": -2.2, "spread": 3.6})
	cracks2 = Lib.fractures(R, func(x: float, y: float) -> bool: return inBlock(x, y), CORE[0] + 1, CORE[1] - 2, 6, {"len": 16.0, "fork": 0.22})


func jolt() -> float:
	return 1.0 if (t >= CRACK and t < CRACK + 0.06) else ((1.0 if floori(t * 40.0) % 2 else -1.0) if (t >= CRACK2 and t < FLASH) else 0.0)


# the frozen character: each pixel turns as the frost reaches it, white at the front; after the burst the
# ice runs off it from the top down
func drawCharacter(p: Px.Painter) -> void:
	var thaw := Px.Ease.inQuad(Px.seg(t, BURST, BURST + THAW)) * (H + 2) - 2.0 if t >= BURST else -1.0
	for i: int in order:
		var age: float = t - reach[i]
		if age < 0.0:
			break
		var x := i % W
		var y := floori(i / float(W))
		if y < thaw:
			continue
		p.px(A.x + x, A.y + y, C[7] if (y < thaw + 1.2 and t >= BURST) else (WHITE if age < 0.016 else (C[6] if age < 0.045 else ice[i])))
		if age < 0.03:
			p.light(A.x + x, A.y + y, C[6], 0.3)
	if t >= BURST:
		return
	for f: Dictionary in feathers:
		var g := Px.clamp((t - f.at) / 0.08)
		if g <= 0.0:
			continue
		var L := Px.round(f.L * g)
		var j := 0
		while j < L:
			p.px(f.x + f.dx * j, f.y + f.dy * j, WHITE if j == L - 1.0 else C[6])
			j += 1


# the block: panes fill in as they crystallize (edges traced in white, a white flash, then glassy), a light
# sweep that breaks at every facet, cracks, the white frame before it bursts
func drawBlock(p: Px.Painter) -> void:
	if t >= BURST or t < SEAL - 0.08:
		return
	var jx := jolt()
	var wh := t >= FLASH
	# light slides across the block: each facet flashes whole as the light passes it, the lit ones brightest
	for F: Dictionary in FACETS:
		F.g = SWEEPS.reduce(func(g: float, s0: float) -> float: return maxf(g, sin(PI * Px.clamp((t - s0 - F.d * 0.32) / 0.13))), 0.0) * (0.35 + 0.65 * F.lit)
	for y in range(Y0, Y1):
		for x in range(X0, X1):
			var f := at(x, y)
			if f < 0:
				continue
			var F: Dictionary = FACETS[f]
			var age: float = t - F.at
			if age < 0.0:
				continue
			if wh:
				p.px(x + jx, y, WHITE)
				continue
			if age < 0.03:
				p.blend(x + jx, y, C[7], 0.55)
				continue
			var fresh := 1.0 - Px.clamp((age - 0.03) / 0.1)
			var g: float = F.g
			p.blend(x + jx, y, C[6] if (fresh > 0.5 or g > 0.5) else F.tint, F.alpha + 0.25 * fresh + 0.15 * g)
			if g > 0.05:
				p.light(x + jx, y, C[5], 0.42 * g)
	# edges: the outline lit where it faces up and left, cool on the shadow side with a deep rim outside it;
	# inner edges pale; any pane that has just set rings white
	for e: Dictionary in EDGES:
		if e.floor or t < e.at:
			continue
		var x0: float = e.a[0]
		var y0: float = e.a[1]
		var x1: float = e.b[0]
		var y1: float = e.b[1]
		var fresh: bool = e.fs.any(func(F: Dictionary) -> bool: return t - F.at < 0.1 or F.g > 0.6)
		if e.outer and e.lit < 0.0 and not wh:
			p.line(x0 + jx + 1.0, y0, x1 + jx + 1.0, y1, C[1])
		if e.outer:
			p.glowLine(x0 + jx, y0, x1 + jx, y1, 5.0, C[4], 0.1)
		p.line(x0 + jx, y0, x1 + jx, y1, C[6] if wh else (WHITE if fresh else ((WHITE if e.lit > 0.3 else (C[6] if e.lit > -0.2 else C[4])) if e.outer else (C[6] if (y0 + y1) / 2.0 < -30.0 else C[5]))))
	# a pane about to set: its edges traced in white from its first corner round, a bead of light at the head
	for F: Dictionary in FACETS:
		var age: float = t - F.at
		if age < -0.07 or age >= 0.0:
			continue
		var left: float = ((age + 0.07) / 0.07) * F.len
		var n: int = F.pts.size()
		var k := 0
		while k < n and left > 0.0:
			var x0: float = F.pts[k][0]
			var y0: float = F.pts[k][1]
			var x1: float = F.pts[(k + 1) % n][0]
			var y1: float = F.pts[(k + 1) % n][1]
			var L := Px.hypot(x1 - x0, y1 - y0)
			var v := minf(1.0, left / L)
			left -= L
			p.line(x0 + jx, y0, x0 + jx + (x1 - x0) * v, y0 + (y1 - y0) * v, WHITE)
			if v < 1.0:
				p.glow(x0 + jx + (x1 - x0) * v, y0 + (y1 - y0) * v, 6.0, C[6], 0.6)
			k += 1
	if t >= CRACK and not wh:
		Lib.drawFractures(p, cracks, (t - CRACK) * 150.0, C, {"ox": jx})
	if t >= CRACK2 and not wh:
		Lib.drawFractures(p, cracks2, (t - CRACK2) * 190.0, C, {"ox": jx})


func chop(pts: Array, depth: int) -> Array:
	var c := Lib.centroid(pts)
	if c.area < 20.0 or depth > 2:
		return [pts]
	var out := []
	for q: Array in Lib.splitPoly(pts, c.x, c.y, R.range(0.0, PI)):
		out.append_array(chop(q, depth + 1))
	return out


func update(dt: float) -> void:
	t += dt
	# frost lines race in along the floor from both sides, vapour riding them
	if t < SNAP:
		for s: int in [-1, 1]:
			var x := s * REACH * (1.0 - t / SNAP)
			if R.chance(0.12):
				ps.spawn(P.VAPOUR, x, -R.range(0.0, 2.0), -s * R.range(40.0, 90.0), -R.range(0.0, 5.0), R.range(0.3, 0.5), C[6], R.range(1.4, 2.4))
			if R.chance(0.45):
				ps.spawn(P.STREAK, x + s * R.range(0.0, 6.0), -R.range(1.0, 4.0), -s * R.range(50.0, 90.0), 0.0, R.range(0.1, 0.16), C[6] if R.chance(0.5) else C[5])
	# stars and motes kicked off the climbing front
	if t > CLIMB[0] and t < CLIMB[1] + 0.03:
		var lo := 0
		while lo < order.size() and reach[order[lo]] < t - 0.06:
			lo += 1
		var hi := lo
		while hi < order.size() and reach[order[hi]] <= t:
			hi += 1
		if hi > lo and R.chance(0.45):
			var i: int = order[R.int_(lo, hi - 1)]
			ps.spawn(P.STAR, A.x + (i % W) + 0.5, A.y + floori(i / float(W)), R.range(-8.0, 8.0), -R.range(0.0, 18.0), R.range(0.2, 0.42), C[6] if R.chance(0.5) else WHITE, R.range(0.6, 1.9))
		if hi > lo and R.chance(0.12):
			var i: int = order[R.int_(lo, hi - 1)]
			ps.spawn(P.FLAKE, A.x + (i % W), A.y + floori(i / float(W)), R.range(-20.0, 20.0), -R.range(10.0, 30.0), R.range(0.5, 0.9), C[6], R.range(0.5, 1.2))
	# each pane snaps into place with a chip of shards, a puff and a glint
	while formed < FACETS.size() and t >= FACETS[formed].at:
		var F: Dictionary = FACETS[formed]
		formed += 1
		var c := Lib.centroid(F.pts)
		for i in 3:
			var a: float = atan2(c.y - CORE[1], c.x - CORE[0]) + R.range(-0.7, 0.7)
			var sp := R.range(50.0, 120.0)
			bits.add({"kind": B.SHARD, "x": c.x, "y": c.y, "vx": cos(a) * sp, "vy": sin(a) * sp - 40.0, "g": 0.8, "drag": 0.8, "bounce": 0.3, "life": R.range(0.35, 0.7), "a": R.range(0.0, TAU), "va": R.range(-18.0, 18.0), "s": R.range(1.0, 2.2), "c": C[R.int_(5, 7)]})
		if c.y > -14.0:
			ps.spawn(P.VAPOUR, c.x, -1.0, Px.sign(c.x if c.x else 1.0) * R.range(10.0, 30.0), -R.range(2.0, 8.0), R.range(0.5, 0.8), C[6], R.range(2.2, 3.4))
		ps.spawn(P.STAR, c.x + R.range(-2.0, 2.0), c.y + R.range(-2.0, 2.0), 0.0, -4.0, R.range(0.25, 0.45), WHITE, R.range(1.2, 2.2))
		lights.add(c.x, c.y, 16.0, C[6], 0.4, 0.12)
	if not sealed and formed == FACETS.size():
		sealed = true
		lights.add(0.0, -26.0, 70.0, C[5], 0.6, 0.4)
		for i in 5:
			ps.spawn(P.STAR, R.range(-15.0, 15.0), -R.range(6.0, 44.0), R.range(-6.0, 6.0), -R.range(0.0, 8.0), R.range(0.3, 0.6), WHITE if R.chance(0.5) else C[6], R.range(1.0, 2.2))
	# while it holds: glints wink on the corners, cold vapour rolls off the foot, a little snow
	if sealed and t < CRACK2:
		if R.chance(0.035):
			var v: Array = R.pick(VERTS)
			ps.spawn(P.STAR, v[0] + R.range(-1.0, 1.0), v[1] + R.range(-1.0, 1.0), 0.0, -2.0, R.range(0.3, 0.6), C[6] if R.chance(0.6) else WHITE, R.range(0.8, 2.2))
		if R.chance(0.025):
			var s := R.sign()
			ps.spawn(P.VAPOUR, s * R.range(12.0, 18.0), -R.range(1.0, 3.0), s * R.range(8.0, 24.0), -R.range(1.0, 5.0), R.range(0.7, 1.1), C[6], R.range(1.8, 3.0))
		if R.chance(0.012):
			ps.spawn(P.FLAKE, R.range(-30.0, 30.0), -R.range(56.0, 76.0), R.range(-4.0, 4.0), R.range(4.0, 10.0), R.range(1.2, 1.8), WHITE if R.chance(0.5) else C[6], R.range(0.5, 1.4))
	# it cracks: a jolt, chips spall off, light leaks from the cracks
	if struck == 0 and t >= CRACK:
		struck = 1
		lights.add(CORE[0], CORE[1], 26.0, WHITE, 0.4, 0.1)
		for i in 4:
			bits.add({"kind": B.SHARD, "x": R.range(-14.0, 14.0), "y": -R.range(10.0, 40.0), "vx": R.range(-40.0, 40.0), "vy": -R.range(10.0, 60.0), "g": 0.9, "drag": 0.6, "bounce": 0.3, "life": R.range(0.5, 0.9), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.0, 2.0), "c": C[R.int_(5, 7)]})
	if struck == 1 and t >= CRACK2:
		struck = 2
		lights.add(CORE[0], CORE[1], 40.0, C[6], 0.35, 0.16)
		for i in 3:
			ps.spawn(P.STAR, R.range(-12.0, 12.0), -R.range(8.0, 40.0), 0.0, -3.0, R.range(0.15, 0.3), WHITE, R.range(1.0, 2.0))
	if not white and t >= FLASH:
		white = true
		lights.add(CORE[0], CORE[1], 60.0, WHITE, 0.9, 0.1)
	# it bursts: the panes fly off tumbling, shards and ice dust, glints, a flurry, a flash of light
	if not burst and t >= BURST:
		burst = true
		lights.add(CORE[0], CORE[1], 64.0, WHITE, 0.85, 0.14)
		lights.add(CORE[0], CORE[1] - 4, 72.0, C[4], 0.55, 0.6)
		for F: Dictionary in FACETS:
			for part: Array in chop(F.pts, 0):
				var m := Lib.centroid(part)
				var dx: float = m.x - CORE[0]
				var dy: float = m.y - CORE[1]
				var d := Px.hypot(dx, dy)
				if not d:
					d = 1.0
				var sp := R.range(40.0, 85.0) * (1.2 - minf(0.5, m.area / 120.0))
				panes.add({
					"pts": part.map(func(pt: Array) -> Array: return [pt[0] - m.x, pt[1] - m.y]), "x": m.x, "y": m.y, "vx": (dx / d) * sp + R.range(-15.0, 15.0), "vy": (dy / d) * sp * 0.6 - R.range(90.0, 190.0),
					"a": 0.0, "va": R.range(-9.0, 9.0), "f": R.range(-0.8, 0.8), "vf": R.sign() * R.range(5.0, 13.0), "lit": F.lit, "g": 0.85, "drag": 0.7, "brittle": true, "life": R.range(1.0, 1.45),
				})
		for i in 50:
			var x := 0
			var y := 0
			var k := 0
			while k < 12 and at(x, y) < 0:
				x = R.int_(X0, X1 - 1)
				y = R.int_(Y0, Y1 - 1)
				k += 1
			var dx: float = x - CORE[0]
			var dy: float = y - CORE[1]
			var d := Px.hypot(dx, dy)
			if not d:
				d = 1.0
			var sp := R.range(50.0, 130.0)
			bits.add({"kind": B.SHARD, "x": x, "y": y, "vx": (dx / d) * sp, "vy": (dy / d) * sp * 0.7 - R.range(60.0, 170.0), "g": 0.85, "drag": 0.9, "bounce": 0.3, "life": R.range(0.8, 1.4), "a": R.range(0.0, TAU), "va": R.range(-22.0, 22.0), "s": R.range(1.5, 3.2), "c": C[R.int_(4, 7)]})
		for f: Dictionary in feathers:
			if R.chance(0.5):
				bits.add({"kind": B.SHARD, "x": f.x, "y": f.y, "vx": f.dx * R.range(20.0, 70.0), "vy": -R.range(20.0, 90.0), "g": 0.8, "drag": 0.8, "bounce": 0.3, "life": R.range(0.4, 0.8), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.0, 1.8), "c": WHITE})
		for i in 12:
			var s := R.sign()
			ps.spawn(P.VAPOUR, s * R.range(2.0, 16.0), -R.range(1.0, 6.0), s * R.range(30.0, 90.0), -R.range(4.0, 16.0), R.range(0.6, 1.1), C[6], R.range(2.2, 4.0))
		for i in 8:
			ps.spawn(P.VAPOUR, R.range(-14.0, 14.0), -R.range(8.0, 40.0), R.range(-30.0, 30.0), -R.range(10.0, 30.0), R.range(0.6, 1.0), C[6], R.range(3.0, 5.0))
		for i in 18:
			var a := R.range(-PI, 0.0)
			var sp := R.range(40.0, 130.0)
			ps.spawn(P.FLAKE, R.range(-10.0, 10.0), CORE[1] + R.range(-12.0, 12.0), cos(a) * sp, sin(a) * sp, R.range(1.0, 1.5), WHITE if R.chance(0.6) else C[6], R.range(0.5, 1.6))
		for i in 7:
			ps.spawn(P.STAR, R.range(-26.0, 26.0), -R.range(6.0, 52.0), R.range(-12.0, 12.0), -R.range(4.0, 16.0), R.range(0.4, 0.8), WHITE if R.chance(0.5) else C[6], R.range(1.0, 2.4))
	# glints wink on the debris as it settles
	if burst and t < BURST + 0.9 and R.chance(0.07):
		var b: Dictionary = R.pick(bits.list if bits.list.size() else [{"x": 0.0, "y": -10.0}])
		ps.spawn(P.STAR, b.x, b.y - 1.0, 0.0, -3.0, R.range(0.2, 0.4), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.6))
	# the last of the ice runs off the character
	if burst and t < BURST + THAW and R.chance(0.12):
		var y := -H + Px.Ease.inQuad(Px.seg(t, BURST, BURST + THAW)) * H
		bits.add({"kind": B.DRIP, "x": R.range(-9.0, 9.0), "y": y, "vy": 10.0, "g": 0.5, "life": 0.8, "c": C[5]})
	ps.update(dt)
	bits.update(dt)
	panes.update(dt)
	lights.update(dt)
	Lib.endBy(t, meta.duration, ps, bits, panes)


func drawBack(p: Px.Painter) -> void:
	var out := 1.0 - Px.smooth(MELT[0], MELT[1], t)
	if out > 0.0:
		floorFrost(p, C, t, out)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	drawCharacter(p)
	drawBlock(p)
	# the cold light: a pool under the ice, a glow in it that brightens as it cracks, the climbing front's light
	var hold := Px.smooth(CLIMB[0], SEAL, t) * (1.0 - Px.smooth(BURST, BURST + 0.6, t))
	var crk := Px.smooth(CRACK, FLASH, t)
	if hold > 0.0:
		p.glow(0.0, -2.0, 34.0, C[4], 0.22 * hold * (0.85 + 0.15 * sin(t * 3.0)))
		p.glow(CORE[0], CORE[1] - 4, 40.0, C[3], (0.22 + 0.1 * crk) * hold)
	if t > CLIMB[0] and t < CLIMB[1]:
		p.glow(0.0, -38.0 * Px.Ease.outQuad(Px.seg(t, CLIMB[0], CLIMB[1])), 18.0, C[5], 0.28)
	# the seal: a star at the crown as the last pane sets
	var top: float = FACETS[FACETS.size() - 1].at
	var g := t - top
	if g > 0.0 and g < 0.3:
		Px.sparkle(p, V.p2[0], V.p2[1], 8.0 * Px.Ease.outBack(minf(1.0, g / 0.06)) * (1.0 - g / 0.3), C[6], C[4], 0.6)
	if t >= FLASH and t < BURST + 0.16:
		var a := Px.clamp((t - FLASH) / 0.22)
		Px.flare(p, CORE[0], CORE[1], 34.0 * pow(1.0 - a, 1.4), 1.0 - a, C)
	panes.draw(p, C)
	bits.draw(p)
	ps.draw(p, "front")
	lights.draw(p)
