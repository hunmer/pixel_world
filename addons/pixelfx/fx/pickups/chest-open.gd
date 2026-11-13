# The collection pop (white squash, a ring snapping out, star sparks) and the glints follow Sprite Fusion's
# open-source pickup (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/chest-open.js@ee0938cc965e3a4073b98a3e51112affce4a0ecb
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Chest open",
	"desc": "A banded chest rattles with gold light leaking from its seam, the lid kicks open, rays fan up, and coins and gems arc out, bounce, glint and get collected.",
	"tags": ["pickup", "chest", "treasure", "loot", "reward", "gold", "one-shot"],
	"size": [176, 112],
	"origin": [88, 96],
	"duration": 4.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#1e1206", "#4a2c08", "#86520c", "#c48412", "#f0b424", "#ffe066", "#fff6c4", "#ffffff"],
		"wood": ["#110a10", "#24131a", "#3a1f1f", "#552d24", "#73402c", "#925737", "#b07246"],
		"coins": 12,
		"seed": 3,
	},
}

# gems that come out with the gold: ruby, emerald, sapphire, amethyst (dark to bright)
static var GEMS := [
	["#2a0612", "#6e0f2a", "#b81c3c", "#f0405a", "#ff8a96", "#ffd2d6"],
	["#06200f", "#0f4a26", "#1a8040", "#34c060", "#8af0a0", "#d8ffe0"],
	["#0a1030", "#142a70", "#2050c0", "#3a8cf0", "#8ccaff", "#dcf0ff"],
	["#1a0a2a", "#3e1466", "#6a28a8", "#a050e0", "#d09cff", "#f0e0ff"],
].map(func(g): return Px.ramp(g))

const T_OPEN := 0.8
const T_COLLECT := 2.55
const T_POOF := 3.3
const RATTLES := [[0.1, 0.4], [0.32, 0.62], [0.5, 0.8], [0.64, 1.0]]
# the chest: 24 px wide, a 9 px front face, seen from a little above (tilt sin 0.34) so the open top shows
const HW := 12
const FH := 9
const CS := 0.94
const SN := 0.34
const HB := FH / CS
const LA := 6.0
const LB := 5.5
const STRAPS := [-9, 7]
static var L := Lib.Layer.new(40, 44)
static var IL := Lib.Layer.new(16, 16)


# the lid as rows of screen pixels: which point of its curved profile each row shows, which side, how lit.
# Points that swing below the rim (behind the back wall) are hidden.
static func lidRows(th: float) -> Array:
	var best := {}
	var ct := cos(th)
	var st := sin(th)
	for i in 261:
		var al := (i / 260.0) * PI
		var dz := LA + LA * cos(al)
		var dy := LB * sin(al)
		var z := -LA + dz * ct - dy * st
		var y := HB + dz * st + dy * ct
		if y < HB - 0.05:
			continue
		var nz := cos(al) / LA
		var ny := sin(al) / LB
		var nl := Px.hypot(nz, ny)
		nz /= nl
		ny /= nl
		var Nz := nz * ct - ny * st
		var Ny := nz * st + ny * ct
		var v := y * CS + (LA - z) * SN
		var dep := z * CS + y * SN
		var row := floori(-v)
		var cur: Variant = best.get(row)
		if not cur or dep > cur.dep:
			best[row] = {"row": row, "al": al, "dep": dep, "out": Nz * CS + Ny * SN > 0.0, "lit": Ny * 0.95 + Nz * 0.3 - 0.2, "crest": false, "seam": false}
	var rows := Px.sort(best.values(), func(a, b): return a.row - b.row)
	# the lit crest: the outside row facing the light most squarely
	var hi: Variant = null
	for r: Dictionary in rows:
		if r.out and (not hi or r.lit > hi.lit):
			hi = r
	if hi and hi.lit > 0.5:
		hi.crest = true
	# stave seams: the row nearest each seam angle
	for s: float in [PI / 3.0, (2.0 * PI) / 3.0]:
		var k: Variant = null
		for r: Dictionary in rows:
			if not k or absf(r.al - s) < absf(k.al - s):
				k = r
		if k and absf(k.al - s) < 0.4:
			k.seam = true
	return rows


