# The smear that trails the lash (white at its leading edge, cooling down the ramp as it thins), the glint and
# crack burst at the tip, are adapted from Sprite Fusion's open-source slash (https://www.spritefusion.com/pixel-art-vfx/slash),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/nature/vine-whip.js@b82ba7f3b1591cd3b32b3f18cab8eb41b9a4ac07
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Vine whip",
	"desc": "A thorny vine bursts from the floor, rears back coiled, then lashes out right in a whip crack that sprays sap and tears off leaves, before sliding back into the ground.",
	"tags": ["nature", "vine", "plant", "whip", "melee", "directional", "one-shot"],
	"size": [216, 128],
	"origin": [60, 114],
	"duration": 1.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#0c1a10", "#173a1a", "#24582a", "#357a34", "#52a03e", "#86c84e", "#c4ec7a", "#f4ffd0"],
		"thorn": ["#2a1410", "#5e2a1a", "#a04c2e", "#e89a6a"],
		"soil": ["#120c0c", "#251917", "#3b2a24", "#553d31", "#715440", "#8f6e52", "#b8966e", "#e6d0a8"],
		"seed": 3,
	},
}

const N := 24
const LS := 3.3
const LASH := 0.36
const LAG := 0.0052
const TAU_S := 0.055
const OMEGA := TAU / 0.21
static var CRACK: float = LASH + LAG * N + (PI - atan(OMEGA * TAU_S)) / OMEGA


# a damped spring's step: 0 before u = 0, swings past 1, settles
static func spring(u: float) -> float:
	return 0.0 if u <= 0.0 else 1.0 - Px.exp(-u / TAU_S) * (cos(OMEGA * u) + sin(OMEGA * u) / (OMEGA * TAU_S))


# the vine's points at time t: each segment's angle blends from standing, to reared back with the tip coiled
# over, to lashed out right; the lash runs up the vine as a wave, so the tip whips through last
static func pose(t: float) -> Array:
	var grow := Px.Ease.outCubic(Px.clamp(t / 0.14)) * (1.0 - Px.Ease.inCubic(Px.clamp((t - 1.0) / 0.3)))
	var rear := Px.smooth(0.1, LASH, t)
	var relax := Px.smooth(0.82, 1.0, t)
	var pts := [[0.0, (1.0 - grow) * (N * LS + 6.0)]]
	for i in N:
		var s := i / float(N)
		var stand := -PI / 2.0 + 0.25 * sin(s * 3.0 + t * 7.0) * s
		var back := -PI / 2.0 - 0.3 - 1.65 * pow(s, 1.3)
		var out := -1.0 + 0.9 * pow(s, 0.6)
		var a := Px.lerp(stand, back, rear)
		a = Px.lerp(a, out, spring(t - LASH - LAG * i))
		a = Px.lerp(a, stand, relax)
		var x: float = pts[i][0]
		var y: float = pts[i][1]
		pts.append([x + cos(a) * LS, y + sin(a) * LS])
	return pts


# a translucent polygon: the soft body of the smear under its streaks
static func haze(p: Px.Painter, pts: Array, c: int, a: float) -> void:
	var x0 := INF
	var y0 := INF
	var x1 := -INF
	var y1 := -INF
	for q: Array in pts:
		var x: float = q[0]
		var y: float = q[1]
		x0 = minf(x0, x)
		x1 = maxf(x1, x)
		y0 = minf(y0, y)
		y1 = maxf(y1, y)
	for y in range(floori(y0), ceili(y1) + 1):
		for x in range(floori(x0), ceili(x1) + 1):
			var inside := false
			var i := 0
			var j := pts.size() - 1
			while i < pts.size():
				var xi: float = pts[i][0]
				var yi: float = pts[i][1]
				var xj: float = pts[j][0]
				var yj: float = pts[j][1]
				if (yi > y + 0.5) != (yj > y + 0.5) and x + 0.5 < ((xj - xi) * (y + 0.5 - yi)) / (yj - yi) + xi:
					inside = not inside
				j = i
				i += 1
			if inside:
				p.blend(x, y, c, a)


static func width(s: float) -> float:
	return 1.2 + 4.8 * pow(1.0 - s, 0.7)


