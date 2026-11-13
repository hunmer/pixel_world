# The faceted ice shell, the cracks, and the shards, mist and glints of the burst are adapted from Sprite
# Fusion's open-source ice (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/spawn/shatter-death.js@60097322821f0d07804f2e0a9d2a2f26d7e72a04
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Shatter death",
	"desc": "Frost races up the body and seals it in faceted ice, a glint sweeps it, cracks spread from the chest, then it bursts into its own facets that tumble, bounce and melt.",
	"tags": ["spawn", "death", "ice", "freeze", "shatter", "shards", "one-shot"],
	"size": [172, 96],
	"origin": [84, 84],
	"duration": 3.3,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#0e1636", "#1a2f66", "#2557a3", "#3488d6", "#5fc0f0", "#a2e6ff", "#dcf8ff", "#ffffff"],
		"seed": 14,
	},
}

static var FEAR := {"turn": 0.9, "lean": -2, "crouch": 2, "fx": -9, "fy": -31, "bx": 9, "by": -31, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"poses": [[-0.2, Px.READY], [0.08, FEAR, "snap"], [0.3, Px.merge(FEAR, {"lean": -3, "fy": -34})], [0.5, FEAR], [3.3, FEAR]],
	"hits": [{"t": 0.5, "stop": 0.02, "shake": 0.06, "amp": 1}, {"t": 1.4, "stop": 0.09, "shake": 0.26, "amp": 3}],
}

const LOCK := 0.5
const CRACK := 1.05
const BURST := 1.4
static func actorAlpha(t: float, _o: Dictionary) -> float:
	return 1.0 if t < BURST else 0.0


const M32 := 0xFFFFFFFF

var C: Array
var R: Px.Rng
var body: Lib.Body
var W: int
var H: int
var X0: float
var Y0: float
var ice: PackedInt32Array
var col: PackedInt32Array
var glass: PackedInt32Array
var solid: PackedByteArray
var spikes: Array = []
var IX: float
var IY: float
var cracks: Array = []
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var pieces: Array = []
var rime: Array = []
var t := 0.0
var locked := false
var cracked := false
var burst := false


