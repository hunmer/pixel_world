# The cracks that open in stages and the burst into tumbling pieces follow Sprite Fusion's open-source ice
# shatter (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/spawn/egg-hatch.js@960bba8ae71947f0cfca35e45af4aa85626d0fb8
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Egg hatch",
	"desc": "A speckled egg rocks three times, each rock cracking it further with warm light leaking out, then pops: light pours out of the opening and lit shell halves tumble away.",
	"tags": ["spawn", "egg", "hatch", "birth", "crack", "shell", "light", "ground", "one-shot"],
	"size": [120, 96],
	"origin": [60, 84],
	"duration": 3.1,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#1e1826", "#4a3e52", "#857684", "#c4b4ac", "#ece0d2", "#fffaf0"],
		"glow": ["#ff8a2a", "#ffd25a", "#fff3c0"],
		"speckle": "#9a6a52",
		"seed": 31,
	},
}

const WOBBLES := [[0.3, 0.11], [0.85, 0.19], [1.4, 0.28]]
const POP := 1.98
const EW := 16
const EH := 20
const ZY := 11.0
const LIGHT := [-0.72, 0.5, 0.48]  # from the upper left, a little toward us
const CROSS := [[1, 0], [-1, 0], [0, 1], [0, -1]]

# the egg in its own pixels: x across from its middle, y up from its base; wider low than high
static var EGG := _egg()

static func _egg() -> Array:
	var out := []
	for y in EH:
		for x in range(int(-EW / 2.0), int(EW / 2.0)):
			var v := (y + 0.5) / EH
			var u := (x + 0.5) / (EW / 2.0)
			var e := 2.0 * v - 1.0
			var half := sqrt(maxf(0.0, 1.0 - e * e)) * (1.08 - 0.22 * v)
			if absf(u) <= half:
				out.append({"x": x, "y": y, "u": u, "v": v, "half": half})
	return out


static func K(x: Variant, y: Variant) -> String:
	return "%d,%d" % [x, y]


var C: Array
var G: Array
var SPK: int
var R: Px.Rng
var at := {}
var crack := {}
var zig: Array = []
var near: Array
var ps: Px.Particles
var lights: Px.Lights
var bits: Px.Bits
var pieces: Array = []
var t := 0.0
var popped := false
var crumbled := false
var cupA := 0.0
var cupV := 0.0
var done := [false, false, false]
var CRUMBLE: float


func has(x: Variant, y: Variant) -> bool:
	return at.has(K(x, y))


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 6)
	G = Px.fit(o.glow, 3)
	SPK = Px.hex(o.speckle)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	for e in EGG:
		at[K(e.x, e.y)] = e
	# shading: a round shell lit from the upper left, a core shadow, a rim of bounce light on the dark side
	for e in EGG:
		var nx := Px.clamp(e.u / maxf(0.05, e.half), -1.0, 1.0)
		var ny: float = (2.0 * e.v - 1.0) * 0.9
		var nz := sqrt(maxf(0.0, 1.0 - nx * nx - ny * ny))
		var d: float = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
		var edge := not has(e.x - 1, e.y) or not has(e.x + 1, e.y) or not has(e.x, e.y - 1) or not has(e.x, e.y + 1)
		var c: int = WHITE if d > 0.9 else (C[5] if d > 0.62 else (C[4] if d > 0.32 else (C[3] if d > 0.02 else (C[2] if d > -0.3 else C[1]))))
		if edge and nx > 0.25 and ny < 0.55:
			c = C[3]  # rim light on the shadow side
		elif Px.rand(e.x, e.y, 3) < 0.08 and e.v > 0.12 and not edge:
			c = SPK if d > 0.2 else Px.mix(SPK, C[1], 0.5)
		e.c = c
		e.lit = d
	# cracks: three stages, the last a zigzag right round the egg where the top breaks off
	walk(2.0, 15.0, -2.2, 3, 0)
	walk(2.0, 15.0, 0.3, 2, 0)
	walk(-2.0, 13.0, -0.6, 3, 1)
	walk(-2.0, 13.0, 2.7, 3, 1)
	walk(3.0, 11.0, 1.9, 2, 1)
	walk(2.0, 15.0, 1.5, 2, 1)
	for x in range(int(-EW / 2.0), int(EW / 2.0)):
		var y := ZY + (1.0 if (x + 8) % 3 == 0 else (0.0 if (x + 8) % 3 == 1 else -1.0))
		zig.append(y)
		if has(x, y):
			crack[K(x, y)] = 2
	# how close each pixel of shell is to an open crack, per stage: light shows through the shell round them
	near = []
	for s in 3:
		var pts := []
		for k in crack:
			if crack[k] <= s:
				var parts: PackedStringArray = String(k).split(",")
				pts.append([parts[0].to_float(), parts[1].to_float()])
		var m := {}
		for e in EGG:
			var mn := 9.0
			for pt in pts:
				mn = minf(mn, Px.hypot(pt[0] - e.x, pt[1] - e.y))
			m[K(e.x, e.y)] = mn
		near.append(m)

	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [WHITE, G[2], G[1], G[0]]})
	lights = Px.Lights.new()
	bits = Px.Bits.new({"ground": floor_})
	CRUMBLE = meta.duration - 0.55


