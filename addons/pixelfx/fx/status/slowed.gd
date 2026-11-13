# port-of: src/fx/status/slowed.js@6ca80b739ec54f9acfe7347480042d4fe9e71785
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Slowed",
	"desc": "Dragged through time: a glassy clock dial behind the head ticks round in heavy steps, flashing with each, while drops sink in slow motion and spread slow rings.",
	"tags": ["status", "slow", "time", "clock", "debuff", "loop"],
	"size": [64, 76],
	"origin": [32, 68],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#081a24", "#0e3446", "#165a6e", "#2a8a9a", "#52bcc4", "#9ee6e0", "#e2fff8", "#ffffff"], "seed": 7},
}

static var S1 := {"turn": 0.3, "lean": 3, "crouch": 3, "ffx": 11, "ffy": -5, "fbx": -9, "fby": -5, "toeB": true, "fx": -5, "fy": -19, "bx": 11, "by": -26}
static var S2 := {"turn": 0.3, "lean": 3, "crouch": 3, "ffx": -9, "ffy": -5, "toeF": true, "fbx": 11, "fby": -5, "fx": 13, "fy": -26, "bx": -4, "by": -19}
static var act := {
	"onBody": true,
	"poses": [[0, S1], [1.2, S2], [2.4, S1]],
}

static var D: float = meta.duration
const TICKS := 4
static var STEP := D / TICKS
const R := 18.0


# the hand's angle: it waits, pulls back a little, snaps a quarter turn, overshoots and settles
static func hand(t: float) -> Dictionary:
	var k := floorf(t / STEP)
	var ph := (t - k * STEP) / STEP
	var base := -PI / 2.0 + (k * TAU) / TICKS
	var q := TAU / TICKS
	if ph < 0.62:
		return {"ang": base, "flash": 0.0, "ph": ph}
	if ph < 0.72:
		return {"ang": base - 0.1 * sin(((ph - 0.62) / 0.1) * PI * 0.5), "flash": 0.0, "ph": ph}
	var s := (ph - 0.72) / 0.28
	var snap := Px.Ease.outBack(Px.clamp(s / 0.35), 2.2)
	var wob := Px.exp(-s * 6.0) * sin(s * 22.0) * 0.05
	return {"ang": base - 0.1 * (1.0 - Px.clamp(s / 0.2)) + q * snap + wob, "flash": Px.exp(-s * 5.0), "ph": ph}
# the flash of the last tick, still fading after the hand has settled
static func afterglow(t: float) -> float:
	var s := fmod(fmod(t - STEP * 0.72, STEP) + STEP, STEP)
	return Px.exp(-s * 4.0)


