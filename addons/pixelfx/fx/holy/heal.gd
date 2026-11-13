# port-of: src/fx/holy/heal.js@b6640aeffdc0d855bb6afe9ac2724f67646e3349
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Heal",
	"desc": "Petals of light bloom under the feet, a hoop of light rises up the body restoring its colour and leaving sparkles, and motes spiral up and pop into tiny hearts.",
	"tags": ["holy", "heal", "restore", "buff", "petals", "hearts", "character", "one-shot"],
	"size": [80, 104],
	"origin": [40, 92],
	"duration": 1.9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#3d2027", "#7d3f35", "#c97a4a", "#f2b46a", "#ffd994", "#fff0cf", "#fffaf2", "#ffffff"], "seed": 2},
}

static var HURT := {"turn": 0.8, "crouch": 5, "lean": 3, "hy": 1, "fx": 1, "fy": -21, "bx": 7, "by": -15, "ffx": 4, "fbx": -3}
static var UP := {"turn": 1.15, "crouch": -1, "fx": -13, "fy": -36, "bx": 14, "by": -36, "hy": -1, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"poses": [
		[-0.3, HURT],
		[0.16, Px.merge(HURT, {"crouch": 6})],
		[0.5, Px.merge(HURT, {"crouch": 3, "lean": 1, "hy": 0})],
		[0.78, UP],
		[1.2, Px.merge(UP, {"crouch": 0, "fy": -30, "by": -30, "hy": 0})],
		[1.9, Px.READY],
	],
}

const SY := 0.3
const NP := 8
const PR := 16.0
const LIFT0 := 0.16
const LIFT1 := 0.74
const TOPY := -43.0
const HEART := [".#.#.", "#####", ".###.", "..#.."]

# a tiny heart of light: cream body, a white glint, a warm rim
static func heart(p: Px.Painter, x: float, y: float, C: Array, a: float) -> void:
	var X := Px.round(x) - 2.0
	var Y := Px.round(y) - 2.0
	var at := func(i: int, j: int) -> bool: return j >= 0 and j < 4 and i >= 0 and i < 5 and String(HEART[j])[i] == "#"
	for j in range(-1, 5):
		for i in range(-1, 6):
			if at.call(i, j):
				p.dot(X + i, Y + j, WHITE if (i == 1 and j == 1) else (C[5] if j >= 2 else C[6]), a)
			elif at.call(i - 1, j) or at.call(i + 1, j) or at.call(i, j - 1) or at.call(i, j + 1):
				p.dot(X + i, Y + j, C[3], a * 0.9)
	p.glow(x, y, 6.0, C[5], 0.4 * a)


var C: Array
var A: Dictionary
var S: Dictionary
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var rows := {}
var petals: Array
var motes: Array
var t := 0.0
var burst := false
var lastRow := 1.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	A = o.actor
	S = Lib.shapeOf(A)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	rows = {}
	for xy: Array in S.edge:
		var y: int = xy[1]
		if not rows.has(y):
			rows[y] = []
		rows[y].append(xy[0])
	# petals, each blooming on its own beat round the ring
	petals = Px.arr(NP, func(k: int): return {"a": (k / float(NP)) * TAU + 0.2, "t0": 0.02 + ((k * 3) % NP) * 0.035, "w": R.range(4.2, 5.2)})
	# motes riding a spiral up round the body: from the petal tips as they open, and from the hoop when it bursts
	motes = []
	for k in NP:
		motes.append({"t0": 0.2 + k * 0.05, "th0": petals[k].a, "r0": PR * 0.9, "y0": -1.0, "w": 4.2 * (1.0 if k % 2 else -1.0), "v": R.range(46.0, 58.0), "life": R.range(0.75, 0.95), "kind": k % 2})
	for k in 8:
		motes.append({"t0": LIFT1 + R.range(0.0, 0.06), "th0": (k / 8.0) * TAU, "r0": R.range(12.0, 18.0), "y0": TOPY + R.range(-2.0, 4.0), "w": 3.6 * (1.0 if k % 2 else -1.0), "v": R.range(14.0, 34.0), "life": R.range(0.35, 0.6), "kind": (k + 1) % 2})


func hoopY(tt: float) -> float:
	return Px.lerp(0.0, TOPY, Px.Ease.inOutSine(Px.seg(tt, LIFT0, LIFT1)))


