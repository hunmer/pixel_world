# The eruption recipe (a frost line racing ahead, each spike punching up white with a spray of shards, a puff
# and a glint, the floor frosting behind) is adapted from Sprite Fusion's open-source ice
# (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ice/ice-spikes.js@3dfab7eec367e17d933e0421966ae634b9f2660d
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Ice spikes",
	"desc": "A frost line races along the floor and clusters of jagged ice blades burst up behind it in a rising wave, glint, flash white together and shatter into toppling shards.",
	"tags": ["ice", "spikes", "ground", "wave", "directional", "magic", "one-shot"],
	"size": [264, 112],
	"origin": [24, 96],
	"duration": 3,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "reach": 172, "height": 56, "seed": 3},
}

const START := 0.04  # the frost line runs out
const RUN := 0.44
const SHIMMER := 0.74  # a glint runs down the line
const TREMBLE := 1.2  # they shiver, flash white together and break
const FLASH := 1.36
const SHATTER := 1.42
const MELT := 1.75  # the frost goes, oldest first

var C: Array
var R: Px.Rng
var REACH: float
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var panes: Lib.Panes
var clusters: Array = []
var crest: Dictionary
var t := 0.0
var broke := false
var trembled := false


func splinter(x: float, y: float, vx: float, n: int) -> void:
	for i in n:
		bits.add({"kind": B.SHARD, "x": x + R.range(-2.0, 2.0), "y": y - 1.0, "vx": vx * 0.5 + R.range(-45.0, 45.0), "vy": -R.range(30.0, 100.0), "g": 0.8, "drag": 0.6, "bounce": 0.35, "life": R.range(0.4, 0.75), "a": R.range(0.0, TAU), "va": R.range(-18.0, 18.0), "s": R.range(1.2, 2.4), "c": C[R.int_(4, 7)]})


func front(tt: float) -> float:
	return REACH * (1.0 - pow(1.0 - Px.seg(tt, START, START + RUN), 1.7))


func reachedAt(x: float) -> float:
	return START + RUN * (1.0 - pow(1.0 - Px.clamp(x / REACH), 1.0 / 1.7))


# clusters along the line: a main blade leaning into the wave and two to four splayed round it, heights
# swelling to a crest past the middle and falling off at the end
static func env(q: float) -> float:
	return 0.28 + 0.72 * exp(-pow((q - 0.64) / 0.3, 2.0))


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	REACH = o.reach
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]], "haze": C[5]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	panes = Lib.Panes.new({
		"ground": floor_,
		"onCrumble": func(q: Dictionary) -> void:
			splinter(q.x, 0.0, 0.0, 3)
			ps.spawn(P.VAPOUR, q.x, -1.0, R.range(-12.0, 12.0), -R.range(2.0, 8.0), R.range(0.4, 0.7), C[6], R.range(1.4, 2.2)),
		"onLand": func(q: Dictionary, x: float, y: float, v: float) -> void:
			if v < 110.0:
				return
			ps.spawn(P.VAPOUR, x, y - 1.0, R.range(-20.0, 20.0), -R.range(2.0, 8.0), R.range(0.4, 0.7), C[6], R.range(1.4, 2.4))
			splinter(x, y, q.vx, 3)
			if R.chance(0.3):
				ps.spawn(P.STAR, x, y - 2.0, 0.0, -5.0, R.range(0.2, 0.4), WHITE, R.range(0.8, 1.6)),
	})
	clusters = []
	var x := 10.0
	while x < REACH - 2.0:
		var q := x / REACH
		var H: float = o.height * env(q) * R.range(0.88, 1.06)
		var W := Px.clamp(H * 0.36, 5.0, 14.0)
		var lean := H * R.range(0.2, 0.34)
		# a big blade leaning into the wave, a smaller one behind it leaning further, a stub in front of its foot
		var list := [
			{"dx": W * R.range(0.35, 0.6), "h": H * R.range(0.5, 0.7), "w": W * 0.7, "lean": H * R.range(0.4, 0.6), "back": true, "delay": R.range(0.02, 0.05), "jag": R.range(0.35, 0.6) if R.chance(0.5) else -1.0},
			{"dx": 0.0, "h": H, "w": W, "lean": lean, "back": false, "delay": 0.0, "jag": R.range(0.32, 0.58) if R.chance(0.7) else -1.0, "main": true},
		]
		if H > 14.0:
			list.append({"dx": -W * R.range(0.35, 0.55), "h": H * R.range(0.24, 0.4), "w": W * 0.55, "lean": -H * R.range(0.0, 0.12), "back": false, "delay": R.range(0.03, 0.07), "jag": -1.0})
		clusters.append({"x": x, "q": q, "H": H, "W": W, "blades": list, "main": list[1], "t0": reachedAt(x) + 0.012, "up": false})
		x += R.range(20.0, 26.0)
	crest = clusters.reduce(func(a, c): return c if c.H > a.H else a, clusters[0])


