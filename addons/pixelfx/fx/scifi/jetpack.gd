# The exhaust (flame puffs cooling down the fire ramp into smoke, a warm light over the smoke) follows Sprite
# Fusion's open-source fire (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/scifi/jetpack.js@922e0d1df966cbb7758a494d6c11cda60c9b4c7b
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE

static var meta := {
	"name": "Jetpack",
	"desc": "Twin thrusters fire straight down: white-hot cores with shock diamonds inside ragged flames, puffs that cool into smoke billowing below, lit by the fire.",
	"tags": ["scifi", "jetpack", "thrust", "rocket", "fire", "smoke", "flight", "loop"],
	"size": [96, 116],
	"origin": [48, 30],
	"duration": 2,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#2a0e12", "#5c1818", "#a02818", "#e0501a", "#ff8a2a", "#ffc23d", "#fff3a6", "#ffffff"],
		"metal": ["#0e0d14", "#1e1c27", "#312e3e", "#4b4759", "#6f6a82", "#9d98b0"],
		"length": 26,
		"seed": 30,
	},
}

static var D: float = meta.duration
const GAP := 8.0
const FR := 30

static var cache := {}


static func ghosts(o: Dictionary, F: Array) -> Lib.Ghosts:
	var key := "%s:%s:%s" % [o.seed, o.palette, o.length]
	if cache.has(key):
		return cache[key]
	var rn := Px.Rng.new(o.seed)
	var L: float = o.length
	var g := Lib.Ghosts.new(D, {"sparks": [WHITE, F[6], F[5], F[4]], "box": [-46.0, -28.0, 46.0, 84.0]})
	for s: float in [-1.0, 1.0]:
		# flame shed off the tip, cooling down the ramp into smoke that's driven down, slows and billows
		for i in 26:
			g.add(rn.range(0.0, D), P.FIRE, s * GAP + rn.range(-1.5, 1.5), L * rn.range(0.55, 0.85), rn.range(-10.0, 10.0), rn.range(70.0, 130.0), rn.range(0.22, 0.4), 0, rn.range(2.2, 3.4), PF.SMOKES | (PF.BIG if rn.chance(0.5) else 0))
		for i in 10:
			g.add(rn.range(0.0, D), P.SMOKE, s * GAP + rn.range(-3.0, 3.0), L + rn.range(2.0, 8.0), s * rn.range(0.0, 14.0), rn.range(40.0, 80.0), rn.range(1.1, 1.6), 0, rn.range(3.0, 5.0), PF.BIG)
		# sparks spat out of the exhaust, embers drifting off it
		for i in 10:
			g.add(rn.range(0.0, D), P.SPARK, s * GAP + rn.range(-1.0, 1.0), L * rn.range(0.3, 0.7), s * rn.range(-40.0, 60.0), rn.range(80.0, 200.0), rn.range(0.2, 0.45))
		for i in 5:
			g.add(rn.range(0.0, D), P.EMBER, s * GAP + rn.range(-2.0, 2.0), L * rn.range(0.6, 1.0), s * rn.range(10.0, 40.0), rn.range(20.0, 60.0), rn.range(0.6, 1.1), F[4], rn.range(0.8, 1.6))
	cache[key] = g
	return g


