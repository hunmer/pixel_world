# The pop's star and slivers follow Sprite Fusion's open-source impact, and the sparks his slash
# (https://www.spritefusion.com/pixel-art-vfx), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/whip-crack.js@92794f205ad2aa49b6e98a0abc48152570b98ec7
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Whip crack",
	"desc": "A whip rolls out to the right as a loop running down its length, faster and faster, until the tip flips over and cracks: a white pop, a ring of air, sparks and a puff of smoke.",
	"tags": ["melee", "whip", "crack", "lash", "combat", "directional", "one-shot"],
	"size": [192, 80],
	"origin": [30, 68],
	"duration": 0.85,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#2a1a10", "#5c3a1e", "#9c6a34", "#d8a45a", "#ffd890", "#fff4d6", "#ffffff"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"length": 76,
		"seed": 3,
	},
}

static var STANCE := Px.merge(Px.READY, {"weapon": "handle", "x": -7, "sa": -0.3, "fx": 13, "fy": -21, "bx": 7, "by": -18})
static var COCK := Px.merge(STANCE, {"crouch": 4, "lean": -3, "fx": -6, "fy": -38, "sa": -2.2, "bx": 9, "by": -23, "armsFront": true, "ffx": 9, "fbx": -7})
static var CRACK_ := Px.merge(STANCE, {"crouch": 4, "lean": 5, "fx": 18, "fy": -21, "sa": 0, "bx": -8, "by": -23, "ffx": 12, "fbx": -10, "toeB": true})
static var act := {
	"target": {"x": 94},
	"poses": [
		[-0.46, STANCE],
		[-0.22, COCK],
		[0.02, Px.merge(COCK, {"lean": -4})],
		[0.06, Px.merge(CRACK_, {"fx": 15, "fy": -34, "sa": -0.7, "lean": 2, "ghost": 1}), "snap"],
		[0.12, CRACK_, "snap"],
		[0.21, CRACK_],
		[0.26, Px.merge(CRACK_, {"fx": 15, "fy": -27, "sa": -0.3, "lean": 2, "crouch": 3}), "snap"],
		[0.44, Px.merge(CRACK_, {"fx": 17, "fy": -22, "sa": 0.1, "lean": 3, "crouch": 3})],
		[0.92, STANCE],
	],
	"hits": [{"t": 0.21, "stop": 0.1, "shake": 0.14, "amp": 2, "push": 2.4, "straw": 14, "y": -28}],
	"dust": [{"t": 0.06, "x": 2, "n": 4, "dir": 1}],
}

const ROLL0 := 0.02  # the loop runs out; the tip cracks when it gets there
const ROLL := 0.19
const CRACK := ROLL0 + ROLL
const RECOIL := 0.16


var C: Array
var Rg: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var L: float
var HX := 11.0
var HY := -21.0
var TIP: Array
var spikes: Array
var slivers: Array
var t := 0.0
var cracked := false
var tipTrail: Array = []


# how far down the whip the loop has run: it starts a third of the way out, cocked, and accelerates
func lam(t_: float) -> float:
	return L * (0.34 + 0.66 * Px.Ease.inQuad(Px.clamp((t_ - ROLL0) / ROLL)))


# the whip as points, handle to tip: straight out to the loop, round the loop, folded back under it
func shape(t_: float) -> Array:
	var l := lam(t_)
	var r := 6.5 - 3.5 * (l / L)
	var pts := []
	var recoil := Px.smooth(CRACK + 0.04, CRACK + 0.04 + RECOIL, t_)
	var len_ := L * (1.0 - recoil * 0.85)
	var s := 0.0
	while s <= len_:
		var x: float
		var y: float
		if s <= l:
			x = HX + s
			y = HY - sin((PI * s) / maxf(l, 1.0)) * 2.5 * (1.0 - l / L)
		elif s <= l + PI * r:
			var th := (s - l) / r
			x = HX + l + sin(th) * r
			y = HY + r - cos(th) * r
		else:
			x = HX + l - (s - l - PI * r)
			y = HY + 2.0 * r
		# after the crack it sags as it's pulled back in
		if recoil > 0.0:
			y += sin((PI * s) / L) * 6.0 * recoil
		pts.append([x, y])
		s += 1.0
	return pts


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	Rg = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": Rg, "ground": func(): return 0.0, "sparks": o.sparks})
	lights = Px.Lights.new()
	L = o.length
	TIP = [HX + L, HY - 1.0]
	spikes = []
	var as_ := [0.0, 0.8, 1.6, 2.4, 3.14, 3.9, 4.7, 5.5]
	for i in as_.size():
		var a: float = as_[i]
		spikes.append({"a": a + Rg.range(-0.15, 0.15), "len": (13.0 if i == 0 else (6.0 if i % 2 else 9.0)) + Rg.range(0.0, 3.0), "w": 1.4 + Rg.range(0.0, 0.5)})
	slivers = [-1.2, -0.3, 0.5, 1.3].map(func(a): return {"a": a + Rg.range(-0.2, 0.2), "r": Rg.range(4.0, 6.0), "v": Rg.range(80.0, 120.0), "arc": Rg.range(0.4, 0.7)})