# a blade's base, tip and look right now
func pose(c: Dictionary, b: Dictionary) -> Dictionary:
	var g := Px.Ease.outBack(Px.clamp((t - c.t0 - b.delay) / 0.09), 2.2)
	var x: float = c.x + b.dx
	return {"g": g, "x": x, "tx": x + b.lean * g, "ty": -b.h * g, "white": t - c.t0 - b.delay < 0.03 or (t >= FLASH and t < SHATTER)}


func drawClusters(p: Px.Painter) -> void:
	if t >= SHATTER:
		return
	for pass_: int in [0, 1, 2]:
		for c: Dictionary in clusters:
			if t < c.t0:
				continue
			var jx := (1.0 if (floori(t * 40.0) + Px.roundi(c.x)) % 2 else 0.0) if (t >= TREMBLE and t < FLASH) else 0.0
			for b: Dictionary in c.blades:
				if (pass_ == 0) != b.back or (pass_ == 1) != (true if b.get("main") else false):
					continue
				var s := pose(c, b)
				if s.g <= 0.0:
					continue
				var gl: float = (t - SHIMMER - c.q * 0.34) / 0.2
				Lib.blade(p, s.x + jx, 0.0, s.tx + jx, s.ty, b.w, C, {"white": s.white, "jag": b.jag, "dim": 1.0 if b.back else 0.0, "glint": gl if (gl >= 0.0 and gl <= 1.0) else -1.0})
			if pass_ == 2:
				# light: a pop at the base as it bursts, a cold glow up its length while it stands
				var pop := Px.clamp(1.0 - (t - c.t0) / 0.15)
				var wh := t >= FLASH
				p.glow(c.x + c.main.lean * 0.4, -c.H * 0.45, c.H * 0.9 + 10.0, C[4], (0.16 + 0.42 * pop + (0.4 if wh else 0.0)) * (0.85 + 0.15 * sin(t * 3.0 + c.x)))
				if pop > 0.0:
					p.glow(c.x, -2.0, 14.0, WHITE, 0.55 * pop)


