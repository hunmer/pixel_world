# The crescent and trace recipe is adapted from Sprite Fusion's open-source slash, and the vapour from his
# ice and poison (https://www.spritefusion.com/pixel-art-vfx), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/scythe-reap.js@9757b43fda2cdacda8d527867172f0a4b7d5899e
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE

static var meta := {
	"name": "Scythe reap",
	"desc": "A slow, huge dark crescent reaps round the front with a pale ghostly edge; it hangs, then tears away from the tail into curling wisps and cold vapour.",
	"tags": ["melee", "scythe", "reap", "dark", "ghost", "death", "slash", "combat", "one-shot"],
	"size": [184, 116],
	"origin": [84, 98],
	"duration": 2.1,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#07040c", "#140a22", "#24113a", "#3b1d58", "#5a3a82", "#7fd6c0", "#d8fff2", "#ffffff"],
		"seed": 13,
	},
}

# the butt rests on the floor in one hand; both hands take it out to the right, and he turns with it round the front
static var REST_ := Px.merge(Px.READY, {"weapon": "scythe", "x": 2, "sa": -1.5, "fx": 11, "fy": -22, "bx": 7, "by": -16})
static var OUT_ := Px.merge(REST_, {"two": true, "crouch": 4, "lean": 4, "fx": 17, "fy": -27, "sa": -0.45, "ffx": 11, "fbx": -8})
static var END := Px.merge(REST_, {"two": true, "x": 0, "yaw": 3.14, "crouch": 6, "lean": 4, "fx": 15, "fy": -24, "sa": 0.3, "ffx": 11, "fbx": -10, "toeB": true})
static var act := {
	"target": {"x": 66},
	"poses": [
		[-0.56, REST_],
		[-0.26, OUT_],
		[0.08, Px.merge(OUT_, {"crouch": 5})],
		[0.2, Px.merge(OUT_, {"yaw": 0.8, "crouch": 5, "lean": 3, "fx": 16, "fy": -23, "sa": 0.1, "ghost": 1})],
		[0.3, Px.merge(OUT_, {"x": 1, "yaw": 1.9, "crouch": 6, "lean": 3, "fx": 15, "fy": -23, "sa": 0.2, "ghost": 1})],
		[0.42, END],
		[0.92, Px.merge(END, {"crouch": 5})],
		[1.3, Px.merge(REST_, {"x": 1, "yaw": 1.4, "crouch": 4})],
		[1.7, REST_],
	],
	"hits": [{"t": 0.14, "stop": 0.12, "shake": 0.16, "amp": 2, "push": 2.4, "straw": 20, "skin": "shadow"}],
	"dust": [{"t": 0.3, "x": 2, "n": 6}],
}

const WIND := 0.08
const SWEEP := 0.34
const HANG := 0.14
const TEAR := 0.55
const T0 := WIND
const T1 := WIND + SWEEP
const T2 := T1 + HANG
const T3 := T2 + TEAR
static func head(t_: float) -> float:
	return Px.Ease.inOutSine(Px.clamp((t_ - T0) / SWEEP))


var C: Array
var Rg: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var A: Dictionary
var W := 21.0
var wisps: Array = []
var t := 0.0
var lastTear := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	Rg = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": Rg, "ground": func(): return 0.0, "haze": C[5]})
	lights = Px.Lights.new()
	# a wide reap from out on the right, round the front of the fighter, to the left
	A = Lib.swing({"cx": 8.0, "cy": -33.0, "R": 52.0, "sy": 0.6, "k": 0.1, "rot": 0.08, "a0": -0.5, "dir": 1.0, "span": 3.5})


# how far the tear has eaten in from the tail (0..1 of the span), ragged by a per-pixel threshold
func tear() -> float:
	return Px.smooth(T2, T3, t)


func addWisp(x: float, y: float, far: bool) -> void:
	wisps.append({"x": x, "y": y, "vx": Rg.range(-12.0, 12.0), "vy": -Rg.range(8.0, 26.0), "life": Rg.range(0.5, 0.9), "max": 0.0, "seed": Rg.range(0.0, 100.0), "pts": [], "far": far})


