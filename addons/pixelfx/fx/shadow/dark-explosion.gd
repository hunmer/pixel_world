# The pull that swirls motes into the core and the collapse burst are adapted from Sprite Fusion's open-source
# black-hole (https://www.spritefusion.com/pixel-art-vfx/black-hole), the sparks, rings and smoke from his explosion,
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/shadow/dark-explosion.js@0a088c0633e271d5a02a231c7ab61a0b6cf4a0b0
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const PK := Lib.PK
const WHITE := Px.WHITE

static var meta := {
	"name": "Dark explosion",
	"desc": "Motes swirl into a pulsing core, a black star cuts across a violet-white flash, and a black sphere burns at the rim, throws lit shards and smoke, then collapses.",
	"tags": ["shadow", "explosion", "void", "dark", "magic", "impact", "one-shot"],
	"size": [280, 248],
	"origin": [140, 206],
	"duration": 3.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOID, "seed": 6},
}

# the heart of the blast hangs above the floor; the sphere's radius; the beats of the choreography
const Y := -54.0
const RS := 16.0
const REL := 0.52
const BURN := 1.62
const POP := 1.84
static var SMOKE := Px.hex("#5d5468")


# a black sphere: a void body (a faint crescent of reflected light low on the right, a dull glint high on the
# left), a white rim, and pointed tongues of violet flame that lean up, flicker and crawl round it
static func sphere(p: Px.Painter, C: Array, r: float, t: float, heat: float) -> void:
	if r < 0.6:
		return
	var E := r + 12.0 * heat + 2.0
	p.shade(-E, Y - E, E, Y + E, func(x, y, out):
		var dx: float = x
		var dy: float = y - Y
		var d := sqrt(dx * dx + dy * dy)
		if d > E:
			return null
		if d < r - 0.5:
			var e0 := r - d
			var ang0 := atan2(dy, dx)
			if e0 < 1.4 and cos(ang0 - 0.8) > 0.55:
				return C[2]
			if r > 8.0 and pow(dx + r * 0.45, 2.0) + pow(dy + r * 0.45, 2.0) < 1.6:
				return C[3]
			return C[0]
		var e := d - (r - 0.5)
		if e < 1.0:
			out.c = WHITE if sin(atan2(dy, dx) * 7.0 + t * 9.0) > -0.6 else C[7]
			out.k = 0.4
			return null
		# the further out, the lower the angle it's sampled at: tongues bend upward like flame
		var ang := atan2(dy + e * 0.6, dx)
		var top := maxf(0.0, -sin(ang))
		var a1 := ang - t * 0.9
		var a2 := ang + t * 1.7
		var i1 := Px.round((a1 * 9.0) / TAU)
		var i2 := Px.round((a2 * 15.0) / TAU)
		var T1 := pow(0.5 + 0.5 * cos(a1 * 9.0), 3.0) * (0.55 + 0.45 * Px.noise(t * 7.0 + i1 * 3.7, 1))
		var T2 := pow(0.5 + 0.5 * cos(a2 * 15.0), 4.0) * (0.5 + 0.5 * Px.noise(t * 11.0 + i2 * 5.1, 2))
		var h := heat * (0.3 + 0.95 * top) * (1.5 + 12.0 * maxf(0.0, T1) + 6.0 * maxf(0.0, T2))
		if e > h + 1.0:
			return null
		var u := (e - 1.0) / h
		out.c = WHITE if u < 0.18 else (C[7] if u < 0.4 else (C[6] if u < 0.62 else (C[5] if u < 0.84 else C[4])))
		out.a = 1.0 if u < 0.8 else (1.0 - u) * 5.0
		if u < 0.6 and ((floori(x) + floori(y)) & 1) == 0:
			out.k = 0.25 * (1.0 - u)
		return null)


static func coreR(tt: float) -> float:
	return 1.5 + 5.0 * Px.Ease.inQuad(tt / REL) if tt < REL - 0.07 else 1.0


