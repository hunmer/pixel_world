# port-of: src/fx/status/poisoned.js@8ea6920947faa3e5ad16305817dffdb51e6e1671
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Poisoned",
	"desc": "Sick to the bone: green rolls up the body in waves, dark veins creep from a wound, toxic sweat drips and hisses; every 0.8 s it wobbles, blisters pop and a ring pulses out.",
	"tags": ["status", "poison", "toxic", "dot", "debuff", "sick", "loop"],
	"size": [72, 64],
	"origin": [36, 54],
	"duration": 1.6,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#0e1d14", "#173320", "#23552e", "#318232", "#55b92f", "#8eea3f", "#cfff63", "#f6ffc2"], "veins": "#2c1a3a", "seed": 5},
}

static var SICK := {"turn": 0.8, "crouch": 4, "lean": 4, "hy": 1, "fx": 2, "fy": -20, "bx": 8, "by": -14, "ffx": 3, "fbx": -3}
static var act := {
	"onBody": true,
	"poses": [[0, Px.merge(SICK, {"x": -1, "crouch": 5, "lean": 5})], [0.2, Px.merge(SICK, {"x": 0})], [0.5, Px.merge(SICK, {"x": 1})], [0.8, Px.merge(SICK, {"x": 1, "crouch": 5, "lean": 5})], [1, Px.merge(SICK, {"x": 0})], [1.3, Px.merge(SICK, {"x": -1})], [1.6, Px.merge(SICK, {"x": -1, "crouch": 5, "lean": 5})]],
}

static var D: float = meta.duration
const TICK := 0.8
const G := 760.0
static func since(t: float) -> float:
	return fmod(fmod(t, TICK) + TICK, TICK)
## The effect draws the whole (sick, swaying) body, so the stand-in is hidden throughout.
static func actorAlpha(_t: float, _o: Dictionary) -> float:
	return 0.0

# worked out once per character: the veins (walks out from a wound on the forearm), blister spots, sweat spots
static var BODIES := {}
static func body(a: Dictionary, seed: float) -> Dictionary:
	var m: Variant = BODIES.get(a.mask.id)
	if not m:
		m = {}
		BODIES[a.mask.id] = m
	if m.has(seed):
		return m[seed]
	var S := Lib.shape(a)
	var H: int = S.h
	var W: int = S.w
	var on: Callable = S.on
	var R := Px.Rng.new(seed * 7.0 + 3.0)
	var lr: Array = S.rows[Px.roundi(H * 0.6)]
	var l: int = lr[0]
	var r: int = lr[1]
	var wx := r - 1
	var wy := Px.roundi(H * 0.6)
	var veins := []
	for i in 4:
		walk(S, R, veins, wx, wy, PI + (i / 4.0 - 0.45) * 2.2, 11.0, 0)
	var lum := func(x: int, y: int) -> float: return Px.luma(Lib.colorAt(a, x, y))
	var skin: Array = S.body.filter(func(xy): return lum.call(xy[0], xy[1]) > 0.55 and on.call(xy[0] - 1, xy[1]) and on.call(xy[0] + 1, xy[1]))
	var pick := func(list: Array) -> Variant: return list[floori(R.next() * list.size())]
	var blisters := []
	for _k in [0, 1]:
		var row := []
		for _j in [0, 1, 2]:
			var xy: Array = pick.call(S.body.filter(func(b): return b[1] > 4 and on.call(b[0] - 1, b[1]) and on.call(b[0] + 1, b[1]) and on.call(b[0], b[1] - 1)))
			row.append({"x": xy[0], "y": xy[1], "r": R.range(1.1, 1.8)})
		blisters.append(row)
	var E := Lib.eyes(a)
	var sweat := []
	for e: Dictionary in E:
		sweat.append([e.x0 - 1 if e.x0 < W / 2.0 else e.x1 + 1, e.y0 - 1])
	for side: int in [-1, 1]:
		var hand: Array = S.body.filter(func(b): return b[1] > H * 0.5 and b[1] < H * 0.7 and (b[0] <= l + 1 if side < 0 else b[0] >= r - 1) and not on.call(b[0], b[1] + 1))
		if hand.size():
			sweat.append(hand[0])
	if not sweat.size():
		sweat.append(pick.call(skin if skin.size() else S.body))
	var out := {"veins": veins, "wound": [wx, wy], "blisters": blisters, "sweat": sweat}
	m[seed] = out
	return out


