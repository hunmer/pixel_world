# port-of: src/fx/critters/frog.js@5c116ce43223212e7dc4f6f5ccff3313435106c9
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P

static var meta := {
	"name": "Frog",
	"desc": "A frog puffs its throat, blinks, crouches and leaps to snap a buzzing fly out of the air, then lands with a squash and a puff of dust, gulps and settles.",
	"tags": ["critter", "frog", "animal", "hop", "ground", "loop"],
	"size": [112, 88],
	"origin": [56, 80],
	"duration": 2.6,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#0a160c", "#173a18", "#256024", "#3a8a2e", "#62b440", "#a8e070", "#e8ffc0"],
		"belly": ["#5e5a24", "#bdb45a", "#efe9a8"],
		"seed": 1,
	},
}

static var D: float = meta.duration
static var GRID := Lib.Grid.new(-22, -40, 44, 44)
static var SWARM := Lib.Swarm.new()
const T_CROUCH := 0.95
const T_UP := 1.2
const T_LAND := 1.62
const T_SNAP := 1.4
const T_BACK := 1.95
const G := 1000.0
static var HOP := (G * (T_LAND - T_UP) ** 2) / 8.0
static var EYE := Px.ramp(["#3a2a08", "#c89420", "#ffd860"])
static var TONGUE := Px.hex("#e8607a")
static var FLY := Px.hex("#141018")
static var WINGS := Px.hex("#c8d0e0")
static var DUST := Px.hex("#8a7f92")


# the pose at loop time t: lift off the floor, nose tilt, squash, hind legs out, throat puffed, eye shut
static func pose(t: float) -> Dictionary:
	var by := 0.0
	var rot := 0.0
	var sq := 0.0
	var leg := 0.0
	var throat := 0.0
	var shut := 0.0
	var age := Px.wrap(t - T_LAND, D)
	for q in [[0.05, 0.45], [0.5, 0.85], [1.75, 1.95]]:
		var a: float = q[0]
		var b: float = q[1]
		if t > a and t < b:
			throat = sin(PI * ((t - a) / (b - a))) ** 0.7 * (0.6 if a > 1.0 else 1.0)
	if t > 0.88 and t < 0.95:
		shut = 1.0
	if t >= T_CROUCH and t < T_UP:
		var u := Px.Ease.inOutSine(Px.seg(t, T_CROUCH, T_UP))
		sq = -0.18 * u
		rot = -0.12 * u
	elif t >= T_UP and t < T_LAND:
		var q := (t - T_UP) / (T_LAND - T_UP)
		by = -HOP * 4.0 * q * (1.0 - q)
		rot = Px.lerp(0.42, -0.25, q)
		sq = Px.lerp(0.18, 0.02, minf(1.0, q * 2.0))
		leg = 1.0 if q < 0.75 else 1.0 - (q - 0.75) / 0.25
	else:
		sq = -0.24 * Lib.spring(age, 2.4, 6.5)
		rot = -0.08 * exp(-age * 6.0)
	return {"by": by, "rot": rot, "sq": sq, "leg": leg, "throat": throat, "shut": shut, "air": t >= T_UP and t < T_LAND}


# the fly: buzzing a little loop over the frog, snapped up at T_SNAP, buzzing back in from the side at T_BACK
static func fly(t: float) -> Variant:
	if t > T_SNAP and t < T_BACK:
		return null
	var a := (t / D) * TAU * 3.0
	var home := [16.0 + 6.0 * sin(a), -40.0 + 3.0 * sin(2.0 * a)]
	var inn := Px.wrap(t - T_BACK, D)
	if inn < 0.45:
		var u := Px.Ease.outCubic(inn / 0.45)
		return [Px.lerp(-52.0, home[0], u), Px.lerp(-46.0, home[1], u) + sin(inn * 30.0) * 1.5]
	return home