func at(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and ice[y * W + x] >= 0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	body = Lib.bodyOf(o.actor, C)
	W = body.w + 2
	H = body.h + 1
	X0 = body.x - 1.0
	Y0 = body.y - 1.0
	# the ice: the body grown by a pixel (not below its feet), cut into facets round a few seeds
	ice = PackedInt32Array()
	ice.resize(W * H)
	ice.fill(-1)
	col = PackedInt32Array()
	col.resize(W * H)
	glass = PackedInt32Array()
	glass.resize(W * H)
	solid = PackedByteArray()
	solid.resize(W * H)
	for y in H:
		for x in W:
			var mx := x - 1
			var my := y - 1
			if body.on(mx, my) or (my < body.h - 1 and (body.on(mx - 1, my) or body.on(mx + 1, my) or body.on(mx, my - 1) or body.on(mx, my + 1))):
				ice[y * W + x] = 0
	var seeds := []
	for i in 22:
		var x := 0.0
		var y := 0.0
		var tries := 0
		while true:
			x = R.range(0.0, W)
			y = R.range(0.0, H)
			if not (ice[floori(y) * W + floori(x)] < 0):
				break
			tries += 1
			if not (tries < 40):
				break
		seeds.append([x, y])
	for y in H:
		for x in W:
			var i := y * W + x
			if ice[i] < 0:
				continue
			var d1 := 1e9
			var d2 := 1e9
			var k := 0
			for j in seeds.size():
				var sx: float = seeds[j][0]
				var sy: float = seeds[j][1]
				var d := Px.hypot(x + 0.5 - sx, (y + 0.5 - sy) * 0.85)
				if d < d1:
					d2 = d1
					d1 = d
					k = j
				elif d < d2:
					d2 = d
			ice[i] = k
			# each facet catches the light by where it faces: up and left bright, down and right deep
			var sx: float = seeds[k][0]
			var sy: float = seeds[k][1]
			var lit := Px.clamp(0.55 + 0.35 * (Px.rand(k, 41) - 0.5) - 0.5 * ((sx - W / 2.0) / W) - 0.55 * ((sy - H / 2.0) / H))
			var cl: Variant = body.cell(x - 1, y - 1)
			var own: Variant = cl.c if cl != null else null
			# under the ice: the body's own colours, gone cold; over it: a see-through facet catching the light
			col[i] = Px.mix(own, C[4], 0.36) if own else C[3]
			glass[i] = C[3 + mini(2, floori(lit * 3.0))]
			var sc := 0
			if d2 - d1 < 0.42 and not own:
				sc = C[6] if lit > 0.5 else C[5]  # the seams between facets, out in the shell
			elif d2 - d1 < 0.42:
				col[i] = Px.mix(col[i], C[6], 0.45)  # and faint where they cross the body
			if not at(x - 1, y) or not at(x, y - 1):
				sc = C[6]  # lit outer rim, top and left
			if not at(x + 1, y) or (not at(x, y + 1) and y < H - 1):
				sc = C[3]  # shaded rim, bottom and right
			if sc:
				col[i] = sc
				solid[i] = 1
	# rime spikes where the ice pushes out: on the shoulders, the head and the feet
	for i in 7:
		var x := R.int_(1, W - 2)
		var y0 := R.int_(2, H - 3)
		var y := y0
		while y > 0 and at(x, y - 1):
			y -= 1
		if at(x, y):
			spikes.append({"x": X0 + x + 0.5, "base": Y0 + y + 1.0, "h": R.range(3.0, 6.0), "w": R.range(2.5, 3.5), "lean": R.range(-2.5, 2.5), "at": LOCK + R.range(-0.02, 0.08)})
	for sd in [-1.0, 1.0]:
		for i in 2:
			var h := R.range(5.0, 7.0) if i else R.range(8.0, 11.0)
			spikes.append({"x": sd * (R.range(11.0, 13.0) if i else R.range(7.0, 9.0)), "base": 0.0, "h": h, "w": 3.5 if i else 4.5, "lean": sd * h * R.range(0.25, 0.45), "at": R.range(0.08, 0.2)})
	# cracks from the chest
	IX = Px.round(W * 0.48)
	IY = Px.round(H * 0.42)
	for i in 7:
		walk(IX, IY, (i / 7.0) * TAU + R.range(-0.3, 0.3), 20.0)

	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [WHITE, C[6], C[5], C[4]], "haze": C[5]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()


func walk(x: float, y: float, a: float, len: float) -> void:
	var pts := [[x, y]]
	var s := 0
	while s < len:
		a += R.range(-0.5, 0.5)
		x += cos(a) * R.range(1.4, 2.4)
		y += sin(a) * R.range(1.4, 2.4)
		if not at(floori(x), floori(y)):
			break
		pts.append([x, y])
		if pts.size() > 3 and cracks.size() < 18 and R.chance(0.15):
			walk(x, y, a + R.sign() * R.range(0.6, 1.1), len / 2.0)
		s += 1
	cracks.append(pts)


func level(tt: float) -> float:
	return H * (1.0 - Px.Ease.outCubic(Px.clamp(tt / LOCK)))  # the frost line, mask row


# the burst: every facet flies as one piece of ice, carrying its own pixels
func shatter() -> void:
	var cells := {}
	for y in H:
		for x in W:
			var k := ice[y * W + x]
			if k < 0:
				continue
			if not cells.has(k):
				cells[k] = []
			var i := y * W + x
			cells[k].append([x, y, (col[i] & M32) if solid[i] else Px.mix(col[i], glass[i], 0.3)])
	for px: Array in cells.values():
		var cx := 0.0
		var cy := 0.0
		for e in px:
			cx += e[0] + 0.5
			cy += e[1] + 0.5
		cx /= px.size()
		cy /= px.size()
		var map := {}
		var r := -INF
		for e in px:
			r = maxf(r, Px.hypot(e[0] + 0.5 - cx, e[1] + 0.5 - cy))
		r += 1.0
		for e in px:
			map["%d,%d" % [Px.round(e[0] + 0.5 - cx), Px.round(e[1] + 0.5 - cy)]] = e[2]
		var dx := cx - IX
		var dy := cy - IY
		var d := Px.hypot(dx, dy)
		if not d:
			d = 1.0
		var sp := R.range(55.0, 115.0)
		var life := R.range(1.3, 1.85)
		pieces.append({"id": pieces.size() + 1, "x": X0 + cx, "y": Y0 + cy, "vx": (dx / d) * sp + R.range(-18.0, 18.0), "vy": (dy / d) * sp * 0.6 - R.range(110.0, 220.0), "a": 0.0, "va": R.range(-9.0, 9.0), "r": r, "map": map, "life": life, "max": life, "rest": false, "n": px.size()})
	for i in 64:
		var a := -PI / 2.0 + R.range(-1.45, 1.45)
		var sp := R.range(60.0, 180.0)
		bits.add({"kind": B.SHARD, "x": X0 + IX + R.range(-6.0, 6.0), "y": Y0 + IY + R.range(-8.0, 8.0), "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 0.85, "drag": 0.6, "bounce": 0.3, "life": R.range(0.9, 1.6), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.5, 3.2), "c": R.pick([C[7], C[6], C[5]])})
	for i in 14:
		ps.spawn(P.VAPOUR, R.range(-10.0, 10.0), -R.range(1.0, 20.0), R.sign() * R.range(20.0, 80.0), -R.range(4.0, 20.0), R.range(0.6, 1.1), C[6] if R.chance(0.5) else C[5], R.range(2.5, 4.5))
	for i in 16:
		ps.spawn(P.STAR, R.range(-16.0, 16.0), -R.range(4.0, 38.0), R.range(-40.0, 40.0), -R.range(10.0, 60.0), R.range(0.4, 1.0), R.pick([WHITE, C[6]]), R.range(1.0, 2.4))
	lights.add(0.0, Y0 + IY, 46.0, WHITE, 0.75, 0.14)
	lights.add(0.0, Y0 + IY, 70.0, C[4], 0.6, 0.5)


func update(dt: float) -> void:
	t += dt
	# the cold climbs: rime sparkles at the frost line, vapour rolls off the feet
	if t < LOCK:
		var y := Y0 + level(t)
		if R.chance(0.7):
			ps.spawn(P.STAR, R.range(-10.0, 10.0), y, R.range(-12.0, 12.0), -R.range(0.0, 18.0), R.range(0.25, 0.5), WHITE if R.chance(0.5) else C[6], R.range(0.8, 1.8))
		if R.chance(0.25):
			ps.spawn(P.VAPOUR, R.range(-8.0, 8.0), -1.0, R.sign() * R.range(15.0, 50.0), -R.range(2.0, 10.0), R.range(0.6, 1.0), C[6], R.range(2.0, 3.5))
	if not locked and t >= LOCK:
		locked = true
		lights.add(0.0, -20.0, 54.0, C[4], 0.6, 0.3)
		for i in 6:
			ps.spawn(P.STAR, R.range(-12.0, 12.0), -R.range(4.0, 36.0), 0.0, -4.0, R.range(0.35, 0.7), R.pick([WHITE, C[6]]), R.range(1.2, 2.4))
	if locked and t < CRACK and R.chance(0.08):
		ps.spawn(P.STAR, R.range(-11.0, 11.0), -R.range(2.0, 36.0), 0.0, -3.0, R.range(0.3, 0.6), R.pick([WHITE, C[6]]), R.range(0.8, 2.0))
	if not cracked and t >= CRACK:
		cracked = true
		for i in 5:
			var a := R.range(0.0, TAU)
			var sp := R.range(60.0, 150.0)
			bits.add({"kind": B.SHARD, "x": X0 + IX, "y": Y0 + IY, "vx": cos(a) * sp, "vy": sin(a) * sp - 60.0, "g": 0.8, "drag": 0.6, "bounce": 0.3, "life": R.range(0.5, 0.9), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.0, 2.0), "c": C[6]})
		lights.add(0.0, Y0 + IY, 24.0, WHITE, 0.7, 0.1)
	if not burst and t >= BURST:
		burst = true
		shatter()
	# the pieces: tumble, bounce, skid to a stop, melt
	var i := pieces.size() - 1
	while i >= 0:
		var q: Dictionary = pieces[i]
		q.life -= dt
		if q.life <= 0.0:
			pieces.remove_at(i)
			i -= 1
			continue
		if q.rest:
			if t < meta.duration - 0.9 and R.chance(0.02):
				ps.spawn(P.VAPOUR, q.x, q.y - 1.0, R.range(-4.0, 4.0), -R.range(4.0, 10.0), R.range(0.5, 0.8), C[5], R.range(1.5, 2.5))
			i -= 1
			continue
		q.vy += 900.0 * dt
		q.vx -= q.vx * 0.5 * dt
		q.x += q.vx * dt
		q.y += q.vy * dt
		q.a += q.va * dt
		var g: float = -q.r * 0.55
		if q.y > g and q.vy > 0.0:
			q.y = g
			if q.vy > 90.0:
				rime.append({"x": q.x, "w": 2.0 + q.r * 0.6, "t0": t})
				q.vy *= -0.32
				q.vx *= 0.65
				q.va = q.va * 0.5 + R.range(-4.0, 4.0)
				if q.n > 8:
					ps.spawn(P.STAR, q.x, q.y, 0.0, -6.0, 0.3, WHITE, 1.2)
				for j in 2:
					ps.spawn(P.DUST, q.x + R.range(-2.0, 2.0), -0.5, R.sign() * R.range(10.0, 30.0), -R.range(2.0, 8.0), R.range(0.3, 0.5), C[5], R.range(1.2, 2.0))
			elif absf(q.vx) > 12.0:
				q.vy = 0.0
				q.vx *= 0.9
				q.va *= 0.85
			else:
				q.rest = true
				q.vy = 0.0
				q.vx = 0.0
		i -= 1
	bits.update(dt)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# frost on the floor under the feet, spreading as the ice locks, gone as the pieces melt
	var k := Px.smooth(0.1, LOCK, t) * (1.0 - Px.smooth(BURST + 0.6, BURST + 1.6, t))
	var reach := 6.0 + 12.0 * Px.smooth(0.0, LOCK + 0.3, t)
	if k > 0.0:
		for x in range(floori(-reach), ceili(reach) + 1):
			var h := Px.rand(x, 17)
			var e := 1.0 - absi(x) / (reach + 1.0)
			p.dot(x, 0.0, WHITE if h < 0.3 else C[6], k * minf(1.0, e * 2.0))
			if h < 0.5:
				p.dot(x, 1.0, C[5], k * e)
			if h < 0.35 and e > 0.3:
				p.dot(x, -1.0, C[6], k * e)
	if k > 0.0:
		p.glow(0.0, -2.0, 26.0, C[4], 0.25 * k)
	# rime left where the pieces hit the floor
	for r in rime:
		var a := Px.clamp((t - r.t0) / 0.08) * (1.0 - Px.smooth(meta.duration - 1.0, meta.duration - 0.15, t))
		var x := floori(r.x - r.w)
		while x <= r.x + r.w:
			var h := Px.rand(x, 23)
			if h < 0.7:
				p.dot(x, 0.0, WHITE if h < 0.25 else C[6], a)
			if h < 0.3:
				p.dot(x, 1.0, C[5], a * 0.7)
			x += 1
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	if not burst:
		# the ice body: everything below the frost line, a white rime edge at the line itself
		var lv := level(t)
		var shake := (1.0 if floori(t * 50.0) % 2 else -1.0) * (1.0 if t > BURST - 0.15 else 0.5) if (t > CRACK and t < BURST) else 0.0
		var glint := fmod((t - LOCK) * 0.9, 1.6) if t > LOCK else -1.0
		for y in H:
			if y < floori(lv):
				continue
			for x in W:
				var i := y * W + x
				if ice[i] < 0:
					continue
				var c: int = ((WHITE if Px.rand(x, 5) < 0.6 else C[6]) if (y == floori(lv) and t < LOCK) else (WHITE if (t >= LOCK and t < LOCK + 0.05) else (col[i] & M32)))
				# a glint runs diagonally across the ice
				var g := absf((x + (H - y) * 0.6) / (W + H * 0.6) - glint)
				var on := glint >= 0.0 and glint <= 1.0
				if on and g < 0.035:
					c = WHITE
				elif on and g < 0.07 and c != C[3]:
					c = C[6]
				p.px(X0 + x + shake, Y0 + y, c)
				if not solid[i] and c == (col[i] & M32):
					p.blend(X0 + x + shake, Y0 + y, glass[i], 0.3)
		# the dark outline that holds the ice together against the floor and the dark
		for y in range(maxi(0, floori(lv) - 1), H + 1):
			for x in range(-1, W + 1):
				if not at(x, y) and (at(x - 1, y) or at(x + 1, y) or (at(x, y + 1) and y + 1 >= lv) or at(x, y - 1)) and y < H:
					p.px(X0 + x + shake, Y0 + y, C[0])
		for s in spikes:
			var g := Px.Ease.outBack(Px.clamp((t - s.at) / 0.12), 2.4)
			if g > 0.0:
				Px.crystal(p, s.x + shake, s.base, s.h * g, s.w, s.lean * g, C, {"white": t < s.at + 0.04})
		if cracked:
			var k := Px.clamp((t - CRACK) / 0.25)
			for pts in cracks:
				var n := floori(pts.size() * k)
				for i in n:
					var x: float = pts[i][0]
					var y: float = pts[i][1]
					var fresh := i > n - 3 and t - CRACK < 0.3
					p.px(X0 + x + shake, Y0 + y, WHITE if fresh else C[7])
					if not fresh:
						p.px(X0 + x + shake, Y0 + y + 1.0, C[1])
		# cold light from the ice, a flash as it locks
		p.glow(0.0, -18.0, 30.0, C[4], 0.18 * Px.smooth(0.0, LOCK, t))
		if t > LOCK and t < LOCK + 0.18:
			Px.sparkle(p, -4.0, Y0 + 8.0, Px.round(8.0 * (1.0 - (t - LOCK) / 0.18)), WHITE, C[5], 0.6)
	elif t < BURST + 0.08:
		# the burst frame
		var k := (t - BURST) / 0.08
		p.circle(X0 + IX, Y0 + IY, 10.0 * (1.0 - k) + 3.0, WHITE)
	# the pieces: each drawn back from its own little map, so they turn without holes
	for q in pieces:
		var ca := cos(q.a)
		var sa := sin(q.a)
		var fade := minf(1.0, q.life / 0.5)
		var r := ceili(q.r)
		var map: Dictionary = q.map
		for py in range(-r, r + 1):
			for px in range(-r, r + 1):
				var ux := Px.round(px * ca + py * sa)
				var uy := Px.round(-px * sa + py * ca)
				var c: Variant = map.get("%d,%d" % [ux, uy])
				# a melting piece loses pixels at random rather than dithering away
				if c and Px.rand(ux, uy, q.id) < fade:
					p.px(floorf(q.x) + px, floorf(q.y) + py, WHITE if q.max - q.life < 0.05 else c)
		if q.n > 6:
			p.glow(q.x, q.y, 6.0, C[5], 0.2 * fade)
	bits.draw(p)
	ps.draw(p, "front")
	lights.draw(p)