# the vine itself: a thick stroke lit on its upper side with a bright edge, dark beneath, bark notches
static func vine(p: Px.Painter, pts: Array, C: Array) -> void:
	for i in N:
		var ax: float = pts[i][0]
		var ay: float = pts[i][1]
		var bx: float = pts[i + 1][0]
		var by: float = pts[i + 1][1]
		var dx := bx - ax
		var dy := by - ay
		var L := Px.hypot(dx, dy)
		if not L:
			L = 1.0
		var nx := -dy / L
		var ny := dx / L
		var w0 := width(i / float(N)) / 2.0
		var w1 := width((i + 1) / float(N)) / 2.0
		var up := 1 if nx * -0.6 + ny * -0.8 > 0.0 else -1
		var X0 := floori(minf(ax, bx) - 4.0)
		var X1 := ceili(maxf(ax, bx) + 4.0)
		var Y0 := floori(minf(ay, by) - 4.0)
		var Y1 := ceili(maxf(ay, by) + 4.0)
		for y in range(Y0, Y1 + 1):
			for x in range(X0, X1 + 1):
				if y > 0:
					continue
				var px := x + 0.5 - ax
				var py := y + 0.5 - ay
				var u := (px * dx + py * dy) / (L * L)
				if u < -0.15 or u > 1.15:
					continue
				var d := px * nx + py * ny
				var w := Px.lerp(w0, w1, Px.clamp(u)) + 0.35
				if absf(d) > w:
					continue
				var side := Px.sign(d) * up
				var q := absf(d) / w
				var arc := (i + u) * LS
				var c: int = (C[5] if side > 0.0 else C[1]) if q > 0.8 else ((C[4] if q > 0.35 else C[3]) if side > 0.0 else (C[2] if q > 0.4 else C[3]))
				if w > 1.6 and absf(fmod(arc + d * 0.8, 5.0) - 2.5) < 0.45 and q < 0.8:
					c = C[2]
				p.px(x, y, c)


# thorns along it, alternating sides, hooked back toward the root; leaves on short stalks
static func thorns(p: Px.Painter, pts: Array, T: Array, C: Array, t: float, _R: Variant) -> void:
	var i := 2
	while i < N - 1:
		var ax: float = pts[i][0]
		var ay: float = pts[i][1]
		var bx: float = pts[i + 1][0]
		var by: float = pts[i + 1][1]
		var dx := bx - ax
		var dy := by - ay
		var L := Px.hypot(dx, dy)
		if not L:
			L = 1.0
		var side := 1.0 if int(i / 2.0) % 2 else -1.0
		var nx := (-dy / L) * side
		var ny := (dx / L) * side
		var w := width(i / float(N)) / 2.0
		var len := 1.8 + 2.4 * (1.0 - i / float(N))
		var tx0 := dx / L
		var ty0 := dy / L
		var x0 := ax + nx * (w - 0.5)
		var y0 := ay + ny * (w - 0.5)
		var tx := x0 + nx * len - tx0 * len * 0.7
		var ty := y0 + ny * len - ty0 * len * 0.7
		if y0 > 0.0:
			i += 2
			continue
		# a hooked thorn: a broad foot on the stem, a sharp lit point raking back toward the root
		p.tri(x0 - tx0 * 1.6, y0 - ty0 * 1.6, x0 + tx0 * 1.4, y0 + ty0 * 1.4, tx, ty, T[1])
		p.line(x0 + tx0 * 0.8, y0 + ty0 * 0.8, tx, ty, T[2])
		p.px(tx, ty, T[3])
		i += 2
	for k in [7, 13, 18]:
		var ax: float = pts[k][0]
		var ay: float = pts[k][1]
		var bx: float = pts[k + 1][0]
		var by: float = pts[k + 1][1]
		var a := atan2(by - ay, bx - ax)
		var side := 1.0 if k % 2 else -1.0
		if ay > -2.0:
			continue
		var la: float = a + side * 1.1 + sin(t * 9.0 + k) * 0.2
		var lx := ax + cos(la) * 4.0
		var ly := ay + sin(la) * 4.0
		Lib.drawLeaf(p, lx, ly, 7.0, 2.2, la, 0.3 + sin(t * 5.0 + k) * 0.4, [C[1], C[3], C[5], C[6]])


