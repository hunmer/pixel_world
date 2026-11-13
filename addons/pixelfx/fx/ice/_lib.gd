# Shared by the ice effects: panes of ice that tumble and skid, polygon helpers, a character turned to ice,
# cracks that race through a shape. Files starting with _ are helpers, not effects.
# The crack walk and the faceted crystal shading are adapted from Sprite Fusion's open-source ice
# (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ice/_lib.js@1a65e9d66a449ec346d2e8c2d36180e81d731f4b
extends RefCounted

const Px := preload("../../core/px.gd")
const Self := preload("_lib.gd")
const GRAVITY := Px.GRAVITY
const WHITE := Px.WHITE


## Is (x, y) inside the polygon pts [[x, y], ...]? (even-odd rule)
static func inPoly(pts: Array, x: float, y: float) -> bool:
	var inside := false
	var n := pts.size()
	var j := n - 1
	for i in n:
		var xi: float = pts[i][0]
		var yi: float = pts[i][1]
		var xj: float = pts[j][0]
		var yj: float = pts[j][1]
		if (yi > y) != (yj > y) and x < ((xj - xi) * (y - yi)) / (yj - yi) + xi:
			inside = not inside
		j = i
	return inside


## A polygon's centroid and area: { x, y, area }.
static func centroid(pts: Array) -> Dictionary:
	var a := 0.0
	var cx := 0.0
	var cy := 0.0
	var n := pts.size()
	var j := n - 1
	for i in n:
		var x0: float = pts[j][0]
		var y0: float = pts[j][1]
		var x1: float = pts[i][0]
		var y1: float = pts[i][1]
		var k := x0 * y1 - x1 * y0
		a += k
		cx += (x0 + x1) * k
		cy += (y0 + y1) * k
		j = i
	if absf(a) < 1e-6:
		return {"x": pts.reduce(func(s, q): return s + q[0], 0.0) / n, "y": pts.reduce(func(s, q): return s + q[1], 0.0) / n, "area": 0.0}
	return {"x": cx / (3.0 * a), "y": cy / (3.0 * a), "area": absf(a) / 2.0}


## Cut a polygon along the line through (x, y) at angle a: the pieces with three corners or more.
static func splitPoly(pts: Array, x: float, y: float, a: float) -> Array:
	var nx := -sin(a)
	var ny := cos(a)
	var side := func(q: Array) -> float: return (q[0] - x) * nx + (q[1] - y) * ny
	var L := []
	var Rt := []
	for i in pts.size():
		var p: Array = pts[i]
		var q: Array = pts[(i + 1) % pts.size()]
		var sp: float = side.call(p)
		var sq: float = side.call(q)
		(L if sp >= 0.0 else Rt).append(p)
		if (sp >= 0.0) != (sq >= 0.0):
			var u := sp / (sp - sq)
			var m := [p[0] + (q[0] - p[0]) * u, p[1] + (q[1] - p[1]) * u]
			L.append(m)
			Rt.append(m)
	return [L, Rt].filter(func(s): return s.size() >= 3)


## A color turned to ice: its brightness picks a step of the ice ramp C (dark to bright), never the darkest.
static func iceOf(c: int, C: Array) -> int:
	var n := C.size()
	var l := Px.luma(c)
	return C[int(Px.clamp(Px.round(((2.0 if l < 0.12 else 2.0 + l * 5.2) * (n - 1)) / 7.0), 1.0, n - 1))]


## Fill a polygon with translucent color (true blending, no dither): glass, ice, light.
static func glassPoly(p: Px.Painter, pts: Array, c: Variant, a: float) -> void:
	var x0 := INF
	var y0 := INF
	var x1 := -INF
	var y1 := -INF
	for q in pts:
		var x: float = q[0]
		var y: float = q[1]
		x0 = minf(x0, x)
		x1 = maxf(x1, x)
		y0 = minf(y0, y)
		y1 = maxf(y1, y)
	var y := floorf(y0)
	while y <= ceilf(y1):
		var x := floorf(x0)
		while x <= ceilf(x1):
			if inPoly(pts, x + 0.5, y + 0.5):
				p.blend(x, y, c, a)
			x += 1.0
		y += 1.0