func update(dt: float) -> void:
	t += dt
	if t > CRACK - 0.05 and t < CRACK + 0.01:
		var pts := shape(t)
		tipTrail.append({"p": pts[pts.size() - 1], "t": t})
	var i := tipTrail.size() - 1
	while i >= 0:
		if t - tipTrail[i].t > 0.06:
			tipTrail.remove_at(i)
		i -= 1
	if not cracked and t >= CRACK:
		cracked = true
		lights.add(TIP[0], TIP[1], 46.0, C[4], 0.6, 0.3)
		lights.add(TIP[0], TIP[1], 14.0, WHITE, 0.8, 0.07)
		for j in 16:
			var a := Rg.range(-1.3, 1.2)
			var sp := Rg.range(130.0, 300.0)
			ps.spawn(P.SPARK, TIP[0], TIP[1], cos(a) * sp, sin(a) * sp - 40.0, Rg.range(0.12, 0.36))
		for j in 3:
			ps.spawn(P.SMOKE, TIP[0] + Rg.range(-2.0, 3.0), TIP[1] + Rg.range(-2.0, 2.0), Rg.range(10.0, 40.0), -Rg.range(6.0, 18.0), Rg.range(0.5, 0.8), C[2], Rg.range(2.5, 4.0), Rg.range(0.02, 0.06))
		for j in 4:
			ps.spawn(P.STAR, TIP[0] + Rg.range(-8.0, 10.0), TIP[1] + Rg.range(-8.0, 8.0), 0.0, -3.0, Rg.range(0.2, 0.4), C[5] if Rg.chance(0.5) else WHITE, Rg.range(0.8, 1.8), Rg.range(0.05, 0.2))
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	var end := CRACK + 0.04 + RECOIL
	if t < end:
		var fade := 1.0 - Px.smooth(end - 0.06, end, t)
		# afterimages of the whip a beat and two beats back: the loop's motion
		if t < CRACK:
			for lca: Array in [[0.03, C[1], 0.5], [0.015, C[2], 0.7]]:
				var lag: float = lca[0]
				var c: int = lca[1]
				var a: float = lca[2]
				var old := shape(maxf(0.0, t - lag))
				var i := 1
				while i < old.size():
					p.dot(old[i][0], old[i][1], c, a)
					i += 2
		# the whip: thicker and lit near the handle, a single line to the tip
		var pts := shape(t)
		var n := pts.size()
		var l := lam(t)
		var r := 6.5 - 3.5 * (l / L)
		for i in range(1, n):
			var x0: float = pts[i - 1][0]
			var y0: float = pts[i - 1][1]
			var x1: float = pts[i][0]
			var y1: float = pts[i][1]
			var u := float(i) / n
			var s := float(i)
			# the loop's leading half is moving fastest: it runs hot
			var inLoop := t < CRACK and s > l and s < l + PI * r
			var lead := inLoop and absf(s - l - (PI * r) / 2.0) < r * 0.9
			p.line(x0, y0, x1, y1, WHITE if lead else (C[5] if inLoop else (C[4] if u < 0.5 else C[3])), fade)
			if u < 0.4:
				p.line(x0, y0 + 1.0, x1, y1 + 1.0, C[2], fade)
		# the running loop is the fastest part: it shines
		if t < CRACK:
			var l2 := lam(t)
			var r2 := 6.5 - 3.5 * (l2 / L)
			p.glow(HX + l2 + r2, HY + r2, 12.0, C[4], 0.4)
	# the tip's path just before the crack: a white-hot streak
	for i in range(1, tipTrail.size()):
		var k: float = 1.0 - (t - tipTrail[i].t) / 0.06
		p.line(tipTrail[i - 1].p[0], tipTrail[i - 1].p[1], tipTrail[i].p[0], tipTrail[i].p[1], WHITE if k > 0.6 else C[5], k)
	# the crack: a white pop, a ring of air, slivers
	var q := t - CRACK
	if q >= 0.0 and q < 0.035:
		Lib.star(p, TIP[0], TIP[1], spikes, 1.0, 1.0, WHITE, C[5], C[6], C[4])
	elif q >= 0.035 and q < 0.07:
		Lib.star(p, TIP[0], TIP[1], spikes, 1.3, 0.5, C[6], C[5], C[5], C[3])
	if q >= 0.02 and q < 0.2:
		var k := (q - 0.02) / 0.18
		var r := 4.0 + 16.0 * Px.Ease.outCubic(k)
		var th := maxf(1.0, 2.2 * (1.0 - k))
		var col: int = WHITE if k < 0.25 else (C[5] if k < 0.5 else (C[4] if k < 0.75 else C[3]))
		var a := 0.0
		while a < TAU:
			var o := 0.0
			while o < th:
				p.dot(TIP[0] + cos(a) * (r - o), TIP[1] + sin(a) * (r - o) * 0.8, col, 1.15 - k)
				o += 0.5
			a += 0.6 / r
		p.glow(TIP[0], TIP[1], r + 6.0, C[4], 0.25 * (1.0 - k))
	if q >= 0.04 and q < 0.16:
		var k := (q - 0.04) / 0.12
		for s: Dictionary in slivers:
			Lib.sliver(p, TIP[0], TIP[1], s.a, s.r + s.v * (q - 0.04), s.arc * (1.0 - 0.4 * k), C[6] if k < 0.4 else C[5], 1.0 - k)
	if q >= 0.0 and q < 0.15:
		p.glow(TIP[0], TIP[1], 26.0, C[5], 0.7 * exp(-q / 0.04))
	ps.draw(p)
	lights.draw(p)
