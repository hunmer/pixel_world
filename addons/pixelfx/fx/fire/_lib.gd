# Shared by the fire effects (the leading _ keeps the tools from listing it as an effect).
# Flame tongues, licks, flame puffs that cool into smoke, embers and sparks, with their motion in closed form so
# looping effects can draw them from t alone and stay seamless. The tongue, lick, puff, smoke, ember and spark
# recipes are adapted from Sprite Fusion's open-source fire (https://www.spritefusion.com/pixel-art-vfx/fire),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/_lib.js@f39107f588c1e887b29e7e7c798bb53b89626531
extends RefCounted

const Px := preload("../../core/px.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE
const SMOKE_RAMP := Px.SMOKE_RAMP


## Smooth value noise in [-1, 1] that repeats every `period` cells (a whole number).
static func pnoise(x: float, period: float, seed: Variant = 0) -> float:
	var i := floorf(x)
	var f := x - i
	var u := f * f * (3.0 - 2.0 * f)
	var a := Px.rand(Px.wrap(i, period), seed)
	var b := Px.rand(Px.wrap(i + 1.0, period), seed)
	return (a + (b - a) * u) * 2.0 - 1.0


## Noise for a loop D seconds long: N.call(tt, rate, seed, off) wobbles about `rate` times a second and is the same at
## tt and tt + D. Pass D = 0 for one-shots (plain noise, no repeat).
static func noiseFor(D: float) -> Callable:
	if not D:
		return func(tt: float, rate: float, seed: Variant = 0, off: float = 0.0) -> float: return Px.noise(tt * rate + off, seed)
	return func(tt: float, rate: float, seed: Variant = 0, off: float = 0.0) -> float:
		var P_ := maxf(1.0, Px.round(rate * D))
		return pnoise((tt / D) * P_ + off, P_, seed)


## Seamless particles for a loop D seconds long: count particles, each born at its own phase and reborn every D.
## make.call(r, i) builds particle i from its own rng (the same every frame) and returns it with a .life (which may
## be longer than D); draw.call(q, age, i) is called for every live copy. Either may take fewer arguments.
static func looped(t: float, D: float, count: float, seed: Variant, make: Callable, draw: Callable) -> void:
	var mn := make.get_argument_count()
	var dn := draw.get_argument_count()
	var i := 0
	while i < count:
		var r := Px.rng(seed, i)
		var born := r.next() * D
		var q: Dictionary = Px.call4(make, mn, r, i)
		var age := Px.wrap(t - born, D)
		while age < q.life:
			Px.call4(draw, dn, q, age, i)
			age += D
		i += 1


## Hugo's flicker, 0.74 to 1: a slow breath and a fast crackle. N(rate, seed) at the current time.
static func flicker(N: Callable, s: float = 0.0) -> float:
	return 0.74 + 0.16 * N.call(7.3, 1.0 + s) + 0.1 * N.call(19.0, 2.0 + s)


## A fire ramp hot-first (H[0] white .. H[8] smouldering) from a palette dark to bright, any length.
static func hotFirst(F: Array) -> Array:
	var H := F.duplicate()
	H.reverse()
	return H


## Tongue layers [width share, height share, step of the hot-first ramp]: red rim, orange, yellow, white heart.
const LAYERS := [[1.0, 1.0, 6], [0.76, 0.86, 4], [0.54, 0.68, 2], [0.3, 0.42, 0]]

## Layers for big tongues: more orange and a smaller white heart, so the light doesn't wash them out.
const BIG_LAYERS := [[1.0, 1.0, 6], [0.8, 0.9, 5], [0.62, 0.78, 4], [0.44, 0.6, 3], [0.26, 0.4, 1], [0.12, 0.22, 0]]

## The same layers a step cooler, for flames further back: dark red rim, deep orange, gold, yellow.
const BACK_LAYERS := [[1.0, 1.0, 7], [0.76, 0.86, 5], [0.54, 0.68, 3], [0.3, 0.42, 2]]


## A flame tongue standing at (x, y), h tall, w its half-width at the base, its tip swept sx px sideways: a red
## rim round orange round yellow round a white heart, every row's width and centre jittered by noise so the
## edges crackle. N.call(rate, seed, off) is the effect's noise at this frame; n seeds this tongue. H: hot-first ramp.
## jit: how far the edges crackle (px); wob: how far the tip wanders (px).
static func flameTongue(p: Px.Painter, x: float, y: float, h: float, w: float, sx: float, N: Callable, n: Variant, H: Array, layers: Array = LAYERS, jit: float = 0.5, wob: float = 1.1) -> void:
	if h < 1.0:
		return
	for layer: Array in layers:
		var lw: float = layer[0]
		var lh: float = layer[1]
		var ri: int = layer[2]
		var L := h * lh
		var c: Variant = H[ri]
		for r in floori(L) + 1:
			var u := r / maxf(1.0, L)
			var half: float = w * lw * pow(1.0 - u, 0.85) * minf(1.0, (r + 1.5) / 3.5) + N.call(9.0, n, r * 0.45) * jit
			if half < 0.3:
				continue
			var cx: float = x + sx * u * u * lh + N.call(4.0, n + 7, r * 0.2) * u * wob
			var Y := Px.round(y - r)
			var px_ := Px.round(cx - half)
			var x1 := Px.round(cx + half)
			while px_ <= x1:
				p.px(px_, Y, c)
				px_ += 1.0


## The same tongue lying along any direction (ux, uy) from its root (x, y): for jets, breath and comet tails.
## len long, w half-width at the root, bend: px the tip is swept sideways (to the left of the direction).
static func flameBlade(p: Px.Painter, x: float, y: float, ux: float, uy: float, len: float, w: float, bend: float, N: Callable, n: Variant, H: Array, layers: Array = LAYERS, jit: float = 0.5, wob: float = 1.1) -> void:
	if len < 1.0:
		return
	var nx := -uy
	var ny := ux
	for layer: Array in layers:
		var lw: float = layer[0]
		var lh: float = layer[1]
		var ri: int = layer[2]
		var L := len * lh
		var c: Variant = H[ri]
		var r := 0.0
		while r <= L:
			var u := r / maxf(1.0, L)
			var half: float = w * lw * pow(1.0 - u, 0.85) * minf(1.0, (r + 1.5) / 3.5) + N.call(9.0, n, r * 0.45) * jit
			if half < 0.3:
				r += 0.5
				continue
			var off: float = bend * u * u * lh + N.call(4.0, n + 7, r * 0.2) * u * wob
			var cx := x + ux * r + nx * off
			var cy := y + uy * r + ny * off
			var q := -half
			while q <= half:
				p.px(cx + nx * q, cy + ny * q, c)
				q += 0.5
			r += 0.5


## A solid disc drawn straight in screen space (fast; a disc looks the same mirrored or turned).
static func solid(p: Px.Painter, x: float, y: float, r: float, c: Variant) -> void:
	if r < 0.6:
		p.px(x, y, c)
		return
	var cx := p.toX(x, y)
	var cy := p.toY(x, y)
	var r2 := r * r
	var sy := floorf(cy - r)
	while sy <= ceilf(cy + r):
		var dy := sy + 0.5 - cy
		var s2 := r2 - dy * dy
		if s2 < 0.0:
			sy += 1.0
			continue
		var s := sqrt(s2)
		var sx := ceilf(cx - s - 0.5)
		while sx <= floorf(cx + s - 0.5):
			p.put(int(sx), int(sy), c, 1.0)
			sx += 1.0
		sy += 1.0


## A translucent disc in screen space: smoke and haze.
static func soft(p: Px.Painter, x: float, y: float, r: float, c: Variant, a: float) -> void:
	if a <= 0.004:
		return
	if r < 0.5:
		p.blend(x, y, c, a)
		return
	var cx := p.toX(x, y)
	var cy := p.toY(x, y)
	var r2 := r * r
	var sy := floorf(cy - r)
	while sy <= ceilf(cy + r):
		var dy := sy + 0.5 - cy
		var s2 := r2 - dy * dy
		if s2 < 0.0:
			sy += 1.0
			continue
		var s := sqrt(s2)
		var sx := ceilf(cx - s - 0.5)
		while sx <= floorf(cx + s - 0.5):
			p.blendPx(int(sx), int(sy), c, a)
			sx += 1.0
		sy += 1.0


## A ball of flame with life left k (1 new, 0 gone) cooling down the hot-first ramp H as it ages: a darker rim,
## a lit core up and to the left, a little tongue on top, a hot heart while it's young, and its light.
## frac (0..1) nudges how hot it starts. (tx, ty): which way its tongue points (up, unless it's streaming).
static func firePuff(p: Px.Painter, x: float, y: float, k: float, size: float, frac: float, H: Array, glowK: float = 0.18, tx: float = 0.0, ty: float = -1.0) -> void:
	var age := 1.0 - k
	var n := H.size()
	var heat := minf(0.999, pow(age, 0.62) + frac * 0.1)
	var idx := mini(n - 2, floori(heat * (n - 1)))
	var r := size * (0.55 + 0.45 * minf(1.0, age * 7.0)) * (1.0 - age * 0.55)
	var c: int = H[idx]
	if idx >= n - 2:
		soft(p, x, y, r, c, minf(1.0, k * 3.0) * 0.85)
		return
	solid(p, x, y, r, H[mini(n - 1, idx + 2)])
	if r > 1.6 and ty > -0.99:
		solid(p, x + tx * r * 1.5, y + ty * r * 1.5, r * 0.3, H[mini(n - 1, idx + 1)])
	solid(p, x - r * 0.16, y - r * 0.22, r * 0.78, c)
	if r > 1.6:
		solid(p, x + tx * r * 0.9, y + ty * r * 0.9, r * 0.42, c)
	if idx <= 3 and r > 1.8:
		solid(p, x - r * 0.28, y - r * 0.34, r * 0.36, H[maxi(0, idx - 1)])
	if idx < 6:
		p.glow(x, y, r * 2.4 + 2.0, c, glowK * k)


## A lick: a blob of flame torn off a tongue's tip, a red rim round a yellow heart, shrinking as it rises.
static func lick(p: Px.Painter, x: float, y: float, k: float, s: float, H: Array) -> void:
	var r := s * (0.4 + 0.6 * k)
	solid(p, x, y, r + 0.6, H[5] if k > 0.5 else H[6])
	if k > 0.35:
		solid(p, x, y - 0.3, r * 0.6, H[2] if k > 0.7 else H[4])


static func rampAt(r: Array, t: float) -> int:
	return r[mini(r.size() - 1, maxi(0, floori(t * r.size())))]


## A puff of smoke with life left k: three soft discs (a body, a denser core sitting low, a lit cap while it's
## young), swelling and thinning. col tints it (0 for plain smoke); big for slower, fuller smoke.
static func smokePuff(p: Px.Painter, x: float, y: float, k: float, size: float, col: int = 0, big: bool = false, aMul: float = 1.0) -> void:
	var age := 1.0 - k
	var r := size * (0.65 + minf(1.0, age * 2.5) * 0.45 + age * (0.5 if big else 0.4))
	var a := minf(1.0, age * 12.0) * minf(1.0, k * 2.4) * (0.7 if big else 0.58) * aMul
	var c := Px.mix(col, rampAt(SMOKE_RAMP, age), age) if col else rampAt(SMOKE_RAMP, age * 1.05)
	soft(p, x, y, r, c, a * 0.45)
	soft(p, x + r * 0.05, y + r * 0.06, r * 0.74, c, a * 0.62)
	if age < 0.5:
		soft(p, x - r * 0.22, y - r * 0.3, r * 0.5, Px.mix(c, WHITE, 0.12), a * 0.4 * (1.0 - age * 2.0))


## An ember with life left k: a hot pixel cooling through cols [hot, warm, cool, rim], flickering out near the
## end (ph: its flicker phase), with its own light. Big ones (size 2) are a little cross with a darker rim.
static func ember(p: Px.Painter, x: float, y: float, k: float, size: float, cols: Array, ph: float) -> void:
	if k < 0.25 and sin(ph) < 0.0:
		return
	var c: int = cols[0] if k > 0.6 else (cols[1] if k > 0.3 else cols[2])
	if size >= 2.0:
		var rim: int = cols[2] if k > 0.45 else cols[3]
		p.px(x - 1.0, y, rim)
		p.px(x + 1.0, y, rim)
		p.px(x, y - 1.0, rim)
		p.px(x, y + 1.0, rim)
		p.px(x, y, c)
		p.glow(x, y, 8.0, c, 0.4 * k)
		return
	p.px(x, y, c)
	if size > 1.4:
		p.px(x, y + 1.0, cols[3])
	p.glow(x, y, 3.0 + size, c, 0.35 * k)


## A spark: a streak stretched along its velocity, a hot head and a cooler tail, and a point of light.
static func spark(p: Px.Painter, x: float, y: float, vx: float, vy: float, k: float, cols: Array) -> void:
	var sp := Px.hypot(vx, vy)
	if not sp or is_nan(sp):
		sp = 1.0
	var ux := vx / sp
	var uy := vy / sp
	var len := minf(9.0, 1.0 + sp * 0.022)
	var head: int = cols[0] if k > 0.6 else (cols[1] if k > 0.3 else cols[2])
	p.line(x - ux * len, y - uy * len, x - ux * len * 0.4, y - uy * len * 0.4, head if k > 0.5 else cols[cols.size() - 1])
	p.line(x - ux * len * 0.45, y - uy * len * 0.45, x, y, head)
	p.glow(x, y, 3.0, head, 0.45 * k)


static func along(x: float, v: float, a: float, k: float, t: float) -> Array:
	if k <= 0.0:
		return [x + v * t + 0.5 * a * t * t, v + a * t]
	var e := exp(-k * t)
	var vt := a / k
	return [x + vt * t + ((v - vt) * (1.0 - e)) / k, vt + (v - vt) * e]


## Where a body is t seconds after launch from (x, y) at (vx, vy), under acceleration (ax, ay) px/s² and linear
## drag kx, ky (1/s): [x, y, vx, vy]. The particle kinds' own numbers: FIRE (0, -95, 5, 3.2), SMOKE
## (0, -16, 1.6, 1.2), EMBER (0, -30, 1.6, 1.6), SPARK (0, 427, 2.2, 2.2).
static func drift(x: float, y: float, vx: float, vy: float, t: float, ax: float, ay: float, kx: float, ky: float) -> Array:
	var X := along(x, vx, ax, kx, t)
	var Y := along(y, vy, ay, ky, t)
	return [X[0], Y[0], X[1], Y[1]]


## A spark's flight: falls, drags, and bounces off the floor at y = floor, losing speed each time.
static func sparkAt(x: float, y: float, vx: float, vy: float, t: float, floor_: float = 0.0, g: float = 427.0, k: float = 2.2) -> Array:
	var s := [x, y, vx, vy]
	var left := t
	for b in 3:
		var e := drift(s[0], s[1], s[2], s[3], left, 0.0, g, k, k)
		if e[1] < floor_ or s[1] >= floor_:
			return e
		var lo := 0.0
		var hi := left
		for i in 16:
			var m := (lo + hi) / 2.0
			if drift(s[0], s[1], s[2], s[3], m, 0.0, g, k, k)[1] < floor_:
				lo = m
			else:
				hi = m
		var c := drift(s[0], s[1], s[2], s[3], hi, 0.0, g, k, k)
		s = [c[0], floor_ - 0.25, c[2] * 0.7, -absf(c[3]) * 0.45]
		left -= hi
	var e := drift(s[0], s[1], s[2], s[3], left, 0.0, g, k, k)
	return e if e[1] < floor_ else [e[0], floor_ - 0.25, e[2], 0.0]


## A pool of light on the floor: an ellipse of glow, k at its middle falling to 0 at its rim.
static func floorLight(p: Px.Painter, x: float, y: float, rx: float, ry: float, c: int, k: float) -> void:
	if k <= 0.004 or rx < 1.0 or ry < 0.5:
		return
	p.shade(x - rx, y - ry, x + rx, y + ry, func(px_, py, out):
		var dx: float = (px_ - x) / rx
		var dy: float = (py - y) / ry
		var d := dx * dx + dy * dy
		if d >= 1.0:
			return
		var f := 1.0 - sqrt(d)
		out.l = c
		out.k = f * f * k)


## A core Particles system drawn with its flame puffs recoloured down the hot-first ramp H (the core draws them
## in its own fire colours): smoke and back particles, then the flames, then sparks and the rest on top.
static func simDraw(p: Px.Painter, ps: Px.Particles, H: Array, layer: String) -> void:
	var all: Array = ps.list
	var rest := []
	var fire := []
	for q: Dictionary in all:
		(fire if q.k == P.FIRE else rest).append(q)
	ps.list = rest
	if layer != "front":
		ps.draw(p, "back")
		_puffs(p, fire, H, true)
	if layer != "back":
		_puffs(p, fire, H, false)
		ps.draw(p, "front")
	ps.list = all


# simDraw's puffs(back)
static func _puffs(p: Px.Painter, fire: Array, H: Array, back: bool) -> void:
	for q: Dictionary in fire:
		if q.delay <= 0.0 and bool(q.flag & PF.BACK) == back:
			firePuff(p, q.x, q.y, q.life / q.max, q.size, fmod(q.seed, 1.0), H)


static var SMOKE1 := Px.hex("#5b5566")


## A fire for loops, drawn from t alone. Tongues T: [[dx, dy, height share, half-width, back row?], ...] from the
## base (o.x, o.y), back row first then outer to inner; licks torn off their tips, flame puffs that burn out into
## smoke, a smoke plume curling off with the draught, embers, and the fire's light.
## o: { H, D, NL (noiseFor(D)), S (seed), height, lean, rates per second: puffs and licks (per tongue), smoke,
## embers; spread (how wide embers and smoke leave), glow (light strength), glowR, mid() (called after the
## tongues, before what flies off them: draw what the fire burns out of there) }. Wide tongues get BIG_LAYERS.
## Returns { tip(i, tt), fl (this frame's flicker) }.
static func burn(p: Px.Painter, t: float, T: Array, o: Dictionary) -> Dictionary:
	var H: Array = o.H
	var D: float = o.D
	var NL: Callable = o.NL
	var S: float = o.S
	var HC: float = o.height
	var X: float = o.get("x", 0.0)
	var Y: float = o.get("y", 0.0)
	var W: float = o.get("spread", 6.0)
	var G: float = o.get("glow", 1.0)
	var N := func(rate: float, seed: Variant = 0, off: float = 0.0) -> float: return NL.call(t, rate, seed, off)
	var fla := func(tt: float) -> float: return 0.74 + 0.16 * NL.call(tt, 7.3, S + 1.0) + 0.1 * NL.call(tt, 19.0, S + 2.0)
	var fl: float = fla.call(t)
	var SMOKE := Px.mix(SMOKE1, H[6], 0.25)
	var EMB := [H[1], H[2], H[4], H[6]]
	var GLOW := Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.25)
	var R := Px.rng(S, 77)
	var count := func(rate: float) -> float: return Px.round(rate * D)
	var TT := []
	for i in T.size():
		var dx: float = T[i][0]
		var dy: float = T[i][1]
		var h: float = T[i][2]
		var w: float = T[i][3]
		var back: Variant = T[i][4]
		TT.append({"dx": dx + R.range(-0.3, 0.3), "y": dy, "h": 2.0 + HC * h * R.range(0.92, 1.08), "w": w * R.range(0.92, 1.08), "back": back, "env": h, "n": (S * 7.0 + i) * 13.0})
	var oLean: float = o.get("lean", 0.1)
	var lean := func(tt: float) -> float: return NL.call(tt, 0.67, S + 90.0) * oLean
	var height := func(i: int, tt: float) -> float:
		var h: float = TT[i].h
		var n: float = TT[i].n
		var leap: float = maxf(0.0, NL.call(tt, 2.6, n + 70.0) - 0.55) * 1.4
		return (h + 0.25 * h * NL.call(tt, 3.3, n) + h * leap) * (0.9 + 0.1 * fla.call(tt))
	var sweep := func(i: int, tt: float, h: float) -> float: return NL.call(tt, 2.2, TT[i].n + 40.0) * (1.0 + h * 0.08) + lean.call(tt) * h * 0.9 - Px.clamp(TT[i].dx * 0.3, -2.5, 2.5)
	var tip := func(i: int, tt: float) -> Array:
		var h: float = height.call(i, tt)
		return [X + TT[i].dx + sweep.call(i, tt, h) * 0.85, Y + TT[i].y - h * 0.88 + 3.0, h]
	var tongueAt := func(i: int) -> void:
		var dx: float = TT[i].dx
		var y: float = TT[i].y
		var w: float = TT[i].w
		var n: float = TT[i].n
		var back: Variant = TT[i].back
		var h: float = height.call(i, t)
		flameTongue(p, X + dx, Y + y, h, w, sweep.call(i, t, h), N, n, H, BACK_LAYERS if back else (BIG_LAYERS if w > 2.2 else LAYERS), 0.5, 1.1 + h * 0.04)

	# the plume: each puff keeps the sway the plume had when it left, so the wiggle climbs it
	var smokeLife: Array = o.get("smokeLife", [1.6, 2.6])
	var smokeSize: float = o.get("smokeSize", 3.0)
	var wind: float = o.get("wind", 3.0)
	looped(t, D, count.call(o.get("smoke", 12.0)), S + 300.0, func(r: Px.Rng) -> Dictionary: return {"x": r.range(-W, W) * 0.7, "y": -HC * 0.8 - r.range(0.0, 6.0), "vx": r.range(-2.0, 2.0), "vy": -r.range(10.0, 17.0), "life": r.range(smokeLife[0], smokeLife[1]), "s": r.range(0.7, 1.1) * smokeSize}, func(q: Dictionary, age: float) -> void:
		var xy := drift(q.x, q.y, q.vx, q.vy, age, wind, -20.0, 1.6, 1.0)
		smokePuff(p, X + xy[0] + NL.call(t - age, 0.8, S + 60.0) * (1.5 + 2.5 * age), Y + xy[1], 1.0 - age / q.life, q.s, SMOKE))
	# flame puffs shed from the tips
	var puffs := []
	looped(t, D, TT.size() * count.call(o.get("puffs", 8.0)), S + 200.0, func(r: Px.Rng, j: int) -> Dictionary:
		var i := j % TT.size()
		var fire := r.range(0.14, 0.3)
		var smokes := r.chance(0.45)
		return {"i": i, "fire": fire, "smokes": smokes, "sl": r.range(0.8, 1.4), "ox": r.range(-1.0, 1.0), "oy": r.range(0.0, 4.0), "vx": r.range(-4.0, 4.0), "vy": -r.range(15.0, 30.0), "s": r.range(0.8, 1.6) * (0.8 + 0.6 * TT[i].env), "f": r.next(), "life": fire + (1.4 if smokes else 0.0)}, func(q: Dictionary, age: float) -> void:
		var txy: Array = tip.call(q.i, t - age)
		var e := drift(txy[0] + q.ox, txy[1] + q.oy, q.vx, q.vy, minf(age, q.fire), 0.0, -95.0, 5.0, 3.2)
		if age < q.fire:
			puffs.append([e[0], e[1], 1.0 - age / q.fire, q.s, q.f])
			return
		if age - q.fire > q.sl:
			return
		var sxy := drift(e[0], e[1], e[2] * 0.6, e[3] * 0.6 - 6.0, age - q.fire, wind, -16.0, 1.6, 1.2)
		smokePuff(p, sxy[0], sxy[1], 1.0 - (age - q.fire) / q.sl, q.s * 0.7, 0))
	for i in TT.size():
		if TT[i].back:
			tongueAt.call(i)
	for i in TT.size():
		if not TT[i].back:
			tongueAt.call(i)
	var mid: Variant = o.get("mid")
	if mid is Callable:
		Px.call4(mid, mid.get_argument_count(), fl)
	# licks torn off the tips, rising and shrinking
	looped(t, D, TT.size() * count.call(o.get("licks", 4.0)), S + 220.0, func(r: Px.Rng, j: int) -> Dictionary: return {"i": j % TT.size(), "vx": r.range(-3.0, 3.0), "vy": -r.range(12.0, 22.0), "s": r.range(0.9, 1.6) * (0.8 + 0.5 * TT[j % TT.size()].env), "life": 0.26}, func(q: Dictionary, age: float) -> void:
		var txy: Array = tip.call(q.i, t - age)
		lick(p, txy[0] + q.vx * age, txy[1] - 2.0 + q.vy * age, 1.0 - age / q.life, q.s, H))
	for pf: Array in puffs:
		firePuff(p, pf[0], pf[1], pf[2], pf[3], pf[4], H)
	# embers carried up by the heat, wandering and cooling
	looped(t, D, count.call(o.get("embers", 8.0)), S + 500.0, func(r: Px.Rng) -> Dictionary: return {"x": r.range(-W, W), "y": -r.range(HC * 0.3, HC * 0.8), "vx": r.range(-15.0, 15.0), "vy": -r.range(25.0, 60.0), "life": r.range(1.1, 2.4), "s": 2.0 if r.chance(0.15) else r.range(1.0, 1.6), "a": r.range(0.0, 6.3), "b": r.range(0.0, 6.3)}, func(q: Dictionary, age: float) -> void:
		var xy := drift(q.x, q.y, q.vx, q.vy, age, 0.0, -30.0, 1.6, 1.6)
		ember(p, X + xy[0] + 7.0 * (sin(age * 2.3 + q.a) - sin(q.a)), Y + xy[1] + 2.0 * (sin(age * 3.0 + q.b) - sin(q.b)), 1.0 - age / q.life, q.s, EMB, age * 40.0 + q.a))
	# light: a broad warm wash, lights on the flames, a hot heart at the base
	if G > 0.0:
		var R1: float = o.get("glowR", 46.0)
		var lx: float = X + lean.call(t) * 12.0
		p.glow(lx, Y - HC * 0.35, R1 * 1.5, GLOW, 0.22 * fl * G)
		p.glow(lx, Y - HC * 0.75, R1, GLOW, 0.34 * fl * G)
		p.glow(X, Y - HC * 0.2, R1 * 0.32, H[2], 0.2 * fl * G)
		p.glow(X, Y - 2.0, 8.0, H[0], 0.14 * fl * G)
	return {"tip": tip, "fl": fl}