## Panes of ice: flat polygons that fly, spin and tumble end over end (they squash as they turn edge-on and
## flash as they square up to the light), bounce on the floor, skid, settle and fade. Drawn as glass: a
## translucent face, edges lit where they face the light, a glint.
## add({ pts (corners around 0, 0), x, y, vx, vy, a (turn), va, f (tumble), vf, lit (0..1: how much light its
## face catches), g, drag, bounce, life, brittle (breaks on that many hard landings), crumble (seconds it lies
## still before it crumbles), solid (opaque: one `tone` 0..1, or shaded like a blade split along `ridge`, an angle) });
## update(dt); draw(p, C)
## with an ice ramp, dark to bright. onLand(q, x, y, speed) when one hits the floor hard, onCrumble(q) when one
## that lay still crumbles away, onSkid(q, x, y) while one slides along the floor.
class Panes extends RefCounted:
	var list: Array = []
	var ground: Variant = null
	var _gn := 0
	var onLand: Variant = null
	var onCrumble: Variant = null
	var onSkid: Variant = null
	var count: int:
		get: return list.size()

	func _init(opts: Dictionary = {}) -> void:
		list = []
		ground = opts.get("ground")
		_gn = ground.get_argument_count() if ground is Callable else 0
		onLand = opts.get("onLand")
		onCrumble = opts.get("onCrumble")
		onSkid = opts.get("onSkid")

	func _ground(x: float) -> float:
		if ground == null:
			return INF
		return ground.call(x) if _gn >= 1 else ground.call()

	static func _cb(fn: Variant, a: Variant, b: Variant = null, c: Variant = null, d: Variant = null) -> void:
		if fn is Callable:
			Px.call4(fn, fn.get_argument_count(), a, b, c, d)

	func add(q: Dictionary) -> void:
		var life: float = q.life if q.get("life") != null else 1.0
		var o := Px.merge({"vx": 0.0, "vy": 0.0, "a": 0.0, "va": 0.0, "f": 0.0, "vf": 0.0, "lit": 0.6, "g": 1.0, "drag": 0.3, "bounce": 0.35, "rest": false, "brittle": false}, q)
		o.life = life
		o.max = life
		list.append(o)

	## The pane's corners as drawn: tumbled (squashed across its own width), turned and placed.
	func corners(q: Dictionary) -> Array:
		var ca := cos(q.a)
		var sa := sin(q.a)
		var k := cos(q.f)
		return q.pts.map(func(pt: Array) -> Array:
			var x: float = pt[0]
			var y: float = pt[1]
			var yy := y * k
			return [q.x + x * ca - yy * sa, q.y + x * sa + yy * ca])

	func seat(q: Dictionary) -> float:
		var low := -INF
		for c in corners(q):
			low = maxf(low, c[1])
		return low

	func update(dt: float) -> void:
		var i := list.size() - 1
		while i >= 0:
			var idx := i
			i -= 1
			var q: Dictionary = list[idx]
			q.life -= dt
			if q.life <= 0.0:
				list.remove_at(idx)
				continue
			var floor_: float = _ground(q.x) - 0.5
			if q.rest and q.has("crumble"):
				q.restT = q.get("restT", 0.0) + dt
				if q.restT > q.crumble:
					_cb(onCrumble, q)
					list.remove_at(idx)
					continue
			if q.rest:
				# skidding: friction slows the slide and the spin, the pane stays seated on the floor
				if absf(q.vx) > 8.0:
					_cb(onSkid, q, q.x, floor_ + 0.5)
				q.x += q.vx * dt
				q.vx -= q.vx * 7.0 * dt
				q.a += q.va * dt
				q.va -= q.va * 9.0 * dt
				q.vf -= q.vf * 9.0 * dt
				q.f += q.vf * dt
				q.y -= seat(q) - floor_
				continue
			q.vy += GRAVITY * q.g * dt
			q.vx -= q.vx * q.drag * dt
			q.vy -= q.vy * q.drag * dt
			q.x += q.vx * dt
			q.y += q.vy * dt
			q.a += q.va * dt
			q.f += q.vf * dt
			var low := seat(q)
			if q.g <= 0.0 or low < floor_ or q.vy <= 0.0:
				continue
			q.y -= low - floor_
			if q.vy > 70.0:
				q.hits = q.get("hits", 0) + 1
				_cb(onLand, q, q.x, floor_ + 0.5, q.vy)
			if q.brittle and q.vy > 70.0 and float(q.hits) >= (1.0 if typeof(q.brittle) == TYPE_BOOL else float(q.brittle)):
				list.remove_at(idx)
				continue
			if q.vy > 70.0 and q.bounce > 0.0:
				q.vy = -q.vy * q.bounce
				q.vx *= 0.75
				q.va *= 0.6
				q.vf *= 0.5
			else:
				q.rest = true
				q.vy = 0.0

	func draw(p: Px.Painter, C: Array) -> void:
		var n := C.size()
		for q: Dictionary in list:
			var a := minf(1.0, q.life / 0.35)
			var pts := corners(q)
			var k := cos(q.f)
			var face := absf(k)
			# the face: glassy, brighter the more it faces us and the more light it catches; it flashes as it squares up
			var lv: float = q.lit * (0.35 + 0.65 * face)
			var flash: bool = face > 0.97 and not q.rest
			var solid: bool = true if q.get("solid") else false
			if face > 0.25:
				if solid and q.has("tone"):
					# a chunk of one face: its tone, brighter as it squares up to the light
					p.poly(pts, C[n - 1] if flash else C[int(Px.clamp(Px.round(1.0 + q.tone * 5.0 * (0.6 + 0.4 * face)), 1.0, n - 2))], a)
				elif solid:
					# shaded like the blade it broke from: a lit side, a pale ridge, a deep side
					var rr: float = q.ridge if q.get("ridge") != null else -PI / 2.0
					var cr := cos(rr)
					var sr := sin(rr)
					var ca := cos(q.a)
					var sa := sin(q.a)
					var rx := cr * ca - sr * k * sa
					var ry := cr * sa + sr * k * ca
					var nx := -ry
					var ny := rx
					if nx * -0.55 + ny * -0.84 < 0.0:
						nx = -nx
						ny = -ny
					var lit: int = C[n - 1] if flash else C[int(Px.clamp(Px.round(3.0 + lv * 3.0), 3.0, n - 2))]
					var deep: int = C[int(Px.clamp(Px.round(1.0 + lv * 2.0), 1.0, 3.0))]
					p.poly(pts, func(x: float, y: float) -> int:
						var d: float = (x - q.x) * nx + (y - q.y) * ny
						return lit if d > 0.6 else (C[n - 2] if d > -0.6 else deep), a)
				else:
					Self.glassPoly(p, pts, C[n - 1] if flash else C[int(Px.clamp(Px.round(3.0 + lv * 3.0), 3.0, n - 2))], (0.3 + 0.35 * lv + (0.3 if flash else 0.0)) * a)
			var cx := 0.0
			var cy := 0.0
			var top := 0
			for pt in pts:
				cx += pt[0]
				cy += pt[1]
			cx /= pts.size()
			cy /= pts.size()
			# edges: lit where they face the light (up and left), cool where they face away
			for i in pts.size():
				var x0: float = pts[i][0]
				var y0: float = pts[i][1]
				var x1: float = pts[(i + 1) % pts.size()][0]
				var y1: float = pts[(i + 1) % pts.size()][1]
				var nx := y1 - y0
				var ny := x0 - x1
				if nx * ((x0 + x1) / 2.0 - cx) + ny * ((y0 + y1) / 2.0 - cy) < 0.0:
					nx = -nx
					ny = -ny
				var l := Px.hypot(nx, ny)
				if not l:
					l = 1.0
				var lit := (-nx * 0.55 - ny * 0.84) / l
				p.line(x0, y0, x1, y1, C[n - 1] if (face < 0.25 or lit > 0.35) else (C[n - 2] if lit > -0.25 else (C[1] if solid else C[maxi(2, n - 4)])), a)
				if pts[i][1] < pts[top][1]:
					top = i
			if face > 0.7:
				p.dot(pts[top][0], pts[top][1], WHITE, a)
			p.glow(cx, cy, 5.0, C[n - 3], (0.5 if flash else 0.14) * a)