static func tone(R: Array, l: float, steps: Array) -> int:
	return R[steps[0 if l > 0.6 else (1 if l > 0.25 else (2 if l > -0.1 else (3 if l > -0.45 else 4)))]]

static var IRON := Px.ramp(["#0e0d16", "#1d1c28", "#2f2e3e", "#474658", "#6a6a7e", "#9898ac"])


static func heat(C: Array, g: float, k: float) -> int:
	return C[int(Px.clamp(Px.round(k + g * 2.2), 0.0, 7.0))]


# the glowing hoard inside the open top: a mound of gold, lit from within
static func paintHoard(C: Array, W: Array, g: float) -> void:
	for y in range(-13, -9):
		for x in range(-HW, HW):
			var h := Px.rand(x, y, 7)
			var k := 5 if h < 0.18 else (4 if h < 0.55 else 3)
			L.setc(x, y, W[2] if (y == -13 and absf(x + 0.5) > 9.0) else heat(C, g, k - (1 if y == -13 else 0)))
	for x in range(-9, 9):
		var top := -13.0 - Px.round(2.2 * pow(cos(((x + 0.5) / 10.0) * (PI / 2.0)), 1.4))
		var y := top
		while y < -13.0:
			L.setc(x, y, heat(C, g, 5 if y == top else 4 + (1 if Px.rand(x, y, 3) < 0.3 else 0)))
			y += 1.0


# the lid at angle th: wood staves, iron straps, a gold lip and hasp outside; dark wood lit by the hoard inside
static func paintLid(C: Array, W: Array, th: float, g: float) -> void:
	var rows := lidRows(th)
	var top: int = rows[0].row if rows.size() else 0
	for r: Dictionary in rows:
		var u: float = r.al
		for x in range(-HW, HW):
			var strap := STRAPS.any(func(s: int) -> bool: return x == s or x == s + 1)
			var left := STRAPS.any(func(s: int) -> bool: return x == s)
			var side := (x + HW + 0.5) / (2.0 * HW)
			var corner := x == -HW or x == HW - 1
			var c: int
			if r.out:
				if r.row == top and corner and th < 0.6:
					continue
				var l: float = r.lit + 0.2 - side * 0.35 - (0.45 if r.row == top else 0.0)
				if u < 0.3 or (u < 0.55 and x >= -2 and x <= 1):
					c = tone(C, l + (0.15 if (x >= -2 and x <= 1) else 0.1), [6, 5, 5, 4, 3])
				elif corner:
					c = IRON[4] if x < 0 else IRON[2]
				elif strap:
					c = tone(IRON, l + (0.3 if left else -0.3), [5, 4, 3, 2, 1])
				elif r.seam:
					c = W[0]
				else:
					c = W[6] if (r.crest and side < 0.62) else tone(W, l, [5, 4, 3, 2, 1])
					if Px.rand(x >> 1, Px.round(u * 6.0), 11) < 0.2:
						c = W[maxi(0, W.find(c) - 1)]
			else:
				# the inside of the lid, lit by the hoard from below
				var k := g * pow(u / PI, 1.3)
				if u < 0.3:
					c = heat(C, g, 1.0)
				elif r.seam:
					c = W[0]
				else:
					c = Px.mix(W[4], C[5], 0.3) if k > 0.6 else (W[3] if k > 0.35 else (W[2] if k > 0.15 else W[1]))
				if corner:
					c = W[0]
			L.setc(x, r.row, c)