var C: Array
var T: Array
var S: Array
var R: Px.Rng
var ps: Px.Particles
var drops: Lib.Drops
var lights: Px.Lights
var chips: Array
var torn: Array
var spots: Array
var t := 0.0
var burst := false
var cracked := false
var sunk := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	T = Px.fit(o.thorn, 4)
	S = Px.fit(o.soil, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]]})
	drops = Lib.Drops.new(floor_)
	lights = Px.Lights.new()
	chips = []
	torn = []
	spots = []
	t = 0.0
	burst = false
	cracked = false
	sunk = false


func dirt(n: int, sp: float) -> void:
	for i in n:
		var a := -PI / 2.0 + R.range(-1.2, 1.2)
		var v := R.range(60.0, 200.0) * sp
		chips.append({"x": R.range(-3.0, 3.0), "y": -1.0, "vx": cos(a) * v, "vy": sin(a) * v, "a": R.range(0.0, TAU), "va": R.range(-15.0, 15.0), "s": R.range(1.4, 2.6), "pts": Lib.stoneShape(R), "life": minf(R.range(0.6, 0.9), meta.duration - 0.05 - t)})
	for i in n * 3:
		var a := -PI / 2.0 + R.range(-1.0, 1.0)
		var v := R.range(50.0, 200.0) * sp
		ps.spawn(P.GRIT, R.range(-3.0, 3.0), -1.0, cos(a) * v, sin(a) * v, minf(R.range(0.5, 0.9), meta.duration - 0.05 - t), R.pick([S[5], S[4], S[3]]), 2.0 if R.chance(0.3) else 1.0)
	for i in n:
		ps.spawn(P.DUST, R.range(-4.0, 4.0), -R.range(0.0, 3.0), R.sign() * R.range(15.0, 60.0), -R.range(4.0, 20.0), minf(R.range(0.4, 0.8), meta.duration - 0.05 - t), S[5], R.range(2.0, 4.0))