static func sphereR(tt: float) -> float:
	if tt < REL:
		return 0.0
	if tt < BURN:
		return RS * Px.Ease.outBack(Px.clamp((tt - REL) / 0.14), 2.4) * (1.0 + 0.06 * Px.smooth(REL + 0.3, BURN, tt) + 0.02 * sin(tt * 11.0))
	if tt < POP:
		return RS * 1.08 * (1.0 - Px.Ease.inQuad((tt - BURN) / (POP - BURN)))
	return 0.0


static func starL(tt: float) -> float:
	return 0.0 if (tt < REL or tt > REL + 0.26) else 60.0 * (1.0 - Px.Ease.inQuad(Px.clamp((tt - REL - 0.05) / 0.21)))


static func starRot(tt: float) -> float:
	return 0.32 + (tt - REL) * 2.2


# how hard the sphere lights what's round it: the rims of the smoke, the edges of the shards
static func burning(tt: float) -> float:
	return Px.clamp(tt / REL) * 0.7 if tt < REL else (1.0 if tt < BURN else (1.2 if tt < POP else maxf(0.0, 1.0 - (tt - POP) / 0.35)))


static func rim(a: float, r: float) -> Array:
	return [cos(a) * r, Y + sin(a) * r]


var C: Array
var R: Px.Rng
var ps: Px.Particles
var embers: Px.Particles
var puffs: Lib.Puffs
var bits: Px.Bits
var lights: Array = []
var rings: Array = []
var t := 0.0
var released := false
var collapsing := false
var popped := false
var acc := 0.0
var dustAcc := 0.0
var flick := 1.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [WHITE, C[7], C[6], C[5]]})
	embers = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]]})
	puffs = Lib.Puffs.new({
		"rng": R,
		"flame": [WHITE, C[7], C[6], C[5], C[5], C[4], C[4], C[3], C[2]],
		"soot": [Px.mix(Px.mix(C[3], C[1], 0.3), SMOKE, 0.45), Px.mix(C[1], SMOKE, 0.3)],
		"cap": Px.mix(Px.mix(C[4], C[2], 0.5), SMOKE, 0.4),
		"rim": [C[6], C[5], C[4]],
		"floor": floor_,
	})
	bits = Px.Bits.new({"ground": floor_})
	lights = []
	rings = []
	t = 0.0
	released = false
	collapsing = false
	popped = false
	acc = 0.0
	dustAcc = 0.0
	flick = 1.0


func light(x: float, y: float, r: float, c: Variant, k: float, life: float) -> void:
	lights.append({"x": x, "y": y, "r": r, "c": c, "k": k, "life": life, "max": life})


