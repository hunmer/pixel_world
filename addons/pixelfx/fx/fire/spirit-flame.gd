# The layered tongue, its noise-torn edges and the shed puffs are adapted from Sprite Fusion's open-source fire
# (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/spirit-flame.js@1142e5c6e108414e8367ccf6433249bf2db22149
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Spirit flame",
	"desc": "A cold blue-teal ghost fire floating in the air: a bright rim round a hollow dark heart, a wave climbing its wispy tail, curls breaking off, cold sparks rising.",
	"tags": ["fire", "spirit", "ghost", "magic", "cold", "ambient", "loop"],
	"size": [80, 124],
	"origin": [40, 94],
	"duration": 3,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#040a16", "#08203a", "#0b3a52", "#0f5e6e", "#16908e", "#2cc4b4", "#7ef0dc", "#c8fff2", "#ffffff"],
		"seed": 7,
	},
}

static var D: float = meta.duration
static var NL: Callable = Lib.noiseFor(D)
# inverted layers: the rim burns brightest, a teal band inside it, a dark hollow heart, a pale core low down
const GHOST := [[1.0, 1.0, 1], [0.8, 0.92, 3], [0.6, 0.78, 6], [0.3, 0.42, 2], [0.14, 0.22, 0]]


# a tongue whose centre line carries a wave climbing it: drawn row by row in layers like a fire tongue
static func ghostTongue(p: Px.Painter, x: float, y: float, h: float, w: float, centre: Callable, N: Callable, n: Variant, H: Array, layers: Array, jit: float = 0.5) -> void:
	for layer: Array in layers:
		var lw: float = layer[0]
		var lh: float = layer[1]
		var ri: int = layer[2]
		var L := h * lh
		var c: Variant = H[ri]
		for r in floori(L) + 1:
			var u := r / maxf(1.0, L)
			var v := r / h
			# a teardrop: round at the bottom, swelling, then drawn out thin
			var half: float = w * lw * pow(1.0 - u, 0.75) * minf(1.0, (r + 1.5) / 4.0) + N.call(6.0, n, r * 0.4) * jit * u
			if half < 0.3:
				continue
			var cx: float = x + centre.call(v, r)
			var Y := Px.round(y - r)
			var px_ := Px.round(cx - half)
			var x1 := Px.round(cx + half)
			while px_ <= x1:
				p.px(px_, Y, c)
				px_ += 1.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var H := Lib.hotFirst(F)
	var S: float = o.seed
	var ph := t / D
	var N := func(rate: float, seed: Variant = 0, off: float = 0.0) -> float: return NL.call(t, rate, seed, off)
	var COLD := Px.mix(H[3], WHITE, 0.15)
	var bob := sin(ph * TAU) * 1.5
	# the wave: it climbs the flame twice a loop, growing toward the tip, and the whole flame leans with a slow drift
	var lean: float = N.call(0.67, S + 2.0) * 3.0
	var wave := func(v: float, r: float, k: float = 0.0) -> float: return (sin(r * 0.24 - ph * TAU * 2.0 + k) * 2.2 + sin(r * 0.11 - ph * TAU + k * 0.5) * 3.2) * v * v + lean * v * v
	var H0: float = 44.0 * (0.92 + 0.08 * N.call(1.3, S + 3.0))
	var y0 := bob

	# the glow it casts, cold and slow
	var br: float = 0.9 + 0.1 * N.call(2.0, S + 4.0)
	p.glow(0.0, y0 - 16.0, 60.0, COLD, 0.36 * br)
	p.glow(wave.call(0.5, 20.0) * 0.5, y0 - 20.0, 26.0, H[2], 0.2 * br)
	# curls breaking off the tips and drifting up, thinning out
	Lib.looped(t, D, 40, S + 300.0, func(r: Px.Rng) -> Dictionary: return {"x": r.range(-4.0, 4.0), "y": -H0 * r.range(0.55, 0.95), "vx": r.range(-7.0, 7.0), "vy": -r.range(10.0, 22.0), "life": r.range(1.0, 1.9), "s": r.range(1.4, 2.8), "a": r.range(0.0, TAU), "w": r.range(2.0, 3.5)}, func(q: Dictionary, age: float) -> void:
		var xy := Lib.drift(q.x + wave.call(0.9, 26.0, 0.0) * 0.5, q.y + y0, q.vx, q.vy, age, 0.0, -6.0, 1.2, 0.6)
		var x: float = xy[0]
		var y: float = xy[1]
		var k: float = 1.0 - age / q.life
		var cx: float = x + sin(age * q.w + q.a) * 3.0 * (age + 0.2)
		var a := minf(1.0, age * 5.0) * k
		Lib.soft(p, cx, y, q.s * (0.8 + age * 0.8), H[4], 0.35 * a)
		Lib.soft(p, cx - 0.4, y - 0.6, q.s * 0.5 * (0.8 + age * 0.5), H[2], 0.4 * a * k)
		p.glow(cx, y, 6.0, H[3], 0.15 * a))
	# two thin wisps trailing off the sides, then the body
	# side wisps that flicker out and curl, now long, now gone
	var wl := maxf(0.0, 0.25 + 0.55 * N.call(1.7, S + 6.0))
	var wr := maxf(0.0, 0.25 + 0.55 * N.call(1.7, S + 7.0))
	if wl > 0.12:
		ghostTongue(p, -4.0, y0 - 4.0, H0 * wl, 2.4, func(v, r): return wave.call(v, r, 2.1) - 6.0 * v * v + 3.0 * sin(v * 5.0 - ph * TAU * 2.0) * v, N, S * 11.0 + 1.0, H, GHOST)
	if wr > 0.12:
		ghostTongue(p, 4.2, y0 - 4.0, H0 * wr, 2.4, func(v, r): return wave.call(v, r, -1.8) + 6.0 * v * v - 3.0 * sin(v * 5.0 - ph * TAU * 2.0 + 1.0) * v, N, S * 11.0 + 2.0, H, GHOST)
	ghostTongue(p, 0.0, y0, H0, 8.6, func(v, r): return wave.call(v, r), N, S * 11.0, H, GHOST, 0.6)
	# bright strands drifting up through the hollow heart
	for k in [0, 1]:
		var r := 4
		while r < H0 * 0.72:
			var v := r / H0
			var x: float = wave.call(v, r) + sin(r * 0.35 - ph * TAU * 3.0 + k * PI) * 2.2 * (1.0 - v)
			var on := sin(r * 0.2 - ph * TAU * 4.0 + k * 2) > 0.2
			if on:
				p.px(x, y0 - r, H[2] if k else H[1])
			r += 1
	# light along the body
	for v: float in [0.2, 0.45, 0.7]:
		p.glow(wave.call(v, H0 * v), y0 - H0 * v, 12.0, H[2], 0.16 * br)
	# the pale heart breathing low in the flame
	p.glow(0.0, y0 - 4.0, 9.0, H[1], 0.22 + 0.06 * N.call(3.0, S + 5.0))
	# cold sparks rising off it, twinkling
	Lib.looped(t, D, 34, S + 400.0, func(r: Px.Rng) -> Dictionary: return {"x": r.range(-7.0, 7.0), "y": -r.range(4.0, 28.0), "vx": r.range(-12.0, 12.0), "vy": -r.range(14.0, 34.0), "life": r.range(0.9, 1.8), "a": r.range(0.0, TAU)}, func(q: Dictionary, age: float) -> void:
		var xy := Lib.drift(q.x, q.y + y0, q.vx, q.vy, age, 0.0, -10.0, 1.2, 1.2)
		var x: float = xy[0]
		var y: float = xy[1]
		var k: float = 1.0 - age / q.life
		var tw: float = 0.5 + 0.5 * sin(age * 14.0 + q.a)
		var sx: float = x + sin(age * 3.0 + q.a) * 3.0
		if k * (0.4 + 0.6 * tw) < 0.2:
			return
		p.px(sx, y, H[0] if tw > 0.7 and k > 0.5 else (H[1] if k > 0.5 else H[3]))
		if tw > 0.85 and k > 0.6:
			p.px(sx - 1.0, y, H[3])
			p.px(sx + 1.0, y, H[3])
			p.px(sx, y - 1.0, H[3])
			p.px(sx, y + 1.0, H[3])
		p.glow(sx, y, 4.0, H[2], 0.3 * k))