static func frog(g: Lib.Grid, C: Array, Bl: Array, Pz: Dictionary, t: float) -> void:
	g.clear()
	var cs := cos(Pz.rot)
	var sn := sin(Pz.rot)
	var sx: float = 1.0 + Pz.sq * -0.6
	var sy: float = 1.0 + Pz.sq
	# into the frog's own frame: centred on its body, turned with it, squashed with it
	var local := func(x: float, y: float) -> Array:
		var dx := x
		var dy := y + 7.0
		return [(dx * cs + dy * sn) / sx, (-dx * sn + dy * cs) / sy - 7.0]
	var inBody := func(x: float, y: float) -> bool:
		return ((x + 1.0) / 10.5) ** 2 + ((y + 7.0) / 6.0) ** 2 <= 1.0 or ((x - 6.0) / 6.2) ** 2 + ((y + 8.6) / 4.8) ** 2 <= 1.0
	var inEye := func(x: float, y: float) -> bool:
		return (x - 5.5) ** 2 + (y + 13.2) ** 2 <= 3.2 ** 2
	# the body and head: lit on top, a pale belly, dark spots on the back
	var lit := func(x: float, y: float, k: float) -> bool:
		return inBody.call(-4.0 + (x + 4.0) / k, -13.0 + (y + 13.0) / k)
	g.shade(-15.0, -22.0, 15.0, 1.0, func(x, y):
		var uv: Array = local.call(x, y)
		var u: float = uv[0]
		var v: float = uv[1]
		if not inBody.call(u, v) and not inEye.call(u, v):
			return 0
		if inEye.call(u, v):
			var d := Px.hypot(u - 5.5, v - 13.2 * -1.0)
			if Pz.shut:
				return C[4] if v < -13.2 else C[3]
			if absf(v + 13.0) < 0.7 and absf(u - 6.0) < 1.8:
				return C[0]
			if u < 4.7 and v < -14.0:
				return EYE[2]
			return EYE[1] if d < 2.4 else EYE[0]
		if v > -5.0 and u > -6.0:
			return Bl[1] if v > -3.0 else Bl[2]
		for q in [[-5.0, -10.0, 1.6], [0.0, -11.5, 1.3], [-8.0, -7.0, 1.2], [3.0, -12.5, 0.9]]:
			var px: float = q[0]
			var py: float = q[1]
			var r: float = q[2]
			if Px.hypot(u - px, v - py) < r:
				return C[2]
		if not inBody.call(u + 2.0, v + 2.4):
			return C[2]
		return C[5] if lit.call(u, v, 0.5) else (C[4] if lit.call(u, v, 0.8) else C[3]))
	# hind leg: a thigh folded at the rump, or kicked out straight when it leaps
	var legs := []
	if Pz.leg < 0.5:
		g.ellipse(-7.5, -4.5 + (1.0 - sy) * 3.0, 5.0, 3.6, func(nx, ny): return C[4] if nx * -0.6 + ny * -0.8 > 0.35 else (C[2] if ny > 0.4 else C[3]))
		legs.append([[-4.0, -1.5], [-9.0, -1.0], [-3.0, -0.5], [4.0, -0.5]])
	else:
		var ex: float = -8.0 - 10.0 * Pz.leg
		var ey: float = 4.0 + 6.0 * Pz.leg
		legs.append([[-6.0, -5.0], [-10.0, 0.0], [ex, ey], [ex - 5.0, ey + 2.0]])
	for L: Array in legs:
		# a tapering tube: a thick thigh, a thinner shin, a long foot; lit along its top
		g.tube(L, func(u): return Px.lerp(2.0, 0.7, u), func(u, v): return C[2] if v > 0.55 else (C[3] if u > 0.66 else C[4]))
		# webbed toes spread at the end of the foot
		var fx: float = L[L.size() - 1][0]
		var fy: float = L[L.size() - 1][1]
		var px: float = L[L.size() - 2][0]
		var py: float = L[L.size() - 2][1]
		var dx := fx - px
		var dy := fy - py
		var l := Px.hypot(dx, dy)
		if not l:
			l = 1.0
		for k in [-1.0, 0.0, 1.0]:
			g.line(fx, fy, fx + (dx / l) * 2.0 - (dy / l) * k * 1.6, fy + (dy / l) * 2.0 + (dx / l) * k * 1.6, C[3])
	# glint in the eye, the mouth line
	if not Pz.shut:
		var gx := 4.6
		var gy := -14.4
		var X := gx * cs - (gy + 7.0) * sn * 1.0
		var Y := gx * sn + (gy + 7.0) * cs - 7.0
		g.setc(X, Y, C[6])
	for u in range(3, 12):
		var v := -7.8 + (u - 3) * 0.05
		var X := (u * sx) * cs - ((v + 7.0) * sy) * sn
		var Y := (u * sx) * sn + ((v + 7.0) * sy) * cs - 7.0
		g.setc(X, Y, C[1])
	# the front leg props it up, or tucks in when it leaps
	var fl: Array = [[7.0, -4.0], [9.0, -1.0]] if Pz.air else [[7.0, -4.0], [8.0, -0.5]]
	g.line(fl[0][0], fl[0][1], fl[1][0], fl[1][1], C[3])
	g.setc(fl[1][0] + 1.0, fl[1][1], C[3])
	g.setc(fl[1][0] - 1.0, fl[1][1], C[3])
	# the throat sac swells into a glossy bubble under the chin
	if Pz.throat > 0.05:
		var r: float = 0.8 + 2.8 * Pz.throat
		var cx := 7.0
		var cy := -5.2 + r * 0.25
		g.ellipse(cx, cy, r * 1.1, r, func(nx, ny): return Bl[2] if nx * -0.6 + ny * -0.8 > 0.55 else (Bl[1] if ny > 0.5 else Px.mix(Bl[2], C[5], 0.4)), 0.9)
		g.setc(cx - r * 0.4, cy - r * 0.45, C[6])
	g.outline(C[0])


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var Bl := Px.fit(o.belly, 3)
	var Pz := pose(t)
	var g := GRID
	frog(g, C, Bl, Pz, t)
	g.draw(p, 1.0, 0.0, Px.round(Pz.by))
	# the tongue whips out to the fly and back
	var ts := (t - T_SNAP + 0.06) / 0.14
	if ts > 0.0 and ts < 1.0:
		var f: Array = fly(T_SNAP - 0.001)
		var e := sin(PI * ts)
		var mx := 11.0
		var my: float = Pz.by - 8.0
		var x1 := Px.lerp(mx, f[0], e)
		var y1 := Px.lerp(my, f[1], e)
		p.line(mx, my, x1, y1, TONGUE)
		p.line(mx, my + 1.0, x1, y1 + 1.0, Px.mix(TONGUE, C[0], 0.4))
		p.circle(x1, y1, 1.4, TONGUE)
	# the fly, buzzing
	var f: Variant = fly(t)
	if f:
		var flap := sin(t * 90.0) > 0.0
		p.px(f[0], f[1], FLY)
		p.px(f[0] + 1.0, f[1], FLY)
		p.dot(f[0], f[1] - (1.0 if flap else 0.0), WINGS, 0.8)
		p.dot(f[0] + 1.0, f[1] - (0.0 if flap else 1.0), WINGS, 0.8)
		p.glow(f[0], f[1], 3.0, WINGS, 0.15)
	# dust thrown out along the floor as it takes off and lands, and grit bouncing
	var sw: Lib.Swarm = SWARM.begin(t)
	for q in [[T_UP, 7, 0.6], [T_LAND, 18, 1.0]]:
		var t0: float = q[0]
		var n: int = q[1]
		var pw: float = q[2]
		var age := Px.wrap(t - t0, D)
		for i in n:
			var r := Px.rng(o.seed, i, t0 * 100.0)
			var L := r.range(0.6, 1.1) * pw
			if age > L:
				continue
			var s := r.sign()
			var v := r.range(24.0, 70.0) * pw
			var x := s * (7.0 + (v / 3.5) * (1.0 - exp(-age * 3.5)))
			var y := -1.5 - r.range(1.0, 5.0) * age
			sw.add(P.SMOKE, x, y, 0.0, 0.0, age, L, DUST, r.range(2.2, 4.2) * (0.65 + 0.35 * pw), 2)
		if pw == 1.0:
			for i in 8:
				var r := Px.rng(o.seed, i, 909)
				var b := Lib.toss(r.range(-8.0, 8.0), -1.0, r.range(-40.0, 40.0), -r.range(30.0, 70.0), age, 700.0, -0.5)
				if age < 0.7:
					p.dot(b.x, b.y, Px.hex("#6a6074") if i % 2 else Px.hex("#9a90a4"), 1.4 - age * 2.0 if b.landed else 1.0)
	sw.draw(p)


static func drawBack(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var Pz := pose(t)
	var hgt := Px.clamp(-Pz.by / HOP)
	Lib.shadow(p, 0.0, -0.2, 13.0 * (1.0 - 0.35 * hgt), 1.6, C[0], 0.6 - 0.3 * hgt)