# a crack: a jagged line, zigging either side of its heading, every step joined pixel to pixel
func walk(x: float, y: float, a: float, len: int, s: int) -> void:
	var px := Px.round(x)
	var py := Px.round(y)
	for i in len:
		var side := (1.0 if i % 2 else -1.0) * R.range(0.6, 1.3)
		a += R.range(-0.25, 0.25)
		x += cos(a) * 1.8 - sin(a) * side * 0.6
		y += sin(a) * 1.8 + cos(a) * side * 0.6
		var nx := Px.round(x)
		var ny := Px.round(y)
		var n := maxf(absf(nx - px), absf(ny - py))
		var j := 1
		while j <= n:
			var k := K(Px.round(px + ((nx - px) * j) / n), Px.round(py + ((ny - py) * j) / n))
			if not at.has(k):
				return
			if not crack.has(k):
				crack[k] = s
			j += 1
		px = nx
		py = ny


func zigAt(x: float) -> float:
	return zig[int(Px.clamp(x + EW / 2.0, 0.0, zig.size() - 1))]


func stage(tt: float) -> int:
	return 3 if tt > WOBBLES[2][0] + 0.05 else (2 if tt > WOBBLES[1][0] + 0.05 else (1 if tt > WOBBLES[0][0] + 0.05 else 0))


# the rock: a damped swing about the base, each one harder; a shiver just before it pops
func angle(tt: float) -> float:
	var a := 0.0
	for w in WOBBLES:
		var t0: float = w[0]
		var amp: float = w[1]
		var u := tt - t0
		if u > 0.0 and u < 0.55:
			a += amp * sin(u * 22.0) * Px.exp(-u * 5.0)
	if tt > POP - 0.14 and tt < POP:
		a += 0.05 * sin(tt * 120.0)
	return a


# the light inside: grows with each crack, flashes at the pop, then dies down in the empty cup
func inner(tt: float) -> float:
	return stage(tt) / 3.0 + 0.25 * maxf(0.0, sin(tt * 9.0)) * (stage(tt) / 3.0) if tt < POP else 1.6 * Px.exp(-(tt - POP) * 2.6)


# break part of the shell into pieces round a few seeds; each keeps its lit outside and a hot broken edge
func breakUp(keep: Callable, n: int, v: Callable, life: Callable) -> void:
	var seeds := Px.arr(n, func(_i): return [R.range(-EW / 2.0 + 1.0, EW / 2.0 - 1.0), R.range(0.0, EH)])
	var cells := {}
	for e in EGG:
		if not keep.call(e.x, e.y):
			continue
		var best := 0
		var bd := 1e9
		for i in seeds.size():
			var sx: float = seeds[i][0]
			var sy: float = seeds[i][1]
			var d := Px.hypot(e.x - sx, e.y - sy)
			if d < bd:
				bd = d
				best = i
		if not cells.has(best):
			cells[best] = []
		cells[best].append(e)
	for px: Array in cells.values():
		var cx := 0.0
		var cy := 0.0
		for e in px:
			cx += e.x + 0.5
			cy += e.y + 0.5
		cx /= px.size()
		cy /= px.size()
		var map := {}
		var mine := {}
		for e in px:
			mine[K(e.x, e.y)] = true
		for e in px:
			var edge := false
			for dd in CROSS:
				if not mine.has(K(e.x + dd[0], e.y + dd[1])) and has(e.x + dd[0], e.y + dd[1]):
					edge = true
					break
			# lit by the flash: no piece flies off in shadow
			var c: int = C[3] if (e.c == C[1] or e.c == C[2]) else e.c
			map[K(Px.round(e.x + 0.5 - cx), Px.round(-(e.y + 0.5 - cy)))] = [c, edge]
		var r := -INF
		for e in px:
			r = maxf(r, Px.hypot(e.x + 0.5 - cx, e.y + 0.5 - cy))
		r += 1.0
		var vv: Array = v.call(cx, cy)
		var l: float = life.call()
		pieces.append({"id": pieces.size() + 1, "x": cx, "y": -cy, "vx": vv[0], "vy": vv[1], "a": 0.0, "va": R.range(-10.0, 10.0), "r": r, "map": map, "life": l, "max": l, "rest": false, "born": t})