# the front face: a gold rim, two planks, iron straps and corners with rivets, a gold lock plate and keyhole
static func paintFront(C: Array, W: Array, g: float) -> void:
	for y in range(-FH, 0):
		for x in range(-HW, HW):
			var side := (x + HW + 0.5) / (2.0 * HW)
			var c: int
			if y == -FH:
				c = C[6] if side < 0.3 else (C[5] if side < 0.7 else C[4])
			elif y == -1:
				c = W[1]
			elif y == -5:
				c = W[0]
			else:
				var top := y == -8 or y == -4
				var bot := y == -6 or y == -2
				c = W[(4 if side < 0.45 else 3) if top else (2 if bot else 3)]
				if not top and Px.rand(x >> 1, y, 5) < 0.2:
					c = W[1 if bot else 2]
			if x == -HW:
				c = C[5] if y == -FH else IRON[4]
			if x == HW - 1:
				c = C[3] if y == -FH else IRON[2]
			for s: int in STRAPS:
				if x == s and y > -FH:
					c = IRON[5] if (y == -7 or y == -3) else IRON[4]
				if x == s + 1 and y > -FH:
					c = IRON[2]
			L.setc(x, y, c)
	for y in range(-FH, -3):
		for x in range(-2, 2):
			L.setc(x, y, C[3] if (x == 1 or y == -4) else (C[7] if (x == -2 and y == -FH) else C[5]))
	var kh: int = W[0] if g < 0.15 else (C[4] if g < 0.4 else (C[6] if g < 0.7 else WHITE))
	L.setc(-1, -7, kh)
	L.setc(0, -7, kh)
	L.setc(-1, -6, kh)
	L.setc(0, -6, Px.scale(kh, 0.85))


# the whole chest: past upright the lid stands behind the hoard, before that it covers it
static func paintChest(C: Array, W: Array, th: float, g: float) -> void:
	if th > 1.2:
		paintLid(C, W, th, g)
		paintHoard(C, W, g)
	else:
		paintHoard(C, W, g)
		paintLid(C, W, th, g)
	paintFront(C, W, g)


var C: Array
var W: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var loot: Array = []
var rings: Array = []
var bits: Array = []
var dust: Px.Particles
var DUST: int
var rays: Array
var t := 0.0
var opened := false
var poofed := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	W = Px.fit(o.wood, 7)
	R = Px.Rng.new(o.seed)
	var floor_ := func() -> float: return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]], "haze": C[4]})
	lights = Px.Lights.new()
	dust = Px.Particles.new({"rng": R, "sparks": [C[5], C[5], C[4], C[3]]})
	DUST = Px.hex("#5e5068")
	# the rays that fan out of the open chest
	rays = Px.arr(9, func(i: int) -> Dictionary:
		var u := (i / 8.0) * 2.0 - 1.0
		return {"a": u * 1.05 + R.range(-0.06, 0.06), "len": R.range(46.0, 64.0) * (1.2 - 0.4 * absf(u)), "w": R.range(0.035, 0.08), "d": R.range(0.0, 0.06), "f": R.range(5.0, 10.0), "ph": R.range(0.0, TAU)})
	# the loot: coins and gems, launched in a fan out of the mouth
	var n: float = o.coins
	var i := 0
	while i < n + 4.0:
		var gem := i >= n
		var s := 1.0 if i % 2 else -1.0
		var a := s * R.range(0.1, 0.5)
		var sp := R.range(190.0, 270.0)
		loot.append({
			"gem": gem, "G": GEMS[int(i - n) % GEMS.size()] if gem else null, "x": R.range(-7.0, 7.0), "y": -12.0, "vx": sin(a) * sp, "vy": -cos(a) * sp,
			"t0": T_OPEN + 0.03 + R.range(0.0, 0.2), "up": false, "rest": false, "r": 2.6 if gem else 3.0, "ax": R.range(-0.6, 0.6), "spin": R.range(0.0, TAU), "vs": R.sign() * R.range(14.0, 24.0),
			"settle": 0.0, "ph": R.next(), "pop": 0.0, "gone": false,
		})
		i += 1
	# they get picked up from the outside in
	var sorted := Px.sort(loot.duplicate(), func(a, b): return absf(b.vx) - absf(a.vx))
	for k in sorted.size():
		sorted[k].pop = T_COLLECT + k * 0.04 + R.range(0.0, 0.02)