## A jagged ice blade standing on its base (bx, by), tip at (tx, ty), w wide at the base. Shaded in an ice ramp
## C (dark to bright, 8 steps): a lit facet on the left with a pale edge, a bright ridge, a deep facet on the
## right, a white tip, a dark rim, and a notch cut into one side so it reads as a shard, not a cone.
## opts: { a (alpha), white (flash it white), glint (0..1: a highlight across it at that height, or -1),
## jag (0..1: where the notch starts, or -1), dim (steps darker, for back rows) }.
static func blade(p: Px.Painter, bx: float, by: float, tx: float, ty: float, w: float, C: Array, opts: Dictionary = {}) -> void:
	var dx := tx - bx
	var dy := ty - by
	var L := Px.hypot(dx, dy)
	if L < 1.5 or w < 0.5:
		return
	var ux := dx / L
	var uy := dy / L
	var nx := -uy
	var ny := ux
	var a: float = opts.a if opts.get("a") != null else 1.0
	var dim: float = opts.dim if opts.get("dim") != null else 0.0
	var jag: float = opts.jag if opts.get("jag") != null else -1.0
	var glint: float = opts.glint if opts.get("glint") != null else -1.0
	var white: bool = true if opts.get("white") else false
	var K := func(i: float) -> int: return C[int(Px.clamp(i - dim, 0.0, C.size() - 1))]
	var hw := w / 2.0
	# half widths on the left (lit) and right (shadow) sides at height u; the notch steps the right side in
	var left := func(u: float) -> float: return hw * (1.0 - u) + 0.35
	var right := func(u: float) -> float: return hw * (1.0 - u) * (0.55 if (jag >= 0.0 and u > jag) else 1.0) + 0.35
	var ridge := func(u: float) -> float: return -w * 0.12 * (1.0 - u)
	var pad := hw + 2.0
	p.shade(minf(bx, tx) - pad, minf(by, ty) - pad, maxf(bx, tx) + pad, maxf(by, ty), func(x: float, y: float, o) -> void:
		var rx := x - bx
		var ry := y - by
		var u := (rx * ux + ry * uy) / L
		var s := rx * nx + ry * ny
		if u < 0.0:
			return
		var l: float = left.call(minf(u, 1.0))
		var r: float = right.call(minf(u, 1.0))
		if u > 1.0 or s < -l or s > r:
			# a dark rim just outside the blade
			var over := (u - 1.0) * L if u > 1.0 else 0.0
			var out := maxf(over, -l - s if s < -l else s - r)
			if out < 1.0 and u < 1.0 + 1.0 / L:
				o.c = K.call(0.0)
				o.a = a
			return
		o.a = a
		if white:
			o.c = WHITE
			return
		var rd: float = ridge.call(u)
		var c: int
		if u > 0.88:
			c = WHITE
		elif absf(s - rd) < 0.55:
			c = K.call(6.0)
		elif s < rd:
			c = K.call(6.0) if s + l < 1.0 else (K.call(5.0) if (s + l) / maxf(1.0, rd + l) > 0.55 else K.call(4.0))
		else:
			c = K.call(1.0) if r - s < 1.1 else (K.call(2.0) if (s - rd) / maxf(1.0, r - rd) > 0.5 else K.call(3.0))
		# the notch's ledge catches light; a little glitter in the lit facet
		if jag >= 0.0 and absf(u - jag) * L < 0.8 and s > rd:
			c = K.call(6.0)
		elif s < rd and c != K.call(6.0) and (Px.i32(floori(x) * 73856093) ^ Px.i32(floori(y) * 19349663)) % 997 < 30:
			c = K.call(7.0)
		if glint >= 0.0 and s <= rd + 0.6:
			var g := absf(u - glint) * L
			if g < 0.8:
				c = WHITE
			elif g < 1.8:
				c = K.call(6.0)
		o.c = c)