# the frosted floor: a crust with rime tufts, a bloom under the surface, a white-hot head while it runs
func drawFrost(p: Px.Painter) -> void:
	var fr := front(t)
	var x := -3.0
	while x <= minf(fr, REACH + 6.0):
		var q := Px.clamp(x / REACH)
		var age := t - reachedAt(maxf(0.0, x))
		var a := 1.0 - Px.smooth(MELT + q * 0.35, MELT + q * 0.35 + 0.6, t)
		if a <= 0.0 or age < 0.0:
			x += 1.0
			continue
		var h := Px.rand(x, 17)
		var grow := Px.smooth(0.0, 0.3, age)
		var head := fr - x < 3.0 and fr < REACH
		p.dot(x, 0.0, WHITE if (head or age < 0.06 or h < 0.3) else C[6], a)
		var L := Px.round(grow * (1.0 + Px.rand(x, 5) * 2.6)) if h < 0.45 else 0.0
		var j := 1.0
		while j <= L:
			p.dot(x, -j, WHITE if j == L else C[5], a)
			j += 1.0
		if L > 1.0 and Px.rand(x, 9) < 0.5:
			p.dot(x + 1.0, -L + 1.0, C[6], a)
		var D := grow * (2.0 + Px.rand(x, 11) * 4.0) * (1.0 - q * 0.3)
		j = 1.0
		while j <= D:
			p.dot(x, j, WHITE if Px.rand(x * 31.0 + j, 7) < 0.06 else (C[5] if j < 2.0 else (C[4] if j < 4.0 else C[3])), a * (1.1 - j / (D + 1.0)))
			j += 1.0
		if head:
			p.dot(x, -1.0, WHITE)
		x += 1.0
	if fr < REACH and t > START:
		p.glow(fr, -2.0, 16.0, C[6], 0.6)
		p.glow(fr, -1.0, 7.0, WHITE, 0.6)


func breakBlade(c: Dictionary, b: Dictionary) -> void:
	var s := pose(c, b)
	var ax: float = s.tx - s.x
	var ay: float = s.ty
	var L := Px.hypot(ax, ay)
	if not L:
		L = 1.0
	var nx := -ay / L
	var ny := ax / L
	var hw: float = b.w / 2.0
	var tri := [[s.x - nx * hw, -ny * hw], [s.tx, s.ty], [s.x + nx * hw, ny * hw]]
	var ang := atan2(ay, ax) + PI / 2.0
	var parts := [tri]
	if b.h > 9.0:
		var cut := []
		for poly: Array in parts:
			cut.append_array(Lib.splitPoly(poly, s.x + ax * 0.4, ay * 0.4, ang))
		parts = cut
	if b.h > 22.0:
		var cut := []
		for poly: Array in parts:
			cut.append_array(Lib.splitPoly(poly, s.x + ax * 0.72, ay * 0.72, ang) if poly.any(func(pt: Array) -> bool: return pt[1] < ay * 0.5) else [poly])
		parts = cut
	for part: Array in parts:
		var mx := 0.0
		var my := 0.0
		for pt: Array in part:
			mx += pt[0]
			my += pt[1]
		mx /= part.size()
		my /= part.size()
		var up := Px.clamp(-my / 40.0)
		panes.add({
			"pts": part.map(func(pt: Array) -> Array: return [pt[0] - mx, pt[1] - my]), "x": mx, "y": my, "vx": R.range(-25.0, 60.0), "vy": -R.range(40.0, 130.0) * (0.5 + up), "a": 0.0, "va": R.range(-8.0, 8.0), "f": R.range(-0.7, 0.7), "vf": R.range(-6.0, 6.0),
			"lit": 0.45 if b.back else 0.75, "g": 0.9, "drag": 0.6, "bounce": 0.3, "solid": true, "ridge": atan2(ay, ax), "brittle": 2 if b.h > 30.0 else 1, "crumble": R.range(0.12, 0.4), "life": R.range(1.0, 1.4),
		})
	var i := 0
	while i < 2.0 + b.h / 7.0:
		var u := R.next()
		bits.add({"kind": B.CHUNK if R.chance(0.15) else B.SHARD, "x": s.x + ax * u + R.range(-1.5, 1.5), "y": ay * u, "vx": R.range(-60.0, 90.0), "vy": -R.range(60.0, 230.0), "g": 0.9, "drag": 0.6, "bounce": 0.3, "life": R.range(0.7, 1.3), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.2, 3.2), "c": C[R.int_(4, 7)], "ramp": [C[1], C[3], C[4], C[6], C[7]]})
		i += 1


