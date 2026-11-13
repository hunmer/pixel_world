# The beads, drops, drying splats and crowns are
# adapted from Sprite Fusion's open-source blood (https://www.spritefusion.com/pixel-art-vfx/blood),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/status/bleeding.js@5c01160f6e1795dc12704834c34654d1644cef2f
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Bleeding",
	"desc": "Bleeding out: beads swell at three wounds, run, let go and fall to spatter into a glossy pool that ripples; each heartbeat spurts a little and flashes the body red.",
	"tags": ["status", "bleed", "blood", "dot", "debuff", "wound", "loop"],
	"size": [60, 56],
	"origin": [30, 46],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#350711", "#5e0c1b", "#931327", "#c71e33", "#f2384a", "#ff8a7a"], "seed": 5},
}

static var CLUTCH := {"turn": 0.7, "crouch": 3, "lean": 2, "fx": 2, "fy": -21, "bx": 8, "by": -14, "ffx": 3, "fbx": -3}
static var BEAT_ := Px.merge(CLUTCH, {"crouch": 5, "lean": 4, "hy": 1})
static var act := {
	"onBody": true,
	"poses": [[0, BEAT_], [0.18, CLUTCH], [1.2, CLUTCH], [1.2, BEAT_, "snap"], [1.38, CLUTCH], [2.4, CLUTCH], [2.4, BEAT_, "snap"]],
}

static var D: float = meta.duration
static var BEAT := D / 2.0
const G := 900.0

# the wounds: two on the edges of the arms and one on the front of the body. Blood runs down the body from each
# and beads at the end of the run; drops fall in front of the body to the floor
static var WOUNDS := {}
static func wounds(a: Dictionary) -> Array:
	var w: Variant = WOUNDS.get(a.mask.id)
	if w != null:
		return w
	var S := Lib.shape(a)
	var H: int = S.h
	var W: int = S.w
	var on: Callable = S.on
	var ax: int = a.x
	var ay: int = a.y
	var make := func(mx: int, my: int, drops: int, phase: float) -> Dictionary:
		var run := 1
		while run < 3 and on.call(mx, my + run + 1):
			run += 1
		return {"x": ax + mx + 0.5, "mx": mx, "y0": ay + my, "yb": ay + my + run + 1, "drops": drops, "phase": phase, "side": -1 if mx < W / 2.0 else 1}
	var edge := func(q: float, side: int) -> Array:
		var my := Px.roundi(H * q)
		var lr: Array = S.rows[my]
		return [lr[0] + 1 if side < 0 else lr[1] - 1, my]
	var cand: Array = S.body.filter(func(xy): return xy[1] > H * 0.5 and xy[1] < H * 0.62 and xy[0] > W * 0.55 and xy[0] < W * 0.75 and on.call(xy[0], xy[1] + 3))
	var front: Array = cand[0] if cand.size() else edge.call(0.55, 1)
	var e0: Array = edge.call(0.57, -1)
	var e2: Array = edge.call(0.6, 1)
	w = [make.call(e0[0], e0[1], 3, 0.0), make.call(front[0], front[1], 2, 0.35), make.call(e2[0], e2[1], 2, 0.7)]
	WOUNDS[a.mask.id] = w
	return w


# a drop in flight: a bead with a tail when it is fast (Hugo's drop)
static func drop(p: Px.Painter, C: Array, x: float, y: float, v: float, s: int) -> void:
	var tail := minf(5.0, v * 0.012)
	if tail >= 1.0:
		p.line(x, y - tail, x, y - 1.0, C[3] if s >= 2 else C[2])
	if s >= 2:
		p.px(x, y, C[5])
		p.px(x + 1.0, y, C[4])
		p.px(x, y + 1.0, C[3])
		p.px(x + 1.0, y + 1.0, C[2])
	else:
		p.px(x, y, C[4])