func update(dt: float) -> void:
	t += dt
	# the cold gathers on the blade before it moves
	if t < WIND and Rg.chance(0.5):
		var xy := Lib.onSwing(A, A.R - 4.0, 0.0)
		ps.spawn(P.VAPOUR, xy[0] + Rg.range(-14.0, 14.0), xy[1] + Rg.range(-8.0, 8.0), Rg.range(-10.0, 10.0), Rg.range(-6.0, 6.0), Rg.range(0.3, 0.5), C[5], Rg.range(1.5, 2.5))
	# the edge sheds a little vapour as it goes
	if t > T0 and t < T1 and Rg.chance(0.5):
		var tr := Lib.travel(A, A.span * head(t) * Rg.range(0.75, 1.0))
		ps.spawn(P.VAPOUR, tr.x, tr.y, tr.dx * 20.0, -Rg.range(4.0, 14.0), Rg.range(0.5, 0.9), C[6], Rg.range(2.0, 3.5), 0.0, PF.BACK if sin(tr.a) < 0.0 else 0)
	# tearing away: wisps peel off where the crescent is coming apart
	var k := tear()
	var u := lastTear
	while u < k * 1.15:
		var uu: float = minf(1.0, u) * A.span
		var tr := Lib.travel(Px.merge(A, {"R": A.R - Rg.range(0.0, 8.0)}), uu)
		var far := sin(tr.a) < 0.0
		addWisp(tr.x, tr.y, far)
		if Rg.chance(0.5):
			ps.spawn(P.VAPOUR, tr.x, tr.y, Rg.range(-10.0, 10.0), -Rg.range(6.0, 18.0), Rg.range(0.55, 0.85), C[5] if Rg.chance(0.5) else C[4], Rg.range(2.5, 4.5), 0.0, PF.BACK if far else 0)
		if Rg.chance(0.2):
			ps.spawn(P.STAR, tr.x + Rg.range(-3.0, 3.0), tr.y + Rg.range(-3.0, 3.0), 0.0, -6.0, Rg.range(0.25, 0.5), C[6] if Rg.chance(0.5) else WHITE, Rg.range(0.6, 1.6), 0.0, PF.BACK if far else 0)
		u += 0.022
	lastTear = maxf(lastTear, k * 1.15)
	# wisps rise, sway and curl, leaving a fading thread behind them
	var i := wisps.size() - 1
	while i >= 0:
		var w: Dictionary = wisps[i]
		w.max += dt
		if w.max > w.life:
			wisps.remove_at(i)
			i -= 1
			continue
		w.vy -= 30.0 * dt
		w.vx += sin(w.max * 9.0 + w.seed) * 120.0 * dt
		w.vx -= w.vx * 2.0 * dt
		w.vy -= w.vy * 1.2 * dt
		w.x += w.vx * dt
		w.y += w.vy * dt
		w.pts.append([w.x, w.y])
		if w.pts.size() > 14:
			w.pts.pop_front()
		i -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	blade(p, -1.0)
	ps.draw(p, "back")
	threads(p, true)


func draw(p: Px.Painter) -> void:
	blade(p, 1.0)
	# the blade's point glints cold as it sets off and where it stops
	if t < WIND + 0.05:
		var xy := Lib.onSwing(A, A.R - 3.0, 0.0)
		Px.sparkle(p, xy[0], xy[1], 6.0 * minf(1.0, t / 0.04) * (1.0 - Px.smooth(WIND - 0.02, WIND + 0.05, t)), C[6], C[5], 0.45)
	var g := t - T1 + 0.06
	if g > 0.0 and g < 0.3:
		var xy := Lib.onSwing(A, A.R - 3.0, A.span)
		Px.sparkle(p, xy[0], xy[1], 9.0 * Px.Ease.outBack(minf(1.0, g / 0.06)) * (1.0 - g / 0.3), C[6], C[5], 0.55)
	ps.draw(p, "front")
	threads(p, false)
	lights.draw(p)


func blade(p: Px.Painter, half: float) -> void:
	var U: float = A.span * head(t)
	var k := tear()
	if U < 0.02 or k >= 1.0:
		return
	var ramp: Array = [C[0], C[0], C[1], C[2], C[3], C[4], C[5], C[6]] if half < 0.0 else C
	var A_ := A
	var W_ := W
	var t_ := t
	Lib.smear(p, A, 0.0, U, W, func(u, r, out, _a):
		var v: float = u / U
		var w := W_ * pow(sin(PI * pow(v, 1.7)), 0.55)
		if w < 0.5:
			return
		var q: float = (A_.R - r) / w
		if q < 0.0 or q > 1.0:
			return
		# torn away from the tail: a ragged front of per-pixel thresholds
		var n := Px.rand(floorf(u * 40.0), floorf(r), 7)
		if k > 0.0 and (u / A_.span) < k * 1.2 - n * 0.2:
			return
		# a pale ghostly rim, a dark body that deepens inward, a faint lit seam
		var ci := 7 if q < 0.08 else (6 if q < 0.16 else (5 if q < 0.25 else (4 if q < 0.4 else (3 if q < 0.62 else 2))))
		out.c = ramp[ci - 1 if (t_ > T1 and q < 0.2) else ci]
		out.a = minf(1.0, v / 0.25), half)
	Lib.glowAlong(p, A, A.R - 2.0, maxf(0.0, k * 1.2 * A.span - 0.3), U, 14.0, C[5], func(u): return 0.3 * (u / U), half, 0.25)


func threads(p: Px.Painter, back: bool) -> void:
	for w: Dictionary in wisps:
		if w.far != back:
			continue
		var life: float = 1.0 - w.max / w.life
		for i in range(1, w.pts.size()):
			var f: float = float(i) / w.pts.size()
			p.line(w.pts[i - 1][0], w.pts[i - 1][1], w.pts[i][0], w.pts[i][1], C[6] if f > 0.75 else (C[5] if f > 0.4 else C[3]), life * (0.3 + 0.7 * f))
		if life > 0.5:
			p.glow(w.x, w.y, 5.0, C[5], 0.25 * life)
