# port-of: src/fx/shadow/grasping-hands.js@e47ad0b135d79fbaa2bef7e4d88799c180b30ff8
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PK := Lib.PK
const WHITE := Px.WHITE

static var meta := {
	"name": "Grasping hands",
	"desc": "Shadow arms burst up out of a dark pool with a splash, clench their hands into claws, strain, and are dragged back under, fingers clawing at the air.",
	"tags": ["shadow", "hands", "arms", "grab", "ground", "dark", "magic", "one-shot"],
	"size": [200, 116],
	"origin": [100, 100],
	"duration": 3.1,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOID, "seed": 5},
}

const RX := 42.0
const OPEN := 0.32
const SHUT := 2.35
const LX := -0.6
const LY := -0.8


# an arm at t: it rises out of the pool along its own shape, bent at the elbow, swaying; returns its spine
static func arm(A: Dictionary, t: float) -> Variant:
	var e := Px.clamp((t - A.t0) / 0.22)
	var d := Px.clamp((t - A.td) / 0.34)
	if e <= 0.0 or d >= 1.0:
		return null
	var rise := Px.Ease.outBack(e, 1.6) * (1.0 - Px.Ease.inQuad(d))
	var hidden: float = (1.0 - rise) * A.L
	var grip := gripOf(A, t)
	var strain: float = sin(t * 47.0 + A.ph) * 0.03 if (t > A.t0 + 0.5 and t < A.td) else 0.0
	var elbow: float = A.bend * (0.3 + 0.7 * grip) * (1.0 - d) + strain
	var lean: float = A.lean + 0.06 * sin(t * 2.2 + A.ph) + d * A.lean * 0.6
	var th := -PI / 2.0 + lean
	var x: float = A.x - cos(th) * hidden
	var y: float = A.y - sin(th) * hidden
	var pts := []
	var n := ceili(A.L / 0.5)
	for i in n + 1:
		var s := i * 0.5
		var u: float = s / A.L
		pts.append({"x": x, "y": y, "th": th, "w": A.W * (1.0 - 0.5 * u) + 0.4, "u": u})
		th += 0.5 * (elbow * exp(-(pow((u - 0.52) / 0.07, 2.0))) / (0.07 * sqrt(PI) * A.L) + A.curve / A.L)
		x += cos(th) * 0.5
		y += sin(th) * 0.5
	return pts


# how closed the hand is: opens as it rises, snaps shut into a claw, splays as it's dragged down
static func gripOf(A: Dictionary, t: float) -> float:
	var shut := Px.Ease.outBack(Px.clamp((t - A.t0 - 0.3) / 0.12), 2.2)
	var splay := Px.smooth(A.td, A.td + 0.12, t)
	return shut * (1.0 - splay) - 0.35 * splay


# the arm in cross-sections, lit like the tendrils: a near-black body, a bright edge toward the light
static func drawArm(p: Px.Painter, A: Dictionary, pts: Array, C: Array) -> void:
	var surf: float = A.y
	for q: Dictionary in pts:
		if q.y > surf:
			continue
		var nx := -sin(q.th)
		var ny := cos(q.th)
		var ks := 1.0 if nx * LX + ny * LY >= 0.0 else -1.0
		var v: float = -q.w
		while v <= q.w:
			var x: float = q.x + nx * v
			var y: float = q.y + ny * v
			var u: float = (v / q.w) * ks
			if y <= surf:
				p.px(x, y, C[2] if u > 0.55 else (C[1] if u > -0.45 else C[0]))
			v += 0.5
	for q: Dictionary in pts:
		if q.y > surf:
			continue
		var nx := -sin(q.th)
		var ny := cos(q.th)
		var f := nx * LX + ny * LY
		var ks := 1.0 if f >= 0.0 else -1.0
		var l: float = ks * q.w
		if q.y - ny * l <= surf:
			p.px(q.x - nx * l, q.y - ny * l, C[3])
		if q.y + ny * l <= surf:
			p.px(q.x + nx * l, q.y + ny * l, C[7] if absf(f) > 0.8 else C[6])
	var base: Variant = null
	for q: Dictionary in pts:
		if q.y <= surf:
			base = q
			break
	if base:
		p.line(base.x - base.w - 1.5, surf, base.x + base.w + 1.5, surf, C[5])


static func bone(p: Px.Painter, C: Array, side: float, x0: float, y0: float, ang: float, len: float, last: bool) -> Array:
	var x1 := x0 + cos(ang) * len
	var y1 := y0 + sin(ang) * len
	var ox := Px.round(-sin(ang) * side * -1.0)
	var oy := Px.round(cos(ang) * side * -1.0)
	p.line(x0, y0, x1, y1, C[1])
	p.line(x0 + ox, y0 + oy, x1 + ox, y1 + oy, C[5])
	if last:
		p.px(x1, y1, WHITE)
		p.px(x1 + cos(ang), y1 + sin(ang), C[7])
	return [x1, y1]