## A snowflake design, seeded: pairs of side branches along each arm ([where 0..1, length 0..1 of the arm]),
## maybe a hexagonal plate round the heart, maybe forked tips.
static func flakeDesign(R: Px.Rng) -> Dictionary:
	var n := R.int_(1, 3)
	var branches := []
	for i in n:
		branches.append([0.38 + (0.4 * (i + R.range(0.2, 0.8))) / n, R.range(0.24, 0.36) * (1.0 - i * 0.15)])
	return {"branches": branches, "plate": R.chance(0.45), "fork": R.chance(0.45)}


## A six-armed snowflake of radius r turned by rot, crisp 1 px lines: pale arms, side branches at 60 degrees,
## a plate or forked tips by design, a white heart, light. hot (0..1) makes it twinkle white.
static func snowflake(p: Px.Painter, x: float, y: float, r: float, rot: float, d: Dictionary, C: Array, opts: Dictionary = {}) -> void:
	var n := C.size()
	var a: float = opts.a if opts.get("a") != null else 1.0
	var hot: float = opts.hot if opts.get("hot") != null else 0.0
	rot = Px.round(rot / (PI / 18.0)) * (PI / 18.0)  # turn in 10 degree ticks, like sprite frames
	if r < 1.2:
		p.dot(x, y, WHITE, a)
		return
	if r < 2.6:
		# too small for branches: a six-point star that flips between two poses as it turns
		var pose := floori((fmod(rot, PI / 3.0) + PI / 3.0) / (PI / 6.0)) % 2
		var pts := [[1, 0], [-1, 0], [0, 1], [0, -1]] if pose else [[1, 1], [-1, -1], [1, -1], [-1, 1]]
		for q in pts:
			p.dot(x + q[0], y + q[1], WHITE if hot > 0.5 else C[n - 3], a)
		p.dot(x, y, WHITE, a)
		p.glow(x, y, 4.0, C[n - 3], 0.2 * a)
		return
	# detail by size: a bare star when small, one pair of branches when middling, the full design when big
	var arm: int = WHITE if hot > 0.5 else C[n - 2]
	var br: int = C[n - 2] if hot > 0.5 else C[n - 3]
	var big := r >= 7.0
	var branches: Array = [] if r < 4.0 else (d.branches.slice(0, 2) if big else [[0.58, 0.36]])
	for k in 6:
		var g := rot + (k * TAU) / 6.0
		var ca := cos(g)
		var sa := sin(g)
		p.line(x, y, x + ca * r, y + sa * r, arm, a)
		for b in branches:
			var u: float = b[0]
			var l: float = b[1]
			var bx := x + ca * r * u
			var by := y + sa * r * u
			var bl := maxf(1.0, r * l)
			for s: int in [-1, 1]:
				p.line(bx, by, bx + cos(g + (s * PI) / 3.0) * bl, by + sin(g + (s * PI) / 3.0) * bl, br, a)
		if d.fork and big and not d.plate:
			for s: int in [-1, 1]:
				p.dot(x + ca * r + cos(g + s * 0.9) * 1.2, y + sa * r + sin(g + s * 0.9) * 1.2, br, a)
		p.dot(x + ca * r, y + sa * r, WHITE, a)
	if d.plate and big:
		var q := r * 0.34
		for k in 6:
			var g0 := rot + PI / 6.0 + (k * TAU) / 6.0
			var g1 := g0 + TAU / 6.0
			p.line(x + cos(g0) * q, y + sin(g0) * q, x + cos(g1) * q, y + sin(g1) * q, C[n - 3], a)
	p.px(x, y, WHITE)
	p.glow(x, y, 3.0 + r * 1.2, C[n - 4], (0.14 + 0.35 * hot) * a)
	if hot > 0.3:
		p.glow(x, y, 2.0 + r * 0.5, WHITE, 0.3 * hot * a)