func hoopR(tt: float) -> float:
	return Px.lerp(PR, 12.0, Px.seg(tt, LIFT0, LIFT1))


func bloom(k: int, tt: float) -> float:
	var pe: Dictionary = petals[k]
	return Px.Ease.outBack(Px.seg(tt, pe.t0, pe.t0 + 0.3), 1.8) * (1.0 - Px.Ease.inBack(Px.seg(tt, 1.25 + k * 0.02, 1.6 + k * 0.02), 1.4))


# a petal of a lotus of light round the feet: rooted on a ring on the floor, leaning out as it opens,
# foreshortened as it turns away; a lit rim, a white vein, a translucent warm body, a white tip
func petal(p: Px.Painter, k: int, back: bool) -> void:
	var pe: Dictionary = petals[k]
	var g: float = pe.a + t * 0.4
	var near := sin(g) >= 0.0
	var b := bloom(k, t)
	if near == back or b <= 0.02:
		return
	var ca := cos(g)
	var sa := sin(g)
	var rb := 6.0
	var rt := rb + 9.0 * minf(1.2, b)
	var h := (7.0 if k % 2 else 9.0) * b
	var bx := ca * rb
	var by := sa * rb * SY
	var tx := ca * rt
	var ty := sa * rt * SY - h
	var L := Px.hypot(tx - bx, ty - by)
	if L < 1.5:
		return
	var ux := (tx - bx) / L
	var uy := (ty - by) / L
	var W: float = pe.w * minf(1.0, b) * (0.35 + 0.65 * absf(sa))
	var pad := W + 1.0
	var CC := C
	p.each(minf(bx, tx) - pad, minf(by, ty) - pad, maxf(bx, tx) + pad, maxf(by, ty) + pad, func(x: float, y: float, sx: int, sy: int) -> void:
		var dx := x - bx
		var dy := y - by
		var u := (dx * ux + dy * uy) / L
		if u < 0.0 or u > 1.0:
			return
		var hw := W * pow(sin(PI * pow(u, 0.6)), 0.7) + 0.2
		var v := absf(-dx * uy + dy * ux) / hw
		if v > 1.0:
			return
		if u > 0.9:
			p.put(sx, sy, WHITE, 1.0)
			return
		if v > 0.7:
			p.put(sx, sy, CC[3] if u < 0.3 else (CC[5] if u < 0.7 else CC[6]), 1.0)
			return
		if v < 0.2 and u > 0.15 and u < 0.85:
			p.put(sx, sy, CC[5] if u < 0.55 else CC[6], 0.75 if back else 0.85)
			return
		p.blendPx(sx, sy, CC[3] if u < 0.45 else CC[4], 0.6 if back else 0.45))
	p.glow(tx, ty, 5.0, C[5], 0.35 * minf(1.0, b))


# the hoop of light rising up the body: far half behind, near half in front, a soft glow round it
func hoop(p: Px.Painter, back: bool) -> void:
	if t < LIFT0 or t > LIFT1 + 0.12:
		return
	var y := hoopY(t)
	var r := hoopR(t) * (1.0 - (t - LIFT1) / 0.12 if t > LIFT1 else 1.0)
	var keep: Callable = (func(g): return sin(g) < 0.0) if back else (func(g): return sin(g) >= 0.0)
	var CC := C
	Lib.oval(p, 0.0, y, r, r * SY, func(g): return WHITE if sin(g) > 0.5 else CC[6], 0.8 if back else 1.0, keep)
	if not back:
		Lib.oval(p, 0.0, y + 1.0, r - 0.5, r * SY, C[4], 1.0, keep)
		for i in range(-2, 3):
			p.glow(i * r * 0.45, y, 8.0, C[5], 0.32)