# a hand on the arm's end: a palm, four fingers and a thumb, each two bones with a lit edge and a pale claw
static func drawHand(p: Px.Painter, A: Dictionary, pts: Array, C: Array, t: float) -> void:
	var tip: Dictionary = pts[pts.size() - 1]
	if tip.y > A.y - 2.0:
		return
	var th: float = tip.th
	var dx := cos(th)
	var dy := sin(th)
	var nx := -dy
	var ny := dx
	var g := gripOf(A, t)
	var side: float = A.curl
	var cx: float = tip.x + dx * 2.6
	var cy: float = tip.y + dy * 2.6
	p.shade(cx - 5.0, cy - 5.0, cx + 5.0, cy + 5.0, func(x, y):
		var a: float = (x - cx) * dx + (y - cy) * dy
		var b: float = (x - cx) * nx + (y - cy) * ny
		var d := pow(a / 3.0, 2.0) + pow(b / 2.7, 2.0)
		if d > 1.25:
			return null
		if d > 1.0:
			return C[6] if b * side < 0.0 else C[3]
		return C[2] if b * side < -1.0 else C[1])
	var spread := 1.0 - 0.65 * maxf(0.0, g)
	var curl := g * 1.2
	var offs := [-2.2, -0.75, 0.75, 2.2]
	for i in offs.size():
		var o: float = offs[i]
		var bx := cx + dx * 2.6 + nx * o * 0.9
		var by := cy + dy * 2.6 + ny * o * 0.9
		var len := 2.6 if (i == 0 or i == 3) else 3.2
		var a0 := th + o * 0.2 * spread
		var j := bone(p, C, side, bx, by, a0 + curl * side * 0.6, len, false)
		bone(p, C, side, j[0], j[1], a0 + curl * side * 1.5, len * 0.85, true)
	var jt := bone(p, C, side, cx - nx * side * 2.4, cy - ny * side * 2.4, th - side * (1.0 - 0.6 * g), 2.4, false)
	bone(p, C, side, jt[0], jt[1], th - side * (0.6 - 1.4 * g), 2.0, true)
	p.glow(cx, cy, 8.0, C[5], 0.18 + 0.3 * maxf(0.0, g))


static func rx(tt: float) -> float:
	return RX * Px.Ease.outCubic(Px.clamp(tt / OPEN)) * (1.0 - Px.Ease.inCubic(Px.clamp((tt - SHUT) / 0.45)))


var C: Array
var DIM: Array
var R: Px.Rng
var ps: Px.Particles
var puffs: Lib.Puffs
var ripples: Array = []
var splats: Array = []
var lights: Array = []
var t := 0.0
var acc := 0.0
var drops: Lib.Drops
var arms: Array


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	DIM = [C[0], C[0], C[1], C[1], C[3], C[4], C[5], C[6]]
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]], "haze": C[4]})
	puffs = Lib.Puffs.new({"rng": R, "flame": [C[7], C[6], C[5], C[4], C[3], C[2], C[1], C[1], C[0]], "soot": [Px.mix(C[3], C[2], 0.55), Px.mix(C[2], C[1], 0.5)], "cap": Px.mix(C[4], C[2], 0.5), "rim": [C[6], C[5], C[4]], "floor": floor_})
	ripples = []
	splats = []
	lights = []
	t = 0.0
	acc = 0.0
	drops = Lib.Drops.new({"onLand": func(x, y, v, s):
		if absf(x) < rx(t) * 0.95:
			ripples.append({"x": x, "t0": t, "life": 0.5, "w": 0.6})
		else:
			splats.append({"x": x, "t0": t, "s": s})})
	# four arms: two at the back, taller and dimmer, two in front; elbows bending toward the middle
	var LAY := [[-20.0, -2.5, 1], [17.0, -2.5, -1], [-30.0, 2.5, 1], [28.0, 2.5, -1]]
	arms = []
	for i in LAY.size():
		var x: float = LAY[i][0]
		var y: float = LAY[i][1]
		var toward: int = LAY[i][2]
		arms.append({
			"x": x + R.range(-3.0, 3.0), "y": y, "back": y < 0.0, "L": R.range(44.0, 52.0) if y < 0.0 else R.range(36.0, 44.0), "W": R.range(3.2, 3.8) if y < 0.0 else R.range(3.6, 4.2),
			"lean": -toward * R.range(0.16, 0.3), "bend": toward * R.range(0.35, 0.6), "curve": toward * R.range(0.05, 0.15), "curl": toward,
			"t0": 0.3 + [1, 3, 0, 2][i] * 0.06 + R.range(0.0, 0.03), "td": 1.45 + [2, 0, 3, 1][i] * 0.09 + R.range(0.0, 0.05), "ph": R.range(0.0, TAU), "up": false, "shut": false, "down": false,
		})


func splash(x: float, y: float, n: int, k: float) -> void:
	for i in n:
		drops.add(x + R.range(-2.0, 2.0), y - 1.0, R.range(-70.0, 70.0) * k, -R.range(90.0, 220.0) * k, 2.0 if R.chance(0.4) else 1.0)
	ripples.append({"x": x, "t0": t, "life": 0.7, "w": 1.0})
	lights.append({"x": x, "y": y - 7.0, "r": 30.0, "k": 0.55 * k, "life": 0.25, "max": 0.25})