## Nothing outlives the effect: trims the life of every particle, bit and pane that would last past D.
static func endBy(t: float, D: float, ...systems: Array) -> void:
	var left := maxf(0.001, D - 0.05 - t)
	for sys in systems:
		for q in sys.list:
			if q.life > left:
				q.life = left


## Cracks racing out from (x, y) through a shape: n jagged lines that wander, fork now and then and stop at
## the shape's edge (inside(x, y) says what's in it). Each point carries its distance from the start along the
## crack, so drawFractures can grow them at a speed. Returns polylines [[x, y, d], ...].
static func fractures(R: Px.Rng, inside: Callable, x: float, y: float, n: float, opts: Dictionary = {}) -> Array:
	var out := []
	var step: Array = opts.step if opts.get("step") != null else [1.6, 2.6]
	var len: float = opts.len if opts.get("len") != null else 18.0
	var fork: float = opts.fork if opts.get("fork") != null else 0.16
	var a0: float = opts.a0 if opts.get("a0") != null else R.range(0.0, TAU)
	var spread: float = opts.spread if opts.get("spread") != null else TAU
	var i := 0
	while i < n:
		_walk(R, inside, out, step, fork, x, y, 0.0, a0 + (i / n) * spread + R.range(-0.3, 0.3) * minf(1.0, spread / TAU), len, 0)
		i += 1
	return out