func shake() -> Dictionary:
	var dx := 0.0
	var hop := 0.0
	var lid := 0.0
	for e: Array in RATTLES:
		var t0: float = e[0]
		var s: float = e[1]
		var u := t - t0
		if u < 0.0 or u > 0.18:
			continue
		var ee := 1.0 - u / 0.18
		dx += sin(u * 90.0) * 1.6 * s * ee
		if u < 0.06 and s > 0.5:
			hop = 1.0
		lid = maxf(lid, maxf(0.0, sin(u * 38.0)) * 0.13 * s * ee)
	if t >= T_OPEN and t < T_OPEN + 0.08:
		hop = 1.0
	# the last strain: the lid creeps up off the seam just before it bursts open
	var strain := Px.smooth(T_OPEN - 0.14, T_OPEN, t)
	if t < T_OPEN:
		lid = maxf(lid, 0.07 * strain)
		dx += ((1.0 if floori(t * 60.0) % 2 else -1.0) * 0.6) if strain > 0.2 else 0.0
	return {"dx": Px.round(dx), "hop": hop, "lid": lid}


func lidAngle(lid: float) -> float:
	if t < T_OPEN:
		return lid
	var u := t - T_OPEN
	var w := 30.0
	var z := 0.55
	var wd := w * sqrt(1.0 - z * z)
	return 1.98 * (1.0 - Px.exp(-z * w * u) * (cos(wd * u) + ((z * w) / wd) * sin(wd * u)))


# the light inside: it builds through the rattles, flares as the lid goes, then settles and fades
func inner() -> float:
	if t < T_OPEN:
		var k := 0.1 + 0.45 * Px.smooth(0.0, T_OPEN, t) + 0.5 * Px.smooth(T_OPEN - 0.14, T_OPEN, t)
		for e: Array in RATTLES:
			var t0: float = e[0]
			var s: float = e[1]
			if t > t0:
				k += 0.45 * s * Px.exp(-(t - t0) * 9.0)
		return k
	return (0.62 + 0.3 * Px.exp(-(t - T_OPEN) * 5.0)) * (1.0 - Px.smooth(T_COLLECT - 0.3, T_POOF, t)) + 0.05 * sin(t * 9.0)


func rayK(r: Dictionary) -> float:
	var u: float = t - T_OPEN - r.d
	if u < 0.0:
		return 0.0
	return Px.Ease.outCubic(Px.clamp(u / 0.1)) * (1.0 - Px.smooth(1.0, 2.1, u)) * (0.72 + 0.28 * sin(t * r.f + r.ph))