func update(dt: float) -> void:
	t += dt
	# the hoop leaves sparkles on the body as it passes each row
	if t > LIFT0 and t < LIFT1:
		var Y := Px.round(hoopY(t))
		var y := lastRow
		while y > Y:
			var xs: Variant = rows.get(int(y))
			if not xs or not R.chance(0.45):
				y -= 1.0
				continue
			ps.spawn(P.STAR, R.pick(xs) + R.range(-1.0, 1.0) * 2.0, y, R.range(-4.0, 4.0), -R.range(4.0, 12.0), R.range(0.3, 0.55), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.6))
			y -= 1.0
		lastRow = minf(lastRow, Y)
	if not burst and t >= LIFT1:
		burst = true
		lights.add(0.0, TOPY, 26.0, C[5], 0.55, 0.3)
		lights.add(0.0, TOPY, 10.0, WHITE, 0.45, 0.08)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# a warm pool under the flower
	var pool := Px.smooth(0.0, 0.2, t) * (1.0 - Px.smooth(1.3, 1.75, t))
	if pool > 0.0:
		p.glow(0.0, -2.0, 30.0, C[4], 0.3 * pool)
	for k in NP:
		petal(p, k, true)
	hoop(p, true)
	ps.draw(p, "back")
	riders(p, true)


func draw(p: Px.Painter) -> void:
	# drained of colour above the hoop, restored below it with a warm glow at the line
	var drain := Px.smooth(0.0, 0.08, t)
	if t < LIFT1 + 0.35:
		var Y := 1.0 if t < LIFT0 else hoopY(t)
		var done := t >= LIFT1
		var CC := C
		var tt := t
		Lib.recolor(p, A, func(c: int, x: float, y: float) -> int:
			var d := y - Y
			if not done and d < -0.5:
				var l := Px.luma(c) * 0.88
				return Px.mix(c, Px.rgb(l * 236.0, l * 226.0, l * 222.0), 0.68 * drain)
			if not done and d < 1.0:
				return WHITE
			if not done and d < 2.5:
				return CC[6]
			var k := (0.45 * (1.0 - Px.seg(tt, LIFT1, LIFT1 + 0.35)) if done else 0.5 * exp(-(d - 2.5) / 5.0))
			return Px.mix(c, CC[5], k) if k > 0.05 else 0)
		if t > LIFT0 and not done:
			p.glow(0.0, Y, 18.0, C[5], 0.35)
	for k in NP:
		petal(p, k, false)
	hoop(p, false)
	if t >= LIFT1 and t < LIFT1 + 0.25:
		Px.sparkle(p, 0.0, TOPY, 8.0 * (1.0 - (t - LIFT1) / 0.25), WHITE, C[5], 0.6)
	riders(p, false)
	ps.draw(p, "front")
	lights.draw(p)


static func _at(m: Dictionary, aa: float) -> Array:
	var th: float = m.th0 + m.w * aa
	var r: float = m.r0 * (1.0 - 0.45 * (aa / m.life))
	return [cos(th) * r, m.y0 - m.v * aa, sin(th)]


# the spiralling motes, each popping into a heart or a sparkle at the end of its ride
func riders(p: Px.Painter, back: bool) -> void:
	for m: Dictionary in motes:
		var a: float = t - m.t0
		if a < 0.0:
			continue
		if a < m.life:
			var xyz := _at(m, a)
			var x: float = xyz[0]
			var y: float = xyz[1]
			var z: float = xyz[2]
			if (z < 0.0) != back:
				continue
			for j in 7:
				var aj := a - j * 0.03
				if aj < 0.0:
					break
				var txyz := _at(m, aj)
				if (txyz[2] < 0.0) != back:
					continue
				p.dot(txyz[0], txyz[1], WHITE if j == 0 else (C[6] if j < 3 else C[5]), (1.0 - j / 7.0) * (0.6 if back else 1.0))
			p.glow(x, y, 4.0, C[5], 0.2 if back else 0.4)
			continue
		# the pop: a quick sparkle, then a heart (or a star) that floats up and fades
		var u: float = (a - m.life) / 0.36
		if u >= 1.0 or back:
			continue
		var xy := _at(m, m.life)
		var x: float = xy[0]
		var y: float = xy[1]
		var k := 1.0 - Px.smooth(0.5, 1.0, u)
		if u < 0.12:
			Px.sparkle(p, x, y, 3.0, WHITE, C[6], 0.5)
		elif m.kind:
			heart(p, x, y - u * 6.0, C, k)
		else:
			Px.sparkle(p, x, y - u * 5.0, 1.0 + 2.0 * k * (0.7 + 0.3 * sin(a * 30.0)), WHITE, C[5], 0.45 * k)