static func _walk(R: Px.Rng, inside: Callable, out: Array, step: Array, fork: float, x: float, y: float, d: float, a: float, len: float, depth: int) -> void:
	var pts := [[x, y, d]]
	var s := 0
	while s < len:
		a += R.range(-0.55, 0.55)
		var st := R.range(step[0], step[1])
		var nx := x + cos(a) * st
		var ny := y + sin(a) * st
		if not inside.call(nx, ny):
			break
		x = nx
		y = ny
		d += st
		pts.append([x, y, d])
		if depth < 2 and pts.size() > 2 and R.chance(fork):
			_walk(R, inside, out, step, fork, x, y, d, a + R.sign() * R.range(0.6, 1.2), ceilf(len * 0.5), depth + 1)
		s += 1
	if pts.size() > 1:
		out.append(pts)


static func _seg(pts: Array, i: int, reach: float, ox: float, oy: float) -> Variant:
	var x0: float = pts[i - 1][0]
	var y0: float = pts[i - 1][1]
	var d0: float = pts[i - 1][2]
	var x1: float = pts[i][0]
	var y1: float = pts[i][1]
	var d1: float = pts[i][2]
	if d0 >= reach:
		return null
	var u := minf(1.0, (reach - d0) / maxf(0.01, d1 - d0))
	return [x0 + ox, y0 + oy, x0 + ox + (x1 - x0) * u, y0 + oy + (y1 - y0) * u, reach - d1 < 3.0]


## Draw cracks grown out to distance `reach` from their start: a bright line over a dark one a pixel lower (an
## engraved fracture), a white-hot tip while they run, light leaking out along them. ox, oy shift them.
static func drawFractures(p: Px.Painter, cracks: Array, reach: float, C: Array, opts: Dictionary = {}) -> void:
	var n := C.size()
	var ox: float = opts.ox if opts.get("ox") != null else 0.0
	var oy: float = opts.oy if opts.get("oy") != null else 0.0
	var hot: bool = opts.hot if opts.get("hot") != null else true
	var a: float = opts.a if opts.get("a") != null else 1.0
	for pts in cracks:
		for i in range(1, pts.size()):
			var s: Variant = _seg(pts, i, reach, ox, oy)
			if not s:
				break
			p.line(s[0], s[1] + 1.0, s[2], s[3] + 1.0, C[mini(2, n - 1)], a)
	for pts in cracks:
		for i in range(1, pts.size()):
			var s: Variant = _seg(pts, i, reach, ox, oy)
			if not s:
				break
			var tip: bool = hot and s[4]
			p.line(s[0], s[1], s[2], s[3], WHITE if tip else C[n - 2], a)
			if tip:
				p.glow(s[2], s[3], 5.0, C[n - 3], 0.5 * a)
			elif i % 2:
				p.glow(s[2], s[3], 3.0, C[n - 3], 0.18 * a)