func update(dt: float) -> void:
	t += dt
	# the cast: a puff and a spray where the line starts
	if t - dt <= START and t > START:
		for i in 4:
			ps.spawn(P.VAPOUR, R.range(0.0, 6.0), -R.range(0.0, 3.0), R.range(10.0, 60.0), -R.range(2.0, 12.0), R.range(0.4, 0.7), C[6], R.range(2.0, 3.2))
		lights.add(4.0, -4.0, 26.0, C[5], 0.6, 0.25)
	# the running front throws frost: streaks along the floor, motes, vapour
	var fr := front(t)
	if t > START and fr < REACH - 1.0:
		if R.chance(0.5):
			ps.spawn(P.STREAK, fr - R.range(4.0, 12.0), -R.range(1.0, 3.0), R.range(40.0, 80.0), -R.range(0.0, 6.0), R.range(0.08, 0.14), C[6] if R.chance(0.5) else WHITE)
		if R.chance(0.3):
			ps.spawn(P.FLAKE, fr, -1.0, R.range(10.0, 50.0), -R.range(20.0, 70.0), R.range(0.5, 0.9), WHITE if R.chance(0.5) else C[6], R.range(0.5, 1.2))
		if R.chance(0.12):
			ps.spawn(P.VAPOUR, fr, -R.range(0.0, 3.0), R.range(20.0, 60.0), -R.range(2.0, 10.0), R.range(0.4, 0.7), C[6], R.range(1.6, 2.8))
	for c: Dictionary in clusters:
		if c.up or t < c.t0:
			continue
		c.up = true
		# each cluster bursts up: shards sprayed forward, a puff, motes, a glint at the tip once it stands
		var big := is_same(c, crest)
		var n := 3.0 + Px.round(c.H / 8.0)
		var i := 0
		while i < n:
			var a := -PI / 2.0 + R.range(-1.1, 1.0)
			var sp: float = R.range(60.0, 190.0) * (0.45 + c.H / 44.0)
			bits.add({"kind": B.SHARD, "x": c.x + R.range(-3.0, 3.0), "y": -1.0, "vx": cos(a) * sp + 25.0, "vy": sin(a) * sp, "g": 0.8, "drag": 0.6, "bounce": 0.3, "life": R.range(0.6, 1.1), "a": R.range(0.0, TAU), "va": R.range(-18.0, 18.0), "s": R.range(1.2, 3.0), "c": C[R.int_(5, 7)]})
			i += 1
		ps.spawn(P.VAPOUR, c.x, -1.0, R.range(-10.0, 40.0), -R.range(2.0, 10.0), R.range(0.5, 0.9), C[6], R.range(2.2, 3.4) * (0.6 + c.H / 60.0))
		for k in 2:
			ps.spawn(P.FLAKE, c.x + R.range(-4.0, 4.0), -R.range(2.0, c.H * 0.5), R.range(-20.0, 40.0), -R.range(20.0, 60.0), R.range(0.6, 1.1), WHITE if R.chance(0.5) else C[6], R.range(0.5, 1.3))
		if c.H > 16.0:
			ps.spawn(P.STAR, c.x + c.main.lean, -c.H * 0.96, 0.0, -4.0, R.range(0.3, 0.5), WHITE, R.range(1.4, 2.6), 0.08)
		lights.add(c.x, -c.H * 0.4, 16.0 + c.H * 0.6, C[5], 0.5, 0.18)
		if big:
			lights.add(c.x, -c.H * 0.5, 54.0, WHITE, 0.5, 0.14)
			for k in 4:
				ps.spawn(P.VAPOUR, c.x + R.range(-6.0, 6.0), -R.range(0.0, 4.0), R.range(-40.0, 60.0), -R.range(4.0, 16.0), R.range(0.6, 1.0), C[6], R.range(3.0, 4.5))
	# while they stand: glints wink on the blades
	if t > START + RUN and t < TREMBLE and R.chance(0.09):
		var c: Dictionary = R.pick(clusters)
		var b: Dictionary = R.pick(c.blades)
		var s := pose(c, b)
		var u := R.range(0.3, 0.95)
		ps.spawn(P.STAR, s.x + (s.tx - s.x) * u, s.ty * u, 0.0, -3.0, R.range(0.25, 0.5), WHITE if R.chance(0.6) else C[6], R.range(0.6, 2.0))
	# they shiver: chips fall
	if not trembled and t >= TREMBLE:
		trembled = true
		for c: Dictionary in clusters:
			for i in 2:
				bits.add({"kind": B.SHARD, "x": c.x + R.range(-4.0, 4.0), "y": -R.range(4.0, c.H * 0.8), "vx": R.range(-20.0, 20.0), "vy": -R.range(0.0, 30.0), "g": 0.8, "drag": 0.5, "bounce": 0.3, "life": R.range(0.3, 0.6), "a": R.range(0.0, TAU), "va": R.range(-18.0, 18.0), "s": R.range(1.0, 1.8), "c": C[R.int_(5, 7)]})
	if not broke and t >= SHATTER:
		broke = true
		# all at once: every blade breaks into toppling pieces, splinters and ice dust, light along the line
		for c: Dictionary in clusters:
			for b: Dictionary in c.blades:
				breakBlade(c, b)
			for i in 2:
				ps.spawn(P.VAPOUR, c.x + R.range(-6.0, 6.0), -R.range(1.0, 8.0), R.range(-30.0, 50.0), -R.range(4.0, 18.0), R.range(0.6, 1.1), C[6], R.range(2.4, 4.0) * (0.7 + c.H / 60.0))
			if R.chance(0.7):
				ps.spawn(P.STAR, c.x + R.range(-6.0, 6.0), -R.range(4.0, c.H), R.range(-10.0, 10.0), -R.range(6.0, 20.0), R.range(0.4, 0.8), WHITE if R.chance(0.5) else C[6], R.range(1.0, 2.2))
			for i in 2:
				ps.spawn(P.FLAKE, c.x + R.range(-6.0, 6.0), -R.range(4.0, c.H), R.range(-30.0, 60.0), -R.range(30.0, 90.0), R.range(0.9, 1.5), WHITE if R.chance(0.6) else C[6], R.range(0.5, 1.5))
			lights.add(c.x, -c.H * 0.5, 22.0 + c.H, WHITE, 0.45, 0.12)
		for i in 5:
			lights.add((REACH * (i + 0.5)) / 5.0, -18.0, 40.0, C[4], 0.4, 0.5)
	# the shatter's dust settles; glints on the debris
	if broke and t < SHATTER + 0.8 and R.chance(0.1) and bits.list.size():
		var b: Dictionary = R.pick(bits.list)
		ps.spawn(P.STAR, b.x, b.y - 1.0, 0.0, -3.0, R.range(0.2, 0.4), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.5))
	ps.update(dt)
	bits.update(dt)
	panes.update(dt)
	lights.update(dt)
	Lib.endBy(t, meta.duration, ps, bits, panes)


func drawBack(p: Px.Painter) -> void:
	drawFrost(p)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	drawClusters(p)
	# the cold light the frosted floor gives off
	var k := (1.0 - Px.smooth(MELT, MELT + 0.9, t)) * Px.smooth(START, START + 0.3, t)
	var fr := front(t)
	for i in 6:
		p.glow((fr * (i + 0.5)) / 6.0, -3.0, 26.0, C[4], 0.15 * k)
	if t >= FLASH and t < SHATTER + 0.1:
		for c: Dictionary in clusters:
			Px.sparkle(p, c.x + c.main.lean, -c.H, 6.0 * (1.0 - Px.clamp((t - FLASH) / 0.16)), C[6], C[4], 0.4)
	panes.draw(p, C)
	bits.draw(p)
	ps.draw(p, "front")
	lights.draw(p)