# (JS: the walk closure inside body; recursive, so it takes what it captured)
static func walk(S: Dictionary, R: Px.Rng, veins: Array, x: float, y: float, ang: float, len: float, depth: int) -> void:
	var pts := []
	var s := 0
	while s < len:
		ang += R.range(-0.5, 0.5)
		x += cos(ang)
		y += sin(ang)
		if not S.on.call(Px.round(x), Px.round(y)):
			break
		pts.append([Px.round(x), Px.round(y), s / len])
		if depth < 2 and s > 2 and R.chance(0.16):
			walk(S, R, veins, x, y, ang + R.sign() * R.range(0.6, 1.1), len * 0.55, depth + 1)
		s += 1
	veins.append(pts)


# the sway: the body leans from the feet, the head moving most; on the tick, every row wobbles a pixel
static func offsets(t: float, H: int) -> Callable:
	var lean := 1.3 * sin((t / D) * TAU)
	var ph := since(t)
	var wob := ph < 0.12
	var w := sin((ph / 0.12) * PI) if wob else 0.0
	return func(my) -> float: return Px.round(lean * (1.0 - my / float(H)) + w * sin(my * 0.42 + ph * 40.0))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var P := Px.fit(o.palette, 8)
	var ph := since(t)
	# a green ring pulses out across the floor on the tick (far half), the floor glows sick
	var k := ph / 0.55
	if k < 1.0:
		Px.band(p, 0.0, 0.0, 5.0 + 22.0 * sqrt(k), 0.18, maxf(1.0, 2.5 * (1.0 - k)), 1.0 - k, [P[3], P[4], P[5], P[6]], func(g): return sin(g) < 0.0)
	p.shade(-28.0, -3.0, 28.0, 6.0, func(x, y, out):
		var d := Px.hypot(x / 24.0, (y - 0.5) / 4.0)
		if d < 1.0:
			out.l = P[4]
			out.k = (0.14 + 0.2 * exp(-ph / 0.2)) * (1.0 - d) * (1.0 - d))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var P := Px.fit(o.palette, 8)
	var a: Dictionary = o.actor
	var S := Lib.shape(a)
	var H: int = S.h
	var B := body(a, o.seed)
	var off := offsets(t, H)
	var ph := since(t)
	var tick := floori(t / TICK) % 2
	var vein := Px.hex(o.veins)
	# the body, swaying, its own colours sickened by green that rolls up it in waves
	for b: Array in S.body:
		var mx: int = b[0]
		var my: int = b[1]
		var c := Lib.colorAt(a, mx, my)
		var l := Px.luma(c)
		var wave := 0.5 + 0.5 * sin(TAU * ((my / float(H)) * 1.6 + (t / D) * 2.0))
		var sick: int = P[int(Px.clamp(1.0 + Px.round(l * 6.2), 1.0, 7.0))]
		var k := 0.22 + 0.4 * wave * wave
		p.px(a.x + mx + off.call(my), a.y + my, Px.mix(c, Px.mix(sick, P[6], 0.3) if (wave > 0.85 and l > 0.4) else sick, k))
	# veins creeping out from the wound and drawing back
	var grow := Px.smooth(0.0, D * 0.55, t) * (1.0 - Px.smooth(D * 0.62, D, t)) * 1.15
	for pts: Array in B.veins:
		for v: Array in pts:
			var x: float = v[0]
			var y: float = v[1]
			var u: float = v[2]
			if u < grow:
				p.px(a.x + x + off.call(y), a.y + y, P[2] if u > grow - 0.12 else vein)
	var wx: int = B.wound[0]
	var wy: int = B.wound[1]
	p.px(a.x + wx + off.call(wy), a.y + wy, P[6])
	p.px(a.x + wx + off.call(wy) - 1, a.y + wy, P[3])
	p.glow(a.x + wx, a.y + wy, 6.0, P[5], 0.3)
	# blisters: on the tick they swell up out of the skin, shine, and pop
	for bl: Dictionary in B.blisters[tick]:
		var x: float = a.x + bl.x + off.call(bl.y)
		var y: float = a.y + bl.y
		var grow2 := Px.clamp(ph / 0.16)
		var pop := ph > 0.38
		if not pop:
			var r: float = bl.r * grow2
			p.circle(x, y, r + 0.6, P[3])
			p.circle(x - 0.2, y - 0.2, r, P[5])
			if r > 0.8:
				p.px(x - 0.5, y - 0.8, WHITE)
			p.glow(x, y, 4.0, P[5], 0.3 * grow2)
		elif ph < 0.56:
			var k := (ph - 0.38) / 0.18
			for j in 6:
				var an: float = (j / 6.0) * TAU + bl.x
				var d: float = bl.r + 0.5 + k * 3.5
				p.dot(x + cos(an) * d, y + sin(an) * d - k * 2.0, P[6] if j % 2 else P[5], 1.2 - k)
			p.glow(x, y, 6.0, P[6], 0.4 * (1.0 - k))
	# toxic sweat: beads gather, run, fall and hiss on the floor
	for i in B.sweat.size():
		var sx: int = B.sweat[i][0]
		var sy: int = B.sweat[i][1]
		var per := D / 2.0
		var age := fmod(fmod(t - i * 0.37, per) + per, per)
		var gather := 0.35
		var x: float = a.x + sx + 0.5 + off.call(sy)
		var y0: float = a.y + sy
		if age < gather:
			var k := age / gather
			var run := Px.round(k * 2.0)
			p.px(x, y0 + run, P[6] if k > 0.5 else P[5])
			if k > 0.5:
				p.px(x, y0 + run - 1.0, P[4])
			continue
		var f := age - gather
		var fallH := -1.0 - (y0 + 2.0)
		var tf := sqrt((2.0 * maxf(1.0, fallH)) / G)
		if f < tf:
			var y := y0 + 2.0 + 0.5 * G * f * f
			p.line(x, y - minf(3.0, G * f * 0.012), x, y, P[4])
			p.px(x, y, P[6])
			continue
		var h := f - tf
		if h > 0.4:
			continue
		# the hiss: a green fleck spreads, a wisp of vapour curls up, sizzle sparks
		var k := h / 0.4
		p.line(x - 1.0 - k * 2.0, -1.0, x + 1.0 + k * 2.0, -1.0, P[6 if k < 0.4 else 4], 1.2 - k)
		for j in 3:
			p.dot(x + (j - 1) * (2.0 + 3.0 * k), -2.0 - j % 2 - 5.0 * k * (1.0 - k), P[6], 1.0 - k)
		p.disc(x + sin(k * 6.0) * 1.5, -3.0 - k * 6.0, 1.0 + 1.5 * k, P[5], 0.35 * (1.0 - k))
		p.glow(x, -1.5, 5.0, P[5], 0.35 * (1.0 - k))
	# the near half of the floor ring
	var k := ph / 0.55
	if k < 1.0:
		Px.band(p, 0.0, 0.0, 5.0 + 22.0 * sqrt(k), 0.18, maxf(1.0, 2.5 * (1.0 - k)), 1.0 - k, [P[3], P[4], P[5], P[6]], func(g): return sin(g) >= 0.0)
	# a sick light on the body, surging with the tick
	p.glow(0.0, a.y + H * 0.45, 26.0, P[4], 0.14 + 0.2 * exp(-ph / 0.18))