# the pack: twin tanks with rounded caps, a spine between them, belled nozzles glowing hot inside
static func pack(p: Px.Painter, H: Array, F: Array, dy: float) -> void:
	for s: float in [-1.0, 1.0]:
		var cx := s * GAP
		p.shade(cx - 5.0, -24.0 + dy, cx + 5.0, -3.0 + dy, func(x: float, y: float, out):
			var u := (x - cx) / 4.5
			var top := -19.0 + dy
			var v := (y - top) / 4.5 if y < top else 0.0
			if u * u + v * v > 1.0:
				return
			var l := -u * 0.8 - v * 0.6
			out.c = H[0] if u * u + v * v > 0.78 else (H[1] if absf(y - (-12.0 + dy)) < 0.6 else (H[5] if l > 0.55 else (H[4] if l > 0.15 else (H[3] if l > -0.35 else H[2])))))
		# the nozzle bell, wider at its mouth, its inside lit by the flame
		for y in range(-3, 1):
			var w := 2.0 + (y + 3) * 0.7
			var x := floorf(cx - w)
			while x <= ceilf(cx + w):
				var inner := absf(x + 0.5 - cx) < w - 1.2 and y >= -1
				p.px(x, y + dy, (F[6] if y == 0 else F[4]) if inner else (H[0] if absf(x + 0.5 - cx) > w - 0.6 else (H[3] if x < cx else H[1])))
				x += 1.0
	for y in range(-20, -5):
		p.px(-1.0, y + dy, H[1])
		p.px(0.0, y + dy, H[2])
		p.px(1.0, y + dy, H[0])
	# a status light on the spine
	p.px(0.0, -16.0 + dy, F[5])


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 8)
	var H := Px.fit(o.metal, 6)
	var ph := t / D
	var f := floori(t * FR) % Px.roundi(D * FR)
	var S: float = o.seed
	var dy := Px.round(sin(TAU * 12.0 * ph) * 0.6)
	var g := ghosts(o, F).at(t)
	# smoke and spent flame behind, then the plumes
	g.draw(p, "back")
	for s: float in [-1.0, 1.0]:
		var cx := s * GAP + (s * 0.5 if Px.rand(S, f, s) < 0.15 else 0.0)
		var L: float = o.length * (0.92 + 0.08 * sin(TAU * 7.0 * ph + s) + 0.06 * (Px.rand(S, f, s, 1) - 0.5))
		# the flame: a cone of heat torn ragged by noise streaming down it, white at its heart, red at its edges
		p.shade(cx - 7.0, dy, cx + 7.0, dy + L + 4.0, func(x: float, y: float, out):
			var v := (y - dy) / L
			var w := Px.lerp(3.4, 0.6, v) + 1.4 * sin(v * PI) * (1.0 if v < 1.0 else 0.0)
			var n := Px.tileFbm((x - cx) / 3.0 + s * 5.0, (y - dy) / 4.0 - ph * 20.0, 0.0, 10.0, S + (9.0 if s > 0.0 else 0.0), 2)
			var q := absf(x - cx) / w + n * 0.45
			if v > 1.15 or q > 1.2:
				return
			var heat := (1.0 - v) * 1.15 - q * 0.9 + n * 0.25
			# a dark red rim round the flame, so it reads as a shape and not a smear
			if q > 0.95:
				out.c = F[3] if heat > 0.2 else F[2]
				if heat < -0.3:
					out.a = 0.5
				return
			out.c = WHITE if heat > 0.82 else (F[6] if heat > 0.62 else (F[5] if heat > 0.42 else (F[4] if heat > 0.22 else (F[3] if heat > 0.02 else F[2])))))
		# shock diamonds: bright knots strung down the core, breathing
		for i in 3:
			var y := Px.round(dy + 5.0 + i * 6.5 + sin(TAU * 4.0 * ph + i) * 0.5)
			var r := Px.roundi(2.2 - i * 0.45 + 0.4 * sin(TAU * 8.0 * ph + i * 2))
			if y > dy + L * 0.75 or r < 1:
				break
			for yy in range(-r, r + 1):
				for xx in range(-r, r + 1):
					var d := absi(xx) + absi(yy)
					if d <= r:
						p.px(cx + xx, y + yy, WHITE if d < r else (F[6] if i == 0 else F[5]))
			p.glow(cx, y, 6.0, F[6], 0.35)
		# light: hot at the nozzle, warm down the plume
		p.glow(cx, dy + 2.0, 9.0, WHITE, 0.45)
		p.glow(cx, dy + L * 0.45, L * 0.8, F[4], 0.35)
	pack(p, H, F, dy)
	g.draw(p, "front")
	# the fire lights the smoke below it, and its own surroundings
	p.glow(0.0, o.length + 14.0, 34.0, F[4], 0.16)
	p.glow(0.0, o.length * 0.4, 30.0, F[5], 0.18)