func pop() -> void:
	popped = true
	breakUp(func(x, y): return y >= zigAt(x), 6, func(cx, _cy): return [cx * R.range(8.0, 13.0) + R.range(-14.0, 14.0), -R.range(140.0, 210.0)], func(): return R.range(0.95, 1.15))
	for i in 14:
		var a := -PI / 2.0 + R.range(-1.2, 1.2)
		var sp := R.range(70.0, 170.0)
		bits.add({"kind": B.SHARD, "x": R.range(-5.0, 5.0), "y": -ZY - R.range(0.0, 4.0), "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 0.9, "drag": 0.6, "bounce": 0.3, "life": R.range(0.55, 0.85), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.2, 2.4), "c": R.pick([C[5], C[5], C[4], G[2]])})
	for i in 12:
		var a := -PI / 2.0 + R.range(-1.1, 1.1)
		var sp := R.range(50.0, 110.0)
		ps.spawn(P.STAR, R.range(-3.0, 3.0), -ZY - 2.0, cos(a) * sp, sin(a) * sp, R.range(0.4, 0.9), R.pick([WHITE, G[2], G[1]]), R.range(1.0, 2.2))
	for i in 10:
		var a := -PI / 2.0 + R.range(-1.0, 1.0)
		var sp := R.range(100.0, 200.0)
		ps.spawn(P.SPARK, R.range(-3.0, 3.0), -ZY - 1.0, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.45))
	# a puff of pale dust at the base, gone in a few frames
	for i in 4:
		var s := R.sign()
		ps.spawn(P.DUST, s * R.range(5.0, 8.0), -1.0, s * R.range(25.0, 50.0), -R.range(2.0, 6.0), R.range(0.15, 0.25), C[5], R.range(1.0, 1.8))
	lights.add(0.0, -ZY - 10.0, 40.0, G[1], 0.9, 0.55)
	lights.add(0.0, -ZY - 2.0, 18.0, WHITE, 0.9, 0.12)
	cupV = R.sign() * 3.0


func update(dt: float) -> void:
	t += dt
	# each rock opens more crack: a tick of light, a chip or two of shell, a puff at the base
	for i in WOBBLES.size():
		var t0: float = WOBBLES[i][0]
		if not done[i] and t >= t0 + 0.05:
			done[i] = true
			lights.add(-3.0 if i == 1 else 2.0, -14.0 + i, 8.0 + i * 2.0, G[1], 0.25 + i * 0.08, 0.18)
			for j in 2 + i * 2:
				ps.spawn(P.STAR, R.range(-5.0, 5.0), -R.range(8.0, 17.0), R.range(-20.0, 20.0), -R.range(10.0, 30.0), R.range(0.25, 0.5), R.pick([WHITE, G[2]]), R.range(0.6, 1.4))
			for j in i + 1:
				bits.add({"kind": B.SHARD, "x": R.range(-4.0, 4.0), "y": -R.range(10.0, 16.0), "vx": R.range(-50.0, 50.0), "vy": -R.range(40.0, 90.0), "g": 0.9, "drag": 0.5, "bounce": 0.3, "life": R.range(0.5, 0.8), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.0, 1.6), "c": C[4]})
			ps.spawn(P.DUST, R.sign() * R.range(5.0, 7.0), -0.5, R.sign() * R.range(8.0, 18.0), -R.range(1.0, 3.0), R.range(0.15, 0.25), C[5], R.range(0.8, 1.4))
	if not popped and t >= POP:
		pop()
	# light keeps welling up out of the empty cup for a moment: something came out of there
	if popped and t < POP + 0.6 and R.chance(0.35):
		ps.spawn(P.MOTE, R.range(-4.0, 4.0), -ZY - 1.0, R.range(-8.0, 8.0), -R.range(40.0, 80.0), minf(R.range(0.4, 0.8), meta.duration - 0.1 - t), R.pick([G[2], G[1], WHITE]), 0.7)
	if popped and not crumbled and t >= CRUMBLE:
		crumbled = true
		breakUp(func(x, y): return y < zigAt(x), 4, func(cx, _cy): return [cx * R.range(4.0, 8.0), -R.range(40.0, 80.0)], func(): return R.range(0.38, 0.48))
		for i in 3:
			ps.spawn(P.DUST, R.range(-6.0, 6.0), -1.0, R.sign() * R.range(10.0, 25.0), -R.range(2.0, 6.0), R.range(0.15, 0.25), C[5], R.range(1.0, 1.6))
	if popped:
		cupV += (-cupA * 90.0 - cupV * 4.0) * dt
		cupA += cupV * dt
	var i := pieces.size() - 1
	while i >= 0:
		var q: Dictionary = pieces[i]
		q.life -= dt
		if q.life <= 0.0:
			pieces.remove_at(i)
			i -= 1
			continue
		if q.rest:
			i -= 1
			continue
		q.vy += 900.0 * dt
		q.vx -= q.vx * 0.6 * dt
		q.x += q.vx * dt
		q.y += q.vy * dt
		q.a += q.va * dt
		var g: float = -q.r * 0.45
		if q.y > g and q.vy > 0.0:
			q.y = g
			if q.vy > 80.0:
				q.vy *= -0.35
				q.vx *= 0.6
				q.va *= 0.5
			else:
				q.rest = true
				q.vy = 0.0
				q.vx = 0.0
		i -= 1
	bits.update(dt)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# a soft contact shadow under the egg, shifting as it rocks
	if not crumbled:
		var sx := 0.0 if popped else -angle(t) * 8.0
		var k := 1.0 - Px.smooth(POP, CRUMBLE, t) * 0.4 if popped else 1.0
		for y in range(-1, 2):
			for x in range(-10, 11):
				var a := (x + 0.5 - sx) / 9.5
				var b := (y + 0.5) / 1.8
				var d := a * a + b * b
				if d < 1.0:
					p.blend(x, y, C[0], 0.5 * k * (1.0 - d))
	# warm light on the floor as it leaks out
	var g := inner(t)
	if g > 0.05:
		p.glow(0.0, -3.0, 22.0, G[0], 0.18 * minf(1.2, g))
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var st := stage(t)
	var a := cupA * 0.03 if popped else angle(t)
	var ca := cos(a)
	var sa := sin(a)
	var g := inner(t)
	if not crumbled:
		p.shade(-12.0, -EH - 4.0, 12.0, 1.0, func(x, y, out):
			var ux := floori(x * ca + y * sa)
			var uy := floori(-(-x * sa + y * ca))
			var e: Variant = at.get(K(ux, uy))
			var inside: bool = e != null and not (popped and uy >= zigAt(ux))
			if not inside:
				# a dark outline holds the egg's shape
				var n := false
				for dd in CROSS:
					var f: Variant = at.get(K(ux + dd[0], uy + dd[1]))
					if f != null and not (popped and uy + dd[1] >= zigAt(ux + dd[0])):
						n = true
						break
				if n and not (popped and uy >= zigAt(ux) and uy <= zigAt(ux) + 1.0):
					out.c = C[0]
				return
			var cs: Variant = crack.get(K(ux, uy))
			if popped:
				# the cup: its broken rim burns with the light inside, cooling as it fades
				out.c = (WHITE if g > 0.9 else (G[2] if g > 0.4 else (G[1] if g > 0.12 else C[4]))) if uy >= zigAt(ux) - 1.0 else e.c
				if uy >= zigAt(ux) - 1.0:
					out.k = 0.25 * g
					out.l = G[1]
				return
			if cs != null and cs < st:
				# an open crack: deep orange light in the gap, flashing white the moment it opens
				var fresh: bool = t - WOBBLES[cs][0] < 0.17
				out.c = WHITE if fresh else (G[1] if Px.rand(ux, uy, int(t * 20.0)) < 0.25 + 0.1 * st else G[0])
				out.k = 0.14 + 0.06 * st
				out.l = G[1]
				return
			# the lip of each crack falls into shadow below it, so the gap reads as a gap
			var c1: Variant = crack.get(K(ux, uy + 1))
			var c2: Variant = crack.get(K(ux + 1, uy))
			if (c1 != null and c1 < st) or (c2 != null and c2 < st):
				out.c = C[2] if e.lit > 0.3 else C[1]
				return
			# light shows through the shell in a halo round the cracks, and the whole egg warms a little
			var dn: float = near[st - 1].get(K(ux, uy)) if st > 0 else 9.0
			var k := minf(1.0, g * 1.5)
			var base: int = Px.mix(e.c, G[0], 0.05 * st * k) if (st > 0 and e.c != SPK) else e.c
			out.c = Px.mix(base, G[1], (0.32 if st >= 2 else 0.2) * k) if dn < 1.6 else (Px.mix(base, G[1], 0.14 * k) if (dn < 2.7 and st >= 2) else base))
	# the pop: the opening floods white, and light rays fan up out of it
	var q := t - POP
	if popped and q < 1.2 and not crumbled and g > 0.22:
		var _k := Px.clamp(q / 1.2)
		var oy := -ZY + 0.5
		var rx := 7.0
		for y in range(-2, 3):
			for x in range(-7, 8):
				var d := Px.hypot((x + 0.5) / rx, (y + 0.5) / 2.2)
				if d > 1.0:
					continue
				if g < 0.6 and d > 0.75:
					continue
				p.px(x, oy + y, (WHITE if d < 0.7 else G[2]) if g > 1.0 else ((G[2] if d < 0.5 else G[1]) if g > 0.6 else (G[1] if d < 0.45 else G[0])))
		p.glow(0.0, oy, 16.0, G[1], 0.6 * g)
		if q < 0.65:
			var rk := q / 0.65
			var L := 36.0 * Px.Ease.outCubic(Px.clamp(q / 0.1)) * (1.0 - rk * 0.6)
			for i in 7:
				var an := -PI / 2.0 + (i - 3) * 0.24 + 0.05 * sin(t * 6.0 + i)
				var len := L * (0.65 if i % 2 else 1.0)
				var w := 1 if i % 2 else 2
				var x1 := cos(an) * len
				var y1 := oy + sin(an) * len
				for j in w:
					p.line(j * 0.8 - 0.4, oy - 1.0, x1 + j * 0.8 - 0.4, y1, func(u): return WHITE if u < 0.3 else (G[2] if u < 0.65 else G[1]), func(u): return (1.0 - u * u) * (1.1 - rk))
				p.glowLine(0.0, oy, x1, y1, 5.0, G[1], 0.35 * (1.0 - rk))
		if q < 0.1:
			p.glow(0.0, oy - 4.0, 30.0, WHITE, 0.6 * (1.0 - q / 0.1))
		# the light that lingers over the cup
		p.glowLine(0.0, oy, 0.0, oy - 26.0, 8.0, G[1], 0.25 * g)
	# the inside glow through the shell before it pops
	if not popped and g > 0.0:
		p.glow(0.0, -EH * 0.55, 7.0 + 2.0 * st, G[1], 0.05 * g)
	# pieces of shell: their lit outsides, their broken edges hot at first
	for s in pieces:
		var c2 := cos(s.a)
		var s2 := sin(s.a)
		var f := minf(1.0, s.life / 0.4)
		var r := ceili(s.r)
		var hot: bool = t - s.born < 0.35
		var map: Dictionary = s.map
		for py in range(-r, r + 1):
			for px in range(-r, r + 1):
				var ux := Px.round(px * c2 + py * s2)
				var uy := Px.round(-px * s2 + py * c2)
				var m: Variant = map.get(K(ux, uy))
				if m != null and Px.rand(ux, uy, s.id) < f:
					p.px(floorf(s.x) + px, floorf(s.y) + py, (G[2] if hot else C[4]) if m[1] else m[0])
		if hot:
			p.glow(s.x, s.y, 6.0, G[1], 0.3)
	bits.draw(p)
	if popped and q < 0.9:
		Px.sparkle(p, -3.0, -ZY - 6.0, Px.round(4.0 * (1.0 - q / 0.9)), WHITE, G[1], 0.4)
	ps.draw(p, "front")
	lights.draw(p)