static func dial(p: Px.Painter, C: Array, cx: float, cy: float, t: float) -> void:
	var h := hand(t)
	var fl := maxf(h.flash, afterglow(t))
	# a glassy face, lit from the top left
	p.disc(cx, cy, R - 1.0, C[2], 0.2)
	p.disc(cx - R * 0.25, cy - R * 0.3, R * 0.5, C[4], 0.08)
	# the rim: a dark edge, a bright band, a thin inner line
	p.ring(cx, cy, R + 1.0, 1.0, C[0])
	p.ring(cx, cy, R, 2.0, func(v, ang): return ((C[7] if fl > 0.4 else C[6]) if sin(ang + 0.8) < -0.3 else (C[5] if v > 0.5 else C[4])))
	p.ring(cx, cy, R - 3.5, 1.0, C[3], 0.6)
	# the minute dots, then the hour marks, the quarters longer and brighter
	for i in 60:
		if i % 5 == 0:
			continue
		var a := (i / 60.0) * TAU
		p.dot(cx + cos(a) * (R - 2.6), cy + sin(a) * (R - 2.6), C[4], 0.8)
	for i in 12:
		var a := (i / 12.0) * TAU
		var big := i % 3 == 0
		var r0 := R - 2.5
		var r1 := R - (6.0 if big else 4.5)
		var c := cos(a)
		var s := sin(a)
		p.line(cx + c * r0, cy + s * r0, cx + c * r1, cy + s * r1, C[6] if big else C[5])
	# the hands: a short one that only shudders, a long heavy one that ticks
	var shud: float = h.flash * sin(t * 60.0) * 0.06
	var ha := -PI / 2.0 + 2.2 + shud
	p.beam(cx, cy, cx + cos(ha) * R * 0.5, cy + sin(ha) * R * 0.5, 2.2, C[5])
	var tx: float = cx + cos(h.ang) * (R - 4.0)
	var ty: float = cy + sin(h.ang) * (R - 4.0)
	p.beam(cx, cy, tx, ty, 2.4, func(u): return C[7] if u > 0.8 else C[6])
	p.circle(cx, cy, 2.0, C[6])
	p.px(cx, cy, C[1])
	# light: the face glows, the rim flares as each tick lands, a ripple runs out from it
	p.glow(cx, cy, R + 8.0, C[4], 0.14 + 0.2 * fl)
	p.glowRing(cx, cy, R, 3.0, C[5], 0.12 + 0.35 * fl)
	p.glow(tx, ty, 5.0, C[6], 0.3 + 0.3 * h.flash)
	if h.flash > 0.02:
		var s: float = 1.0 - h.flash
		p.ring(cx, cy, R + 2.0 + 10.0 * s, 1.0, C[5], h.flash)
		p.glowRing(cx, cy, R + 2.0 + 10.0 * s, 3.0, C[4], 0.3 * h.flash)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var a: Dictionary = o.actor
	dial(p, C, 0.0, a.y + 3.0, t)
	# the body lags behind itself: an after-image of its outline, dragged a step back after every tick
	var lag := afterglow(t)
	if lag > 0.05:
		p.outline(a.mask, a.x - 1.0 - Px.round(2.0 * lag), a.y, C[5], 0.55 * lag)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var a: Dictionary = o.actor
	var S := Lib.shape(a)
	var fl := maxf(hand(t).flash, afterglow(t))
	# a cold film of time over the body, thickening with each tick
	for b: Array in S.body:
		p.blend(a.x + b[0], a.y + b[1], C[5], 0.08 + 0.12 * fl)
	# drops sinking in slow motion, ghosts trailing them, slow rings where they reach the floor
	Px.cycle(t, D, 6, o.seed + 3, func(r): return r.range(1.6, 2.2), func(age, life, r):
		var side := -1.0 if r.next() < 0.5 else 1.0
		var x: float = side * r.range(10.0, 17.0)
		var y0: float = a.y + r.range(6.0, 22.0)
		var v0: float = r.range(18.0, 30.0)
		var k := 1.1
		var yAt := func(g: float) -> float: return y0 + (v0 * (1.0 - Px.exp(-k * g))) / k + 4.0 * g
		var y: float = yAt.call(age)
		var u: float = age / life
		if y < -1.0:
			for la: Array in [[0.22, 0.35], [0.11, 0.6]]:
				var lag: float = la[0]
				var al: float = la[1]
				if age > lag:
					p.dot(x, yAt.call(age - lag), C[4], al)
			p.px(x, y - 1.0, C[5])
			p.px(x, y, C[6])
			p.px(x, y + 1.0, C[5])
			p.px(x - 1.0, y + 1.0, C[4])
			p.px(x - 1.0, y, C[7])
			p.glow(x, y, 4.0, C[5], 0.3 * (1.0 - u))
		else:
			# it reached the floor: a slow ring spreads and fades
			var g: float = age
			while g > 0.0 and yAt.call(g) >= -1.0:
				g -= 0.02
			var s := Px.clamp((age - g) / 0.9)
			if s < 1.0:
				# two crests running apart along the floor, a faint far edge behind them
				var rx := 1.0 + 7.0 * sqrt(s)
				var c: int = C[6] if s < 0.3 else C[5]
				for sd: float in [-1.0, 1.0]:
					p.line(x + sd * rx, -0.5, x + sd * (rx - 1.5), -0.5, c, (1.0 - s) * 1.2)
				var dx := -rx + 2.0
				while dx <= rx - 2.0:
					p.dot(x + dx, -1.5, C[4], (1.0 - s) * 0.5 * (1.0 - absf(dx) / rx))
					dx += 1.0
				p.glow(x, -1.0, 4.0 + rx, C[4], 0.12 * (1.0 - s)))