func release() -> void:
	light(0.0, Y, 100.0, C[4], 1.25, 0.85)
	light(0.0, Y, 86.0, Px.mix(C[6], WHITE, 0.5), 1.3, 0.22)
	rings.append({"r0": RS, "r1": 104.0, "life": 0.46, "max": 0.46, "th": 3.6, "hot": true, "delay": 0.0})
	rings.append({"r0": RS * 0.8, "r1": 62.0, "life": 0.3, "max": 0.3, "th": 1.6, "hot": true, "delay": 0.02})
	rings.append({"r0": RS, "r1": 124.0, "life": 0.62, "max": 0.62, "th": 1.2, "hot": false, "delay": 0.07})
	# shards of the void: big slivers tumbling out and raining onto the floor, fine splinters faster
	for i in 34:
		var big := i < 20
		var a := R.range(0.0, TAU)
		var xy := rim(a, RS * 0.7)
		var sp := R.range(80.0, 170.0) if big else R.range(130.0, 220.0)
		bits.add({"kind": B.SHARD, "x": xy[0], "y": xy[1], "vx": cos(a) * sp, "vy": sin(a) * sp - R.range(40.0, 110.0), "g": 0.75, "drag": 1.3 if big else 1.7, "bounce": 0.35, "life": R.range(1.6, 2.6), "a": R.range(0.0, TAU), "va": R.range(-16.0, 16.0), "s": R.range(6.0, 11.0) if big else R.range(3.0, 4.5)})
	for i in 84:
		var a := R.range(0.0, TAU)
		var xy := rim(a, RS * 0.8)
		var sp := R.range(120.0, 235.0)
		ps.spawn(P.SPARK, xy[0], xy[1], cos(a) * sp, sin(a) * sp - 50.0, R.range(0.2, 0.7))
	for i in 28:
		var a := R.range(0.0, TAU)
		var xy := rim(a, RS * 0.9)
		var sp := R.range(30.0, 130.0)
		embers.spawn(P.EMBER, xy[0], xy[1], cos(a) * sp, sin(a) * sp - 40.0, R.range(1.3, 2.5))
	for i in 24:
		var a := R.range(0.0, TAU)
		var xy := rim(a, RS * 0.9)
		var sp := R.range(15.0, 70.0)
		puffs.spawn(PK.SOOT, xy[0], xy[1], cos(a) * sp, sin(a) * sp * 0.8 - 14.0, R.range(2.0, 2.8), R.range(7.0, 12.0), R.range(0.02, 0.3))
	# the shock flattens on the floor and shoves smoke out along it
	for i in 12:
		var s := 1.0 if i % 2 else -1.0
		puffs.spawn(PK.SOOT, s * R.range(10.0, 40.0), -R.range(2.0, 5.0), s * R.range(50.0, 120.0), -R.range(0.0, 10.0), R.range(1.6, 2.4), R.range(5.0, 9.0), R.range(0.08, 0.2))
	for i in 10:
		var a := -PI / 2.0 + R.range(-1.6, 1.6)
		var xy := rim(a, RS)
		var sp := R.range(30.0, 80.0)
		puffs.spawn(PK.FLAME, xy[0], xy[1], cos(a) * sp, sin(a) * sp - 30.0, R.range(0.3, 0.6), R.range(2.0, 3.6), 0.0, R.chance(0.5))
	# what was still falling in is swallowed by the blast
	ps.list.clear()
	puffs.list = puffs.list.filter(func(q): return q.delay > 0.0)


func pop() -> void:
	light(0.0, Y, 56.0, WHITE, 0.9, 0.18)
	light(0.0, Y, 120.0, C[5], 0.8, 0.5)
	rings.append({"r0": 2.0, "r1": 40.0, "life": 0.28, "max": 0.28, "th": 2.0, "hot": true, "delay": 0.0})
	for i in 26:
		var a := R.range(0.0, TAU)
		var sp := R.range(120.0, 250.0)
		ps.spawn(P.SPARK, 0.0, Y, cos(a) * sp, sin(a) * sp - 40.0, R.range(0.2, 0.6))
	for i in 14:
		var a := R.range(0.0, TAU)
		var sp := R.range(20.0, 90.0)
		embers.spawn(P.EMBER, 0.0, Y, cos(a) * sp, sin(a) * sp - 30.0, R.range(0.9, 1.6))
	for i in 10:
		var a := R.range(0.0, TAU)
		var sp := R.range(20.0, 70.0)
		puffs.spawn(PK.SOOT, cos(a) * 3.0, Y + sin(a) * 3.0, cos(a) * sp, sin(a) * sp - 15.0, R.range(1.1, 1.7), R.range(3.0, 6.0), R.range(0.0, 0.08))

	for q: Dictionary in embers.list + puffs.list:
		var dx: float = q.x
		var dy: float = q.y - Y
		var d := Px.hypot(dx, dy)
		if not d:
			d = 1.0
		var f := 90.0 * maxf(0.0, 1.0 - d / 70.0)
		q.vx += (dx / d) * f
		q.vy += (dy / d) * f - f * 0.3
	# what's left of it climbs away as a column of smoke
	for i in 12:
		puffs.spawn(PK.SOOT, R.range(-6.0, 6.0), Y + R.range(-4.0, 6.0), R.range(-10.0, 10.0), -R.range(20.0, 55.0), R.range(1.3, 1.8), R.range(7.0, 12.0), R.range(0.02, 0.2))


