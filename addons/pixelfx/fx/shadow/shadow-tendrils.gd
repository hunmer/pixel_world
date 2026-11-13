# port-of: src/fx/shadow/shadow-tendrils.js@52783a8329acb2f00707bda6c349cf7876ce0266
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PK := Lib.PK
const WHITE := Px.WHITE

static var meta := {
	"name": "Shadow tendrils",
	"desc": "A dark pool opens on the floor; tentacles with lit rims and hooked tips lash up out of it with a splash, writhe, and sink back as it closes.",
	"tags": ["shadow", "tentacle", "tendril", "ground", "dark", "magic", "one-shot"],
	"size": [208, 130],
	"origin": [104, 106],
	"duration": 3.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOID, "seed": 3},
}

const RX := 40.0
const OPEN := 0.34
const SHUT := 2.5
const SINK := 0.5
const LX := -0.6
const LY := -0.8


# a tentacle's spine at t: it rises out of the pool along its own curve, a wave writhes up it, its lean sways
# and sometimes whips, and its tip curls into a hook; points every 0.5 px with angle and half-width
static func spine(T: Dictionary, t: float) -> Variant:
	var e := Px.clamp((t - T.t0) / 0.2)
	var s1 := Px.clamp((t - T.t1) / SINK)
	if e <= 0.0 or s1 >= 1.0:
		return null
	# it lashes up past its length and settles; going, it lifts a little, then slides back under
	var lift := 0.07 * sin(PI * Px.clamp(s1 / 0.3))
	var down := Px.Ease.inOutCubic(Px.clamp((s1 - 0.12) / 0.88))
	var rise := Px.Ease.outBack(e, 1.8) * (1.0 + lift) * (1.0 - down)
	var hidden: float = (1.0 - rise) * T.L
	var writhe: float = T.A * (0.25 + 0.75 * Px.smooth(T.t0 + 0.08, T.t0 + 0.5, t))
	var hook: float = (0.04 + T.H * Px.Ease.outBack(Px.clamp((t - T.t0 - 0.1) / 0.32), 2.5)) * (1.0 + 0.5 * s1) * (1.0 + 0.18 * sin(t * 2.3 + T.ph))
	var lean: float = T.lean + 0.12 * sin(t * 1.6 + T.ph)
	if T.whip:
		lean += T.whip.a * exp(-(pow((t - T.whip.t) / 0.14, 2.0)))
	var th := -PI / 2.0 + lean
	var x: float = T.x - cos(th) * hidden
	var y: float = T.y - sin(th) * hidden
	var pts := []
	var n := ceili(T.L / 0.5)
	for i in n + 1:
		var s := i * 0.5
		var u: float = s / T.L
		pts.append({"x": x, "y": y, "th": th, "w": T.W * pow(1.0 - u, 0.75) + 0.45, "u": u, "s": s})
		th += 0.5 * (writhe * sin((s / T.lam) * TAU - T.om * t + T.ph) + T.curl * hook * Px.smooth(0.58, 1.0, u))
		x += cos(th) * 0.5
		y += sin(th) * 0.5
	return pts


# a tentacle in cross-sections: a dark body with a lighter half toward the light, then the rims: bright where it
# faces the light (white where it faces it squarely), violet on the side the pool lights, suckers inside the hook
static func tentacle(p: Px.Painter, T: Dictionary, pts: Array, C: Array, t: float) -> void:
	var surf: float = T.y
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
	# a pulse of light runs up it as it lashes, then slower ones while it writhes
	var pulse: float = (t - T.t0) * 150.0
	var slow: float = fmod((t - T.t0) * 55.0, T.L * 1.8) - 4.0
	for q: Dictionary in pts:
		if q.y > surf:
			continue
		var nx := -sin(q.th)
		var ny := cos(q.th)
		var f := nx * LX + ny * LY
		var ks := 1.0 if f >= 0.0 else -1.0
		var lit: float = ks * q.w
		var x0: float = q.x + nx * lit
		var y0: float = q.y + ny * lit
		var x1: float = q.x - nx * lit
		var y1: float = q.y - ny * lit
		if y1 <= surf:
			p.px(x1, y1, C[3])
		if y0 <= surf:
			p.px(x0, y0, C[7] if (absf(f) > 0.8 and q.u > 0.15) else (C[6] if q.u > 0.85 else (C[6] if absf(f) > 0.3 else C[5])))
		if q.u > 0.62 and q.u < 0.93 and fmod(q.s, 3.0) < 0.5:
			p.px(q.x + nx * T.curl * q.w * 0.45, q.y + ny * T.curl * q.w * 0.45, C[4])
		var dp := minf(absf(q.s - pulse), absf(q.s - slow) * 1.6)
		if dp < 2.5:
			p.px(q.x, q.y, C[7] if dp < 1.0 else C[5])
	# the tip catches the light, and light runs along it
	var tip: Dictionary = pts[pts.size() - 1]
	if tip.y <= surf:
		p.px(tip.x, tip.y, WHITE)
		p.glow(tip.x, tip.y, 6.0, C[6], 0.25)
	var i := 0
	while i < pts.size():
		if pts[i].y < surf:
			p.glow(pts[i].x, pts[i].y, 9.0, C[4], 0.1)
		i += 8
	var pq: Dictionary = pts[mini(pts.size() - 1, maxi(0, Px.roundi(pulse * 2.0)))]
	if pulse < T.L and pq.y < surf:
		p.glow(pq.x, pq.y, 10.0, C[6], 0.45)
	# where it breaks the surface: a lit collar of ink
	var base: Variant = null
	for q: Dictionary in pts:
		if q.y <= surf:
			base = q
			break
	if base:
		var w: float = base.w + 1.5
		p.line(base.x - w, surf, base.x + w, surf, C[5])
		p.px(base.x - w - 1.0, surf + 0.5, C[3])
		p.px(base.x + w + 1.0, surf + 0.5, C[3])