func update(dt: float) -> void:
	t += dt
	for A: Dictionary in arms:
		if not A.up and t >= A.t0:
			A.up = true
			splash(A.x, A.y, 12, 1.0)
		if not A.shut and t >= A.t0 + 0.36:
			# the clench: a snap of light at the fist, a puff of dark breath, a few sparks
			A.shut = true
			var pts: Variant = arm(A, t)
			if pts:
				var q: Dictionary = pts[pts.size() - 1]
				lights.append({"x": q.x, "y": q.y, "r": 22.0, "k": 0.7, "life": 0.2, "max": 0.2})
				A.snap = {"x": q.x + cos(q.th) * 4.0, "y": q.y + sin(q.th) * 4.0, "t0": t}
				for i in 6:
					var a := R.range(0.0, TAU)
					var sp := R.range(60.0, 130.0)
					ps.spawn(P.SPARK, A.snap.x, A.snap.y, cos(a) * sp, sin(a) * sp - 20.0, R.range(0.12, 0.3))
				puffs.spawn(PK.SOOT, A.snap.x, A.snap.y, 0.0, -12.0, 0.6, 3.5)
		if not A.down and t >= A.td + 0.28:
			A.down = true
			splash(A.x, A.y, 8, 0.7)
	var r := rx(t)
	if r > 8.0 and t < SHUT - 0.4:
		acc += dt * 8.0
		while acc > 1.0:
			puffs.spawn(PK.SOOT, R.range(-0.8, 0.8) * r, -R.range(1.0, 4.0), R.range(-8.0, 8.0), -R.range(14.0, 28.0), R.range(0.6, 0.85), R.range(3.0, 6.0))
			acc -= 1.0
		if R.chance(dt * 12.0):
			ps.spawn(P.MOTE, R.range(-0.8, 0.8) * r, -2.0, R.range(-8.0, 8.0), -R.range(30.0, 70.0), R.range(0.5, 0.9), R.pick([C[7], C[6], C[5]]), R.range(0.6, 1.0))
		if R.chance(dt * 6.0):
			ps.spawn(P.VAPOUR, R.range(-0.7, 0.7) * r, -R.range(2.0, 8.0), R.range(-6.0, 6.0), -R.range(10.0, 22.0), R.range(0.6, 0.9), C[3] if R.chance(0.5) else C[4], R.range(3.0, 6.0))
		if R.chance(dt * 3.0):
			ripples.append({"x": R.range(-0.7, 0.7) * r, "t0": t, "life": 0.6, "w": 0.5})
	for a: Array in [ripples, splats]:
		for i in range(a.size() - 1, -1, -1):
			if t - a[i].t0 > a[i].get("life", 0.6):
				a.remove_at(i)
	for i in range(lights.size() - 1, -1, -1):
		lights[i].life -= dt
		if lights[i].life <= 0.0:
			lights.remove_at(i)
	drops.update(dt)
	puffs.update(dt)
	ps.update(dt)


func drawBack(p: Px.Painter) -> void:
	var r := rx(t)
	var k := r / RX
	Lib.floorPool(p, C, r, t, ripples)
	if k > 0.0:
		p.glow(0.0, -16.0, 80.0, C[4], 0.2 * k)
		p.glow(0.0, -8.0, r * 1.7 + 12.0, C[4], 0.3 * k)
		p.glow(0.0, 0.0, r * 1.15, C[5], 0.16 * k)
	puffs.draw(p, PK.SOOT, {"x": 0.0, "y": 6.0, "k": k, "reach": 70.0})
	ps.draw(p, "back")
	for A: Dictionary in arms:
		if A.back:
			var pts: Variant = arm(A, t)
			if pts:
				drawArm(p, A, pts, DIM)
				drawHand(p, A, pts, DIM, t)


func draw(p: Px.Painter) -> void:
	for A: Dictionary in arms:
		if not A.back:
			var pts: Variant = arm(A, t)
			if pts:
				drawArm(p, A, pts, C)
				drawHand(p, A, pts, C, t)
	for A: Dictionary in arms:
		if A.get("snap") != null and t - A.snap.t0 < 0.22:
			var u: float = (t - A.snap.t0) / 0.22
			Lib.ringFast(p, A.snap.x, A.snap.y, 2.0 + 5.0 * Px.Ease.outCubic(u), 1.0, C[6] if u < 0.4 else (C[5] if u < 0.7 else C[3]))
	drops.draw(p, C[1], C[5])
	for s: Dictionary in splats:
		var a: float = 1.0 - (t - s.t0) / 0.6
		p.dot(s.x, -0.5, C[1], a * 1.5)
		p.dot(s.x + 1.0, -0.5, C[2], a)
		p.dot(s.x, -1.5, C[5], a)
	ps.draw(p, "front")
	for l: Dictionary in lights:
		var q: float = l.life / l.max
		p.glow(l.x, l.y, l.r * (0.6 + 0.4 * q), C[5], l.k * q * q)