func update(dt: float) -> void:
	t += dt
	flick = 0.88 + 0.12 * sin(t * 37.0) * sin(t * 23.0)
	# the charge: motes swirl in from all round, streaks shoot straight at the core, darkness gathers
	if t < REL - 0.06:
		var k := t / REL
		acc += dt * (90.0 + 150.0 * k)
		while acc > 1.0:
			var a := R.range(0.0, TAU)
			var D := R.range(36.0, 84.0)
			var x := cos(a) * D
			var y := minf(-3.0, Y + sin(a) * D)
			var vt := R.range(50.0, 110.0)
			var vi := R.range(10.0, 40.0)
			ps.spawn(P.MOTE, x, y, -sin(a) * vt - cos(a) * vi, cos(a) * vt - sin(a) * vi, 0.9, R.pick([WHITE, C[6], C[6], C[5]]), R.range(0.7, 1.2))
			acc -= 1.0
		if R.chance(0.75):
			var a := R.range(0.0, TAU)
			var D := R.range(28.0, 70.0)
			var T := R.range(0.18, 0.28)
			var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
			ps.spawn(P.STREAK, cos(a) * D, Y + sin(a) * D, -cos(a) * v, -sin(a) * v, T, C[7] if R.chance(0.5) else C[6])
		if t < REL - 0.2 and R.chance(0.16):
			var a := R.range(0.0, TAU)
			var D := R.range(34.0, 60.0)
			puffs.spawn(PK.SOOT, cos(a) * D, Y + sin(a) * D, -sin(a) * 40.0, cos(a) * 40.0, R.range(0.6, 0.9), R.range(3.0, 6.0))
		Lib.attract(ps.list, 0.0, Y, 2.2e6 * (0.3 + k), 110.0, 0.55, 2.5, dt, func(q): return 1.0 if q.k == P.MOTE else 0.0, 420.0)
		Lib.attract(puffs.list, 0.0, Y, 1.2e6 * (0.3 + k), 90.0, 0.7, 4.0, dt, func(): return 1.0, 160.0)
	if t >= REL and not released:
		released = true
		release()
	# the sphere burns: flame licks off its rim, the odd spark and ember
	if released and t < BURN:
		var sr := sphereR(t)
		acc += dt * 34.0
		while acc > 1.0:
			var a := -PI / 2.0 + R.gauss() * 1.1
			var xy := rim(a, sr + 1.0)
			var sp := R.range(10.0, 35.0)
			puffs.spawn(PK.FLAME, xy[0], xy[1], cos(a) * sp, sin(a) * sp - R.range(10.0, 30.0), R.range(0.25, 0.45), R.range(1.2, 2.2), 0.0, R.chance(0.2))
			acc -= 1.0
		if R.chance(dt * 10.0):
			var a := -PI / 2.0 + R.range(-1.4, 1.4)
			var xy := rim(a, sr * 0.9)
			puffs.spawn(PK.SOOT, xy[0], xy[1], cos(a) * 20.0, -R.range(15.0, 35.0), R.range(1.2, 1.7), R.range(5.0, 9.0))
		if R.chance(dt * 8.0):
			var a := R.range(0.0, TAU)
			var xy := rim(a, sr)
			var sp := R.range(110.0, 200.0)
			ps.spawn(P.SPARK, xy[0], xy[1], cos(a) * sp, sin(a) * sp - 40.0, R.range(0.2, 0.5))
		if R.chance(dt * 7.0):
			var a := -PI / 2.0 + R.range(-1.2, 1.2)
			var xy := rim(a, sr)
			embers.spawn(P.EMBER, xy[0], xy[1], cos(a) * 30.0, -R.range(20.0, 50.0), R.range(0.9, 1.6))
	# the collapse: the sphere draws its own flame back in, streaks race to the heart
	if t >= BURN and not collapsing:
		collapsing = true
		for i in 14:
			var a := R.range(0.0, TAU)
			var D := R.range(26.0, 48.0)
			var T := R.range(0.14, 0.2)
			var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
			ps.spawn(P.STREAK, cos(a) * D, Y + sin(a) * D, -cos(a) * v, -sin(a) * v, T, WHITE if R.chance(0.5) else C[6])
	if collapsing and not popped:
		Lib.attract(puffs.list, 0.0, Y, 1.4e6, 64.0, 0.6, 3.0, dt, func(q): return 1.0 if q.k == PK.FLAME else 0.35, 200.0)
	if t >= POP and not popped:
		popped = true
		pop()
	# the shock reaches the floor: dust rolls out under the ring
	for r: Dictionary in rings:
		if r.delay > 0.0 or not r.hot or r.th < 3.0:
			continue
		var rr: float = r.r0 + (r.r1 - r.r0) * (1.0 - pow(r.life / r.max, 3.0))
		var rf := sqrt(rr * rr - Y * Y) if rr > -Y else 0.0
		if rf > 0.0:
			dustAcc += dt * 60.0
			while dustAcc > 1.0:
				var s := R.sign()
				ps.spawn(P.DUST, s * rf + R.range(-2.0, 2.0), -R.range(1.0, 3.0), s * R.range(20.0, 50.0), -R.range(4.0, 14.0), R.range(0.4, 0.8), Px.mix(C[2], C[3], R.next()), R.range(1.5, 3.0))
				dustAcc -= 1.0
	for a: Array in [lights, rings]:
		for i in range(a.size() - 1, -1, -1):
			var q: Dictionary = a[i]
			if q.get("delay", 0.0) > 0.0:
				q.delay -= dt
			else:
				q.life -= dt
				if q.life <= 0.0:
					a.remove_at(i)
	bits.update(dt)
	for b: Dictionary in bits.list:
		# a shard that comes to rest lies flat on the floor
		if b.rest and not b.get("flat", false):
			b.flat = true
			b.a = Px.round(b.a / PI) * PI + R.range(-0.2, 0.2)
			b.y = -1.0
		# and once it has lain a while, it dissolves into a wisp
		if b.life < 0.45 and not b.get("wisp", false):
			b.wisp = true
			puffs.spawn(PK.SOOT, b.x, b.y - 1.0, R.range(-4.0, 4.0), -R.range(8.0, 16.0), R.range(0.6, 0.9), R.range(1.4, 2.4))
	puffs.update(dt)
	ps.update(dt)
	embers.update(dt)