func update(dt: float) -> void:
	t += dt
	if not burst:
		burst = true
		dirt(6, 1.0)
	if not cracked and t >= CRACK:
		cracked = true
		var a := pose(t)
		var b := pose(t - 0.01)
		var x: float = a[N][0]
		var y: float = a[N][1]
		var vx: float = (x - b[N][0]) / 0.01
		var vy: float = (y - b[N][1]) / 0.01
		var sp := Px.hypot(vx, vy)
		if not sp:
			sp = 1.0
		lights.add(x, y, 22.0, WHITE, 0.5, 0.08)
		lights.add(x, y, 50.0, C[5], 0.35, 0.4)
		for i in 18:
			var ang := atan2(vy, vx) + R.range(-0.7, 0.7)
			var v := R.range(80.0, 260.0)
			drops.add(x, y, cos(ang) * v, sin(ang) * v - R.range(0.0, 60.0), 2.0 if R.chance(0.3) else 1.0)
		for i in 4:
			torn.append({"x": x, "y": y, "vx": (vx / sp) * R.range(40.0, 120.0) + R.range(-30.0, 30.0), "vy": R.range(-90.0, -20.0), "a": R.range(0.0, TAU), "va": R.range(-12.0, 12.0), "fl": R.range(0.0, TAU), "vf": R.range(8.0, 16.0), "life": R.range(0.65, 0.8), "max": 0.0})
		for l: Dictionary in torn:
			l.max = l.life
		for i in 8:
			ps.spawn(P.STAR, x + R.range(-6.0, 6.0), y + R.range(-6.0, 6.0), R.range(-20.0, 20.0), R.range(-20.0, 20.0), R.range(0.15, 0.35), C[7], R.range(0.6, 1.6))
	if not sunk and t >= 1.08:
		sunk = true
		dirt(3, 0.5)
	drops.update(dt, func(d: Dictionary) -> void: spots.append({"x": d.x, "t0": t, "w": d.s * 0.7 + R.range(0.2, 1.0)}))
	var i := chips.size() - 1
	while i >= 0:
		var c: Dictionary = chips[i]
		c.life -= dt
		if c.life <= 0.0:
			chips.remove_at(i)
		c.vy += 950.0 * dt
		c.x += c.vx * dt
		c.y += c.vy * dt
		c.a += c.va * dt
		if c.y > 0.0:
			c.y = 0.0
			c.vy *= -0.3
			c.vx *= 0.6
		i -= 1
	i = torn.size() - 1
	while i >= 0:
		var l: Dictionary = torn[i]
		l.life -= dt
		if l.life <= 0.0:
			torn.remove_at(i)
		l.vy += 160.0 * dt
		l.vx -= l.vx * 2.5 * dt
		l.vy -= l.vy * 2.0 * dt
		l.x += l.vx * dt + sin(l.fl) * 20.0 * dt
		l.y += l.vy * dt
		l.a += l.va * dt
		l.fl += l.vf * dt
		i -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# a hole torn in the floor where it comes up, sap spots where it sprays
	var k := 1.0 - Px.smooth(1.15, 1.35, t)
	for x in range(-5, 6):
		p.dot(x, 0.0, S[0] if absi(x) < 3 else S[1], k * (1.0 - absi(x) / 7.0))
	for s: Dictionary in spots:
		var a := (1.0 - Px.smooth(0.25, 0.6, t - s.t0)) * (1.0 - Px.smooth(1.2, 1.35, t))
		for x in range(floori(s.x - s.w), ceili(s.x + s.w) + 1):
			p.dot(x, 0.0, C[6] if t - s.t0 < 0.1 else C[4], a)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var pts := pose(t)
	# the smear: a fan of streaks, each the path one point of the outer vine just swept, the tip's white,
	# the ones further in cooling down the ramp, all fading back along their length
	if t > LASH + 0.04 and t < CRACK + 0.1:
		var age := Px.clamp((t - CRACK + 0.02) / 0.12)
		var hist := []
		for k in 12:
			hist.append(pose(t - k * 0.0045))
		for k in 6:
			haze(p, [hist[k][N], hist[k + 1][N], hist[k + 1][N - 12], hist[k][N - 12]], C[6] if k < 2 else C[5], 0.4 * (1.0 - k / 6.0) * (1.0 - age))
		var i := N - 12
		while i <= N:
			var q := (N - i) / 12.0
			var col: int = WHITE if q < 0.1 else (C[7] if q < 0.3 else (C[6] if q < 0.55 else (C[5] if q < 0.8 else C[4])))
			var len := Px.roundi(11.0 * (1.0 - q * 0.6))
			for k in len:
				p.line(hist[k][i][0], hist[k][i][1], hist[k + 1][i][0], hist[k + 1][i][1], WHITE if (k < 2 and q < 0.1) else col, (1.0 - age) * (1.0 if k < len * 0.5 else 2.0 * (1.0 - k / float(len))))
			i += 2
		p.glowLine(hist[0][N][0], hist[0][N][1], hist[6][N][0], hist[6][N][1], 14.0, C[5], 0.35 * (1.0 - age))
	vine(p, pts, C)
	thorns(p, pts, T, C, t, null)
	var lk := Px.smooth(LASH, CRACK, t) * (1.0 - Px.smooth(CRACK, CRACK + 0.35, t))
	if lk > 0.0:
		var i := 6
		while i <= N:
			p.glow(pts[i][0], pts[i][1], 12.0, C[5], 0.18 * lk)
			i += 6
	# the crack: a white burst of air lines and a glint at the tip
	var e := t - CRACK
	if e >= 0.0 and e < 0.12:
		var x: float = pts[N][0]
		var y: float = pts[N][1]
		var k := 1.0 - e / 0.12
		for j in 7:
			var a := (j / 7.0) * TAU + 0.3
			var r0 := 4.0 + 10.0 * (1.0 - k)
			var r1 := r0 + 5.0 * k
			p.line(x + cos(a) * r0, y + sin(a) * r0, x + cos(a) * r1, y + sin(a) * r1, WHITE if k > 0.5 else C[6])
		p.ring(x, y, 3.0 + 8.0 * (1.0 - k), 1.0, C[7], k)
		Px.sparkle(p, x, y, 7.0 * k, C[7], C[5], 0.4)
	for c: Dictionary in chips:
		Lib.drawRock(p, c.x, c.y, c.s, c.a, c.pts, S, minf(1.0, c.life / 0.25))
	for l: Dictionary in torn:
		Lib.drawLeaf(p, l.x, l.y, 6.0, 2.0, l.a, l.fl, [C[1], C[3], C[5], C[6]], minf(1.0, l.life / 0.3))
	drops.draw(p, C)
	ps.draw(p, "front")
	lights.draw(p)