func update(dt: float) -> void:
	t += dt
	var g := inner()
	for e: Array in RATTLES:
		var t0: float = e[0]
		var s: float = e[1]
		if s > 0.5 and t - dt < t0 + 0.05 and t >= t0 + 0.05:
			for i in 4:
				var sd := 1.0 if i % 2 else -1.0
				ps.spawn(P.DUST, sd * R.range(9.0, 13.0), -1.0, sd * R.range(20.0, 50.0), -R.range(2.0, 8.0), R.range(0.3, 0.5), DUST, R.range(1.2, 2.2) * s)
	# anticipation: motes of light squeeze out of the seam and the keyhole
	if t < T_OPEN and R.chance(g * 0.08):
		var x := R.range(-11.0, 11.0)
		ps.spawn(P.STAR, x, -10.0, x * 1.5, -R.range(8.0, 30.0), R.range(0.3, 0.6), C[6] if R.chance(0.5) else C[5], R.range(0.4, 1.2))
	if not opened and t >= T_OPEN:
		opened = true
		lights.add(0.0, -18.0, 64.0, C[5], 0.45, 0.7)
		lights.add(0.0, -16.0, 22.0, WHITE, 0.35, 0.1)
		for i in 7:
			var a := -PI / 2.0 + R.range(-1.1, 1.1)
			var sp := R.range(120.0, 260.0)
			ps.spawn(P.SPARK, R.range(-8.0, 8.0), -13.0, cos(a) * sp, sin(a) * sp, R.range(0.12, 0.26))
		for i in 8:
			var s := R.sign()
			ps.spawn(P.DUST, s * R.range(10.0, 14.0), -1.0, s * R.range(30.0, 80.0), -R.range(2.0, 10.0), R.range(0.4, 0.7), DUST, R.range(1.6, 3.0))
	# the hold: gold dust rising out of the hoard, twinkles in the light
	if t > T_OPEN and t < T_COLLECT:
		if R.chance(0.22):
			ps.spawn(P.EMBER, R.range(-9.0, 9.0), -13.0, R.range(-12.0, 12.0), -R.range(25.0, 60.0), R.range(0.8, 1.5), C[5], R.range(0.8, 1.6))
		if R.chance(0.12):
			var a := R.range(-1.0, 1.0)
			var d := R.range(10.0, 40.0)
			ps.spawn(P.STAR, sin(a) * d, -12.0 - cos(a) * d, 0.0, -R.range(4.0, 12.0), R.range(0.3, 0.7), WHITE if R.chance(0.5) else C[6], R.range(0.5, 2.0))
	# the loot flies, bounces and settles
	for it: Dictionary in loot:
		if it.gone or t < it.t0:
			continue
		it.up = true
		if t >= it.pop + 0.13:
			it.gone = true
			var y: float = it.y - 6.0
			if it.gem:
				rings.append({"x": it.x, "y": y, "t0": t})
			lights.add(it.x, y, 18.0, it.G[4] if it.gem else C[5], 0.65, 0.25)
			for i in 4:
				var a := R.range(0.0, TAU)
				var sp := R.range(25.0, 55.0)
				ps.spawn(P.STAR, it.x, y, cos(a) * sp - it.x * 0.25, sin(a) * sp - 20.0, R.range(0.3, 0.55), ((it.G[5] if it.gem else C[6]) if i else WHITE), R.range(0.6, 1.5))
			continue
		if it.rest:
			it.settle += dt
			it.vx -= it.vx * 9.0 * dt
			it.x = Px.clamp(it.x + it.vx * dt, -74.0, 74.0)
			continue
		it.vy += 950.0 * dt
		it.x += it.vx * dt
		# keep the loot on the canvas: the far ones skid back off its edge
		if absf(it.x) > 74.0:
			it.x = Px.sign(it.x) * 74.0
			it.vx *= -0.3
		it.y += it.vy * dt
		it.spin += it.vs * dt
		var bottom: float = it.y + it.r
		if bottom >= -0.5 and it.vy > 0.0:
			it.y = -0.5 - it.r
			if it.vy > 110.0:
				ps.spawn(P.DUST, it.x, -1.0, R.range(-20.0, 20.0), -R.range(4.0, 12.0), R.range(0.25, 0.45), DUST, R.range(1.0, 1.8))
				if it.vy > 220.0:
					for i in 2:
						ps.spawn(P.SPARK, it.x, -1.0, R.range(-90.0, 90.0), -R.range(60.0, 140.0), R.range(0.1, 0.22))
					lights.add(it.x, -2.0, 9.0, C[5], 0.5, 0.12)
				it.vy = -it.vy * 0.42
				it.vx *= 0.5
				it.vs *= 0.55
			else:
				it.rest = true
				it.vy = 0.0
	var ri := rings.size() - 1
	while ri >= 0:
		if t - rings[ri].t0 > 0.3:
			rings.remove_at(ri)
		ri -= 1
	if not poofed and t >= T_POOF:
		# the empty chest dissolves from the lid down into rising gold dust
		poofed = true
		lights.add(0.0, -12.0, 40.0, C[5], 0.5, 0.6)
		L.begin(-20.0, -32.0)
		paintChest(C, W, lidAngle(0.0), 0.3)
		L.outline(W[0])
		var f := L.f
		var col := f.color
		var top := 0
		for k in col.size():
			if col[k]:
				top = mini(top, floori(k / float(f.w)) + f.oy)
		for k in col.size():
			# a Uint32Array read: unsigned, so it never equals the (signed) W[0]
			var c := col[k] & 0xFFFFFFFF
			if not c:
				continue
			var x := (k % f.w) + f.ox
			var y := floori(k / float(f.w)) + f.oy
			bits.append({"x": x, "y": y, "c": c, "td": T_POOF + (float(y - top) / -top) * 0.32 + Px.rand(x, y, 21) * 0.05, "mote": c != W[0] and Px.rand(x, y, 23) < 0.14, "done": false})
	for b: Dictionary in bits:
		if not b.done and t >= b.td:
			b.done = true
			if b.mote:
				dust.spawn(P.EMBER, b.x + 0.5, b.y + 0.5, R.range(-28.0, 28.0), -R.range(14.0, 50.0), R.range(0.4, 0.8), C[5], R.range(0.5, 1.1))
	ps.update(dt)
	dust.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	if t < T_POOF + 0.2:
		Lib.blobShadow(p, 0.0, 15.0, 1.0 - Px.smooth(T_POOF, T_POOF + 0.2, t))
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var g := inner()
	var sh := shake()
	var th := lidAngle(sh.lid)
	var sdx: float = sh.dx
	var hop: float = sh.hop
	var lid: float = sh.lid
	# light on the floor and round the chest
	var open := 1.0 if t >= T_OPEN else 0.0
	Lib.pool(p, 0.0, 0.0, 30.0 + 10.0 * g, 4.0, C[4], (0.1 + 0.18 * open) * g)
	p.glow(0.0, -16.0, 24.0 + 8.0 * g, C[4], (0.1 + 0.2 * open) * g)
	if t < T_POOF:
		L.begin(-20.0, -32.0)
		paintChest(C, W, th, minf(1.2, g))
		L.outline(W[0])
		L.draw(p, sdx, -hop)
	else:
		for b: Dictionary in bits:
			if not b.done:
				p.px(b.x, b.y, ((C[3] if b.c == W[0] else C[6]) if b.td - t < 0.04 else b.c))
	# light leaking from the seam before it opens
	if t < T_OPEN:
		p.glowLine(-11.0, -9.5 - hop, 11.0, -9.5 - hop, 5.0, C[5], 0.22 * g)
		# light through the crack under the lid, growing as the hoard brightens
		if g > 0.35 and lid < 0.015:
			p.line(-10.0 + sdx, -10.0 - hop, 9.0 + sdx, -10.0 - hop, func(u: float) -> int: return WHITE if absf(u - 0.5) < 0.2 else C[6], func(u: float) -> float: return (g - 0.35) * 2.2 * (1.0 - absf(u - 0.5) * 0.9))
		p.glow(sdx, -7.0 - hop, 6.0, C[6], 0.35 * g)
		# each bump lifts the lid off the seam and light shoots out of the crack in thin rays
		if lid > 0.015:
			for i in 8:
				var x := -10.5 + i * 3 + sdx + (Px.rand(i, 3) - 0.5) * 1.5
				var a := -PI / 2.0 + (x / 11.0) * 1.25
				var l := (7.0 + Px.rand(i, floorf(t * 30.0), 1) * 12.0) * minf(1.0, lid / 0.05)
				var y0 := -10.0 - hop
				p.line(x, y0, x + cos(a) * l, y0 + sin(a) * l, func(u: float) -> int: return WHITE if u < 0.25 else (C[6] if u < 0.6 else C[5]), func(u: float) -> float: return 1.15 - u)
				p.glowLine(x, y0, x + cos(a) * l * 0.7, y0 + sin(a) * l * 0.7, 3.0, C[5], 0.25)
	# the rays: wedges of light fanning out of the open chest
	for r: Dictionary in rays:
		var k := rayK(r)
		if k <= 0.01:
			continue
		var ox: float = sin(r.a) * 7.0
		var oy := -12.0
		var dx: float = sin(r.a)
		var dy: float = -cos(r.a)
		var len: float = r.len * (0.88 + 0.12 * sin(t * r.f * 0.7 + r.ph))
		var tw: float = tan(r.w)
		var x1 := ox + dx * len
		var y1 := oy + dy * len
		p.shade(minf(ox, x1) - 8.0, minf(oy, y1) - 8.0, maxf(ox, x1) + 8.0, maxf(oy, y1) + 8.0, func(x: float, y: float, out) -> void:
			var rx := x - ox
			var ry := y - oy
			var d := rx * dx + ry * dy
			if d < 0.0 or d > len:
				return
			var q := absf(rx * dy - ry * dx)
			var hw := 0.6 + d * tw
			var f := 1.0 - 0.35 * (q / hw) if q < hw else 0.65 * (1.0 - (q - hw) / 1.6)
			if f <= 0.0:
				return
			out.l = C[6] if q < hw * 0.45 else C[5]
			out.k = k * 0.55 * f * pow(1.0 - d / len, 1.4) * Px.smooth(5.0, 14.0, d))
	# the release: a flare out of the mouth
	if t >= T_OPEN and t < T_OPEN + 0.2:
		var a := (t - T_OPEN) / 0.2
		Px.flare(p, 0.0, -14.0, 22.0 * pow(1.0 - a, 1.4), 1.0 - a, C)
	# the loot
	for it: Dictionary in loot:
		if not it.up or it.gone:
			continue
		var pu: float = t - it.pop
		var lift := 6.0 * Px.Ease.outCubic(Px.clamp(pu / 0.1)) if pu > 0.0 else 0.0
		var wh := pu > 0.095
		var y: float = it.y - lift
		var ax: float = it.ax
		var spin: float = it.spin
		var flat := false
		if it.rest and not it.gem:
			# a coin falls flat with a wobble, then lies there as a lens of gold
			var w: float = Px.exp(-it.settle * 8.0) * absf(cos(it.settle * 22.0))
			ax = 0.0
			spin = acos(Px.clamp(0.5 + 0.5 * w, 0.0, 1.0))
			flat = w < 0.12
			y = -1.5 - lift if flat else -it.r * cos(spin) - lift
		if it.y > -10.0:
			Lib.blobShadow(p, it.x, 3.0, 0.7 * (1.0 - Px.clamp(-it.y / 30.0)))
		if it.gem:
			Lib.gemlet(IL, p, it.x, y, it.r, 0.4 * Px.sign(it.vs) if it.rest else it.spin, it.G, wh)
		else:
			Lib.coin(IL, p, Px.round(it.x) + 0.5 if flat else it.x, y, it.r, ax, acos(0.5) if flat else spin, C, wh, 1.0, not flat)
		p.glow(it.x, y, 9.0, it.G[4] if it.gem else C[5], 0.26 if it.rest else 0.18)
		p.glow(it.x, y, 3.0, WHITE, 0.12)
		# resting loot glints in turn
		if it.rest and t < it.pop:
			var u := fmod(t * 0.9 + it.ph, 1.0)
			if u < 0.16:
				Lib.glint(p, it.x - 1.0, y - 1.5, 2.6 * sin((u / 0.16) * PI), it.G[5] if it.gem else C[6], 0.5)
	for r: Dictionary in rings:
		var k: float = (t - r.t0) / 0.3
		var e := Px.Ease.outCubic(k)
		p.ring(r.x, r.y, 2.0 + 5.0 * e, 1.0, WHITE if k < 0.3 else C[6], 1.15 - k)
		p.glow(r.x, r.y, 12.0, C[5], 0.45 * (1.0 - k))
		if k < 0.5:
			Lib.glint(p, r.x, r.y, 3.4 * (1.0 - k / 0.5), C[6], 0.55)
	ps.draw(p, "front")
	dust.draw(p)
	lights.draw(p)