func drawBack(p: Px.Painter) -> void:
	var k := burning(t)
	for r: Dictionary in rings:
		floorRing(p, C, r, true)
	puffs.draw(p, PK.SOOT, {"x": 0.0, "y": Y, "k": k * flick, "reach": 84.0})
	ps.draw(p, "back")
	if k > 0.0:
		p.glow(0.0, -3.0, 74.0, C[4], 0.24 * minf(1.0, k) * flick)


func draw(p: Px.Painter) -> void:
	var sr := sphereR(t)
	var k := burning(t)
	var L := starL(t)
	for r: Dictionary in rings:
		floorRing(p, C, r, false)
	# the charge: a contracting ring and a black core that beats
	var cr := 0.0
	if t < REL:
		var q := t / REL
		var ring := 3.0 + 74.0 * (1.0 - Px.Ease.inQuad(q))
		var beat := 1.0 + 0.3 * exp(-(pow(t - REL * 0.5, 2.0)) / 0.0015) + 0.4 * exp(-(pow(t - REL * 0.8, 2.0)) / 0.0015)
		cr = coreR(t) * beat
		Lib.ringFast(p, 0.0, Y, ring, 1.0, C[6] if q > 0.7 else C[5], 0.2 + 0.7 * q)
		if t > REL - 0.07:
			p.circle(0.0, Y, 1.6, WHITE)
		else:
			sphere(p, C, cr, t, 0.3 + 0.3 * q)
		Lib.halo(p, 0.0, Y, cr, cr + 14.0 + 30.0 * q, C[5], (0.45 + 0.7 * q) * beat)
		p.glow(0.0, Y, 60.0 + 30.0 * q, C[4], 0.12 + 0.3 * q)
	# the release: a violet-white flash with a black star cut across it
	var fu := (t - REL) / 0.12
	if fu >= 0.0 and fu < 1.0:
		var r := 36.0 * (1.0 - 0.3 * fu)
		p.circle(0.0, Y, r + 1.5, C[5], 1.2 - fu)
		p.circle(0.0, Y, r, WHITE if fu < 0.35 else C[6], 1.1 - fu)
		if fu < 0.6:
			p.circle(0.0, Y, r * 0.62, WHITE)
	# the shock rings in the air
	for r: Dictionary in rings:
		if r.delay > 0.0:
			continue
		var q: float = r.life / r.max
		var rr: float = r.r0 + (r.r1 - r.r0) * (1.0 - q * q * q)
		var th := maxf(1.0, r.th * q + 0.4)
		var hot: bool = r.hot
		# the floor stops it: below the floor line it's the flat ring on the floor instead
		Lib.ringFast(p, 0.0, Y, rr, th, func(v): return (WHITE if v > 0.6 else (C[6] if v > 0.3 else C[5])) if hot else (C[5] if v > 0.5 else C[4]), func(v, g): return 0.0 if Y + sin(g) * rr > 0.5 else minf(1.0, q * 1.6))
		if hot:
			Lib.ringLight(p, 0.0, Y, rr, 4.0, C[5], 0.4 * q, func(x, y): return y < 0.5)
	sphere(p, C, sr, t, 1.0 if t < BURN else 1.0 + 0.5 * Px.clamp((t - BURN) / (POP - BURN)))
	# the black star, burning at the edge where its arms leave the flash
	var star: Lib.Star = Lib.blackStar(Y, L, starRot(t), 0.5, 0.4) if L > 0.0 else null
	if star:
		var age := t - REL
		var fr := 36.0 * (1.0 - 0.3 * (age / 0.12)) + 1.5 if age < 0.12 else 0.0
		var cut := maxf(fr, sr)
		star.draw(p, C[0], C[5] if age < 0.1 else C[4], func(x, y): return x * x + pow(y - Y, 2.0) < cut * cut)
	puffs.draw(p, PK.FLAME)
	for b: Dictionary in bits.list:
		Lib.shard(p, b, C, 0.0, Y, minf(1.0, k) * 0.9)
	ps.draw(p, "front")
	embers.draw(p, "front")
	# the pop as it goes: a glint and a last hard light
	var pu := (t - POP) / 0.2
	if pu >= 0.0 and pu < 1.0:
		Px.sparkle(p, 0.0, Y, 12.0 * (1.0 - pu), C[6], C[5], 0.7 * (1.0 - pu))
	# light: the blast's flare and the sphere's corona; then black takes its light back
	for l: Dictionary in lights:
		var q: float = l.life / l.max
		p.glow(l.x, l.y, l.r * (0.55 + 0.45 * q), l.c, l.k * q * q)
	if sr > 1.0:
		Lib.halo(p, 0.0, Y, sr - 0.5, sr + 16.0, C[6], 0.5 * flick * minf(1.0, k))
		p.glow(0.0, Y, sr + 54.0, C[4], 0.5 * flick * minf(1.0, k))
	# black takes its light back: the sphere and the core, then the star's own cells
	var B0 := maxf(sr, cr) + 1.0
	if B0 > 2.0:
		Lib.unlight(p, -B0, Y - B0, B0, Y + B0, func(x, y): return x * x + pow(y - Y, 2.0) < pow(maxf(sr, cr) - 0.5, 2.0))
	if star:
		star.unlight(p)


# where the shock meets the floor: its cross-section with the floor plane, a flat ring racing out
static func floorRing(p: Px.Painter, C: Array, r: Dictionary, back: bool) -> void:
	if r.delay > 0.0 or not r.hot or r.th < 3.0:
		return
	var q: float = r.life / r.max
	var rr: float = r.r0 + (r.r1 - r.r0) * (1.0 - q * q * q)
	if rr <= -Y:
		return
	var rf := sqrt(rr * rr - Y * Y)
	Px.band(p, 0.0, 0.5, rf, 0.16, maxf(1.0, 3.0 * q), minf(1.0, q * 1.5), [C[3], C[4], C[5], C[6]], func(g): return (sin(g) < 0.0) == back)
	if not back:
		for s: float in [-1.0, 1.0]:
			p.glow(s * rf, -2.0, 16.0, C[5], 0.4 * q)