# a splat where a drop lands: it spreads, throws a crown of droplets, then dries darker and fades
static func splat(p: Px.Painter, C: Array, x: float, ground: float, age: float, big: bool, seed: int) -> void:
	var life := D * 0.85
	if age < 0.0 or age > life:
		return
	var spread := Px.smooth(0.0, 0.1, age)
	var hw := (2.2 if big else 1.4) * (0.5 + 0.5 * spread)
	var fade := 1.0 - Px.smooth(life - 0.5, life, age)
	var dry := 4 if age < 0.35 else (3 if age < 1.0 else 2)
	for xx in range(floori(x - hw), ceili(x + hw) + 1):
		p.dot(xx, ground - 1.0, C[dry - 1] if absf(xx + 0.5 - x) > hw * 0.75 else C[dry], fade)
	if age < 0.3:
		p.px(x - 0.5, ground - 1.0, C[5])
	# the crown
	if age < 0.4:
		for j in (3 if big else 2):
			var vx := (1.0 if j % 2 else -1.0) * (18.0 + 24.0 * Px.rand(seed, j, 1))
			var vy := -(40.0 + 40.0 * Px.rand(seed, j, 2))
			var tt := age
			var dx := vx * tt
			var dy := vy * tt + 0.5 * G * tt * tt
			if dy <= 0.0:
				p.px(x + dx, ground - 1.0 + dy, C[3] if j else C[4])


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 6)
	var a: Dictionary = o.actor
	var W := wounds(a)
	# the pool under the lowest wounds: dark and glossy, a ripple where each drop lands in it
	var px: float = (W[0].x + W[2].x) / 2.0 - 1.0
	var rx := 6.5
	var beat := exp(-(fmod(fmod(t, BEAT) + BEAT, BEAT) / 0.25))
	for x in range(floori(px - rx - 1.0), floori(px + rx + 1.0) + 1):
		var q := absf(x + 0.5 - px) / rx
		if q > 1.1:
			continue
		p.px(x, -1.0, C[2] if q > 0.85 else C[1])
		if q < 0.8:
			p.px(x, 0.0, C[1] if q < 0.5 else C[0])
		if q < 0.45:
			p.px(x, 1.0, C[0])
	p.px(px - 2.0, -1.0, C[4])
	p.px(px - 1.0, -1.0, C[3])
	p.px(px + 3.0, -1.0, C[3])
	p.glow(px, -1.0, 8.0, C[3], 0.06 + 0.04 * beat)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 6)
	var a: Dictionary = o.actor
	var W := wounds(a)
	var S := Lib.shape(a)
	# each heartbeat flashes the body red for a moment
	var ph := fmod(fmod(t, BEAT) + BEAT, BEAT)
	var hurt := maxf(0.0, 1.0 - ph / 0.12)
	if hurt > 0.0:
		for b: Array in S.body:
			p.blend(a.x + b[0], a.y + b[1], C[4], 0.26 * hurt)
	for w: Dictionary in W:
		# the wound, a dark gash with a wet lip, and the blood running down from it
		p.px(w.x, w.y0 - 1, C[1])
		p.px(w.x - w.side, w.y0 - 1, C[0])
		p.px(w.x - w.side, w.y0, C[2])
		for y in range(w.y0, w.yb):
			p.px(w.x, y, C[4] if y == w.y0 else (C[3] if y >= w.yb - 1 else C[2]))
		# drops: a bead swells, sags, lets go, falls, splats
		var period: float = D / w.drops
		for k in w.drops:
			var born: float = w.phase * period + k * period
			var age := fmod(fmod(t - born, D) + D, D)
			var swell := period * 0.62
			var big: bool = (k + w.mx) % 2 == 0
			var fallH := maxf(1.0, -1.0 - w.yb)
			var fall := sqrt((2.0 * fallH) / G)
			var ground := 0.0
			if age < swell:
				# a bead gathers at the end of the run, sags and stretches
				var u := age / swell
				var len := 1 if u < 0.35 else (2 if u < 0.75 else 3)
				for j in len:
					p.px(w.x, w.yb + j, C[2] if j == len - 1 else C[3])
				if len == 3:
					p.px(w.x - 1, w.yb + 2, C[1])
				p.px(w.x, w.yb + len - 2, C[5] if u > 0.5 else C[4])
			elif age < swell + fall:
				var f := age - swell
				var y: float = w.yb + 2 + 0.5 * G * f * f
				drop(p, C, w.x, y, G * f, 2 if big else 1)
			else:
				splat(p, C, w.x, ground, age - swell - fall, big, w.mx * 31 + k)
	# the heartbeat squeezes a little spurt from the first wound: droplets streak out and fall
	var w: Dictionary = W[0]
	if ph < 0.5:
		for j in 7:
			var vx: float = w.side * (18.0 + 42.0 * Px.rand(j, 7))
			var vy := -(15.0 + 50.0 * Px.rand(j, 8))
			var tt := ph - j * 0.012
			if tt <= 0.0:
				continue
			var x: float = w.x + Lib.travel(vx, 0.0, 1.2, tt)
			var y: float = w.y0 + Lib.travel(vy, G * 0.8, 0.6, tt)
			var x2: float = w.x + Lib.travel(vx, 0.0, 1.2, tt - 0.02)
			var y2: float = w.y0 + Lib.travel(vy, G * 0.8, 0.6, tt - 0.02)
			if y >= -1.0:
				continue
			p.line(x2, y2, x, y, C[3] if j % 3 else C[2])
			p.px(x, y, C[5] if j % 2 else C[4])
	p.glow(w.x, w.y0, 6.0, C[4], 0.25 * hurt)