static func rx(tt: float) -> float:
	return RX * Px.Ease.outCubic(Px.clamp(tt / OPEN)) * (1.0 - Px.Ease.inCubic(Px.clamp((tt - SHUT) / 0.45)))


static func inPool(x: float, tt: float) -> bool:
	return absf(x) < rx(tt) * 0.95


var C: Array
var R: Px.Rng
var DIM: Array
var ps: Px.Particles
var puffs: Lib.Puffs
var ripples: Array = []
var splats: Array = []
var lights: Array = []
var t := 0.0
var acc := 0.0
var drops: Lib.Drops
var tents: Array


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	DIM = [C[0], C[0], C[1], C[1], C[3], C[4], C[5], C[6]]
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]], "haze": C[4]})
	puffs = Lib.Puffs.new({"rng": R, "flame": [C[7], C[6], C[5], C[4], C[3], C[2], C[1], C[1], C[0]], "soot": [Px.mix(C[3], C[2], 0.55), Px.mix(C[2], C[1], 0.5)], "cap": Px.mix(C[4], C[2], 0.5), "rim": [C[6], C[5], C[4]], "floor": floor_})
	ripples = []
	splats = []
	lights = []
	t = 0.0
	acc = 0.0
	drops = Lib.Drops.new({
		"onLand": func(x, y, v, s):
			if inPool(x, t):
				ripples.append({"x": x, "t0": t, "life": 0.5, "w": 0.6})
			else:
				splats.append({"x": x, "t0": t, "s": s}),
	})
	# seven tentacles in two rows: the back row taller and dimmer, hooks mostly curling inward
	var rows := [[-22.0, -2.5], [-8.0, -3.0], [7.0, -3.0], [21.0, -2.5], [-28.0, 2.5], [-1.0, 3.0], [27.0, 2.5]]
	var order := [3, 0, 5, 2, 4, 1, 6]
	var last := [1, 5, 0, 6, 3, 2, 4]
	tents = []
	for i in rows.size():
		var x: float = rows[i][0]
		var y: float = rows[i][1]
		var back := y < 0.0
		var sg := Px.sign(x)
		var sx := sg if sg else 1.0
		tents.append({
			"x": x + R.range(-3.0, 3.0), "y": y, "back": back,
			"L": R.range(46.0, 62.0) if back else R.range(32.0, 46.0), "W": R.range(3.2, 4.0) if back else R.range(3.8, 4.6),
			"lean": sx * (0.06 + absf(x) / 120.0) + R.range(-0.06, 0.06), "curl": -sx if R.chance(0.75) else sx,
			"lam": R.range(36.0, 50.0), "om": R.range(4.5, 7.0) * R.sign(), "ph": R.range(0.0, TAU), "A": R.range(0.06, 0.085), "H": R.range(0.15, 0.32),
			"t0": 0.3 + order[i] * 0.045 + R.range(0.0, 0.03), "t1": 1.5 + last[i] * 0.1 + R.range(0.0, 0.05),
			"whip": {"t": R.range(0.9, 1.5), "a": R.range(0.28, 0.45) * R.sign()} if R.chance(0.45) else null,
			"up": false, "down": false,
		})


func splash(x: float, y: float, n: int, power: float) -> void:
	for i in n:
		drops.add(x + R.range(-2.0, 2.0), y - 1.0, R.range(-70.0, 70.0) * power, -R.range(90.0, 230.0) * power, 2.0 if R.chance(0.4) else 1.0)
	ripples.append({"x": x, "t0": t, "life": 0.7, "w": 1.0})
	lights.append({"x": x, "y": y - 7.0, "r": 30.0, "k": 0.6 * power, "life": 0.25, "max": 0.25})


func update(dt: float) -> void:
	t += dt
	for T: Dictionary in tents:
		if not T.up and t >= T.t0:
			T.up = true
			splash(T.x, T.y, 12, 1.0)
			for i in 4:
				ps.spawn(P.SPARK, T.x, T.y - 2.0, R.range(-80.0, 80.0), -R.range(120.0, 260.0), R.range(0.2, 0.45))
		if not T.down and t >= T.t1 + SINK * 0.8:
			T.down = true
			splash(T.x, T.y, 6, 0.6)
		# glints run over the rims while they stand
		if t > T.t0 + 0.2 and t < T.t1 and R.chance(dt * 1.6):
			var pts: Variant = spine(T, t)
			var q: Variant = pts[floori(R.range(0.3, 0.95) * pts.size())] if pts else null
			if q and q.y < T.y:
				ps.spawn(P.STAR, q.x - sin(q.th) * q.w, q.y + cos(q.th) * q.w, 0.0, -4.0, R.range(0.25, 0.5), C[6], R.range(1.0, 2.2))
	# the pool breathes out wisps and motes while it's open
	var r := rx(t)
	if r > 8.0 and t < SHUT - 0.4:
		acc += dt * 9.0
		while acc > 1.0:
			puffs.spawn(PK.SOOT, R.range(-0.8, 0.8) * r, -R.range(1.0, 4.0), R.range(-8.0, 8.0), -R.range(14.0, 30.0), R.range(0.6, 0.85), R.range(3.0, 6.0))
			acc -= 1.0
		if R.chance(dt * 16.0):
			ps.spawn(P.MOTE, R.range(-0.8, 0.8) * r, -2.0, R.range(-8.0, 8.0), -R.range(30.0, 80.0), R.range(0.5, 1.0), R.pick([C[7], C[6], C[6], C[5]]), R.range(0.6, 1.1))
		if R.chance(dt * 5.0):
			ps.spawn(P.EMBER, R.range(-0.8, 0.8) * r, -3.0, R.range(-10.0, 10.0), -R.range(20.0, 45.0), R.range(0.6, 1.0), C[6])
		if R.chance(dt * 3.0):
			ripples.append({"x": R.range(-0.7, 0.7) * r, "t0": t, "life": 0.6, "w": 0.5})
		# a violet haze hangs over the pool, lit from inside
		if R.chance(dt * 7.0):
			ps.spawn(P.VAPOUR, R.range(-0.7, 0.7) * r, -R.range(2.0, 8.0), R.range(-6.0, 6.0), -R.range(10.0, 22.0), R.range(0.6, 0.9), C[3] if R.chance(0.5) else C[4], R.range(3.0, 6.0))
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
		p.glow(0.0, -16.0, 86.0, C[4], 0.22 * k)
		p.glow(0.0, -8.0, r * 1.7 + 12.0, C[4], 0.32 * k * (0.9 + 0.1 * sin(t * 5.0)))
		p.glow(0.0, 0.0, r * 1.15, C[5], 0.18 * k)
	puffs.draw(p, PK.SOOT, {"x": 0.0, "y": 6.0, "k": k, "reach": 70.0})
	ps.draw(p, "back")
	for T: Dictionary in tents:
		if T.back:
			var pts: Variant = spine(T, t)
			if pts:
				tentacle(p, T, pts, DIM, t)


func draw(p: Px.Painter) -> void:
	for T: Dictionary in tents:
		if not T.back:
			var pts: Variant = spine(T, t)
			if pts:
				tentacle(p, T, pts, C, t)
	drops.draw(p, C[1], C[5])
	for s: Dictionary in splats:
		var a: float = 1.0 - (t - s.t0) / 0.6
		p.dot(s.x, -0.5, C[1], a * 1.5)
		p.dot(s.x + 1.0, -0.5, C[2], a)
		if s.s > 1.0:
			p.dot(s.x - 1.0, -0.5, C[2], a)
		p.dot(s.x, -1.5, C[5], a)
	ps.draw(p, "front")
	for l: Dictionary in lights:
		var q: float = l.life / l.max
		p.glow(l.x, l.y, l.r * (0.6 + 0.4 * q), C[5], l.k * q * q)
