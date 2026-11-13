# The bubbles (lit and shaded rims, a highlight, a dotted pop) follow Sprite Fusion's open-source bubbles
# (https://www.spritefusion.com/pixel-art-vfx/bubbles), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/potion.js@bfefca9ad8b6f82a00c7f29b9c854887986b5aca
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Potion",
	"desc": "A round glass flask of glowing brew rocks in the air: the brew sloshes behind the rock, bubbles rise and pop, light glows through the glass, wisps curl off the cork.",
	"tags": ["pickup", "potion", "flask", "brew", "magic", "loop"],
	"size": [56, 72],
	"origin": [28, 64],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#1a0516", "#3d0a33", "#701560", "#b0228f", "#f53cd1", "#ff86e6", "#ffd2f6", "#ffffff"], "seed": 5},
}

const RB := 7.0
const HOVER := 17.0
const NECK := 2.0
const LIP := -12.0
const CORK_TOP := -16.0
static var INK := Px.hex("#120d1a")
static var GLASS := Px.hex("#2a2236")
static var CORK := Px.ramp(["#2a160c", "#4e2c16", "#7a4a26", "#a8703a", "#d09a5a"])
static var L := Lib.Layer.new(40, 44)


# the flask hovers and rocks; the brew's surface stays level in the world and lags behind the rock
static func pose(ph: float) -> Dictionary:
	return {"y": -HOVER - 1.4 * sin(ph * TAU), "tilt": 0.13 * sin(ph * TAU + 0.4)}


static func surface(x: float, ph: float) -> float:
	return -0.5 + 0.17 * sin(ph * TAU - 0.9) * x + 0.45 * sin(x * 0.85 + ph * TAU * 3.0)


static func flask(p: Px.Painter, C: Array, t: float, ph: float, cy: float, tilt: float, seed: Variant) -> void:
	var ct := cos(tilt)
	var st := sin(tilt)
	L.begin(-20.0, floorf(cy) - 22.0)
	L.fill(-20.0, floorf(cy) - 22.0, 19.0, floorf(cy) + 12.0, func(px: float, py: float) -> Variant:
		var wx := px
		var wy := py - cy
		var fx := wx * ct + wy * st
		var fy := -wx * st + wy * ct
		var d := Px.hypot(fx, fy)
		# the cork, the lip, the neck and the bulb, in the flask's own frame
		if fy < LIP - 0.5 and fy >= CORK_TOP and absf(fx) <= NECK + 0.2:
			return CORK[4 if fy < CORK_TOP + 1.0 else (3 if fx < -0.6 else (1 if fx > 1.0 else 2))]
		if fy >= LIP - 0.5 and fy < LIP + 1.0 and absf(fx) <= NECK + 1.4:
			return Px.mix(WHITE, C[6], 0.4) if fx < 0.0 else Px.mix(GLASS, C[5], 0.45)
		var inNeck := fy >= LIP + 1.0 and fy < -RB + 2.0 and absf(fx) <= NECK + 0.6
		if d > RB and not inNeck:
			return 0
		var wall := absf(fx) > NECK - 0.5 if inNeck else d > RB - 1.0
		# the brew: below its sloshing surface, glowing from within, a bright skin on top
		var s := surface(wx, ph)
		var depth := wy - s
		if not wall and not inNeck and depth > 0.0:
			# dark at the bottom and the edges, a lit heart, a bright skin with a sheen on its left
			var core := 1.0 - Px.hypot(wx * 0.85, wy - 1.8) / RB
			if depth < 0.9:
				return WHITE if (wx < -1.5 and wx > -4.5) else C[6]
			var k := 5 if core > 0.62 else (4 if core > 0.38 else (3 if core > 0.18 else 2))
			if depth < 1.9 and k < 5:
				k += 1
			if wx > 1.5 and wy > 2.0:
				k -= 1
			return C[maxi(2, mini(6, k))]
		if wall:
			# the glass: catching light on its left, showing the brew through its lower half
			var lit := (-fx * 0.75 - fy * 0.66) / maxf(1.0, d)
			if inNeck:
				return Px.mix(GLASS, C[6], 0.55) if fx < 0.0 else Px.mix(GLASS, C[5], 0.3)
			if lit > 0.82:
				return Px.mix(WHITE, C[6], 0.3)
			if lit > 0.3:
				return Px.mix(GLASS, C[6], 0.5)
			return C[3] if depth > 0.0 else Px.mix(GLASS, C[5], 0.28)
		# empty glass above the brew
		return GLASS)
	L.outline(INK).draw(p)
	# a curved streak of light on the glass, and a pin-point
	var a := 3.45
	while a < 4.35:
		var lx := cos(a + tilt) * (RB - 2.2)
		var ly := sin(a + tilt) * (RB - 2.2)
		p.px(lx, cy + ly, WHITE if (a > 3.7 and a < 4.1) else Px.mix(WHITE, C[6], 0.5))
		a += 0.04
	p.px(Px.round(2.0 * cos(tilt) + 3.0 * sin(tilt)), Px.round(cy - 3.0), WHITE)
	# bubbles rising through the brew and popping at its surface
	var D: float = meta.duration
	Px.cycle(t, D, 10, seed, func(g: Px.Rng) -> float: return g.range(0.7, 1.3), func(age: float, life: float, r: Px.Rng) -> void:
		var x0 := r.range(-4.0, 4.0)
		var r0 := r.range(0.6, 1.7)
		var vy := r.range(7.0, 13.0)
		var x := x0 + sin(age * r.range(5.0, 9.0) + r.range(0.0, TAU)) * 0.7
		var y := cy + 5.5 - vy * age
		var ph2 := (t + age) / D
		var top := cy + surface(x, ph2)
		if y > top + 0.8:
			var rr := r0 * (0.7 + 0.5 * (age / life))
			if Px.hypot(x, y - cy) > RB - 1.5:
				return
			if rr < 0.95:
				p.px(x, y, C[6])
			else:
				p.px(x, y, C[3])
				p.px(x + 1.0, y, C[6])
				p.px(x, y - 1.0, WHITE)
				p.px(x + 1.0, y - 1.0, C[6])
				if rr > 1.4:
					p.px(x - 1.0, y, C[5])
					p.px(x, y + 1.0, C[4])
			p.glow(x + 0.5, y, 3.0, C[6], 0.15)
		else:
			# the pop: a little arc of light and two flecks thrown up
			var k := Px.clamp((top + 0.8 - y) / 3.0)
			if k >= 1.0:
				return
			var a2 := PI
			while a2 < TAU:
				p.dot(x + cos(a2) * (1.0 + k * 2.0), top - 0.5 + sin(a2) * (1.0 + k * 2.0) * 0.5, WHITE if k < 0.5 else C[6], 1.2 - k)
				a2 += 0.6
			p.dot(x - 1.0, top - 1.5 - k * 3.0, C[6], 1.0 - k)
			p.dot(x + 1.5, top - 2.0 - k * 4.0, WHITE, 1.0 - k))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var ph := t / D
	var y: float = pose(ph).y
	Lib.blobShadow(p, 0.0, 7.5, 0.8 - (-y - HOVER + 1.4) * 0.06)
	# light thrown on the floor through the brew
	Lib.pool(p, 0.0, 0.5, 18.0, 3.0, C[5], 0.3)
	# wisps curling up off the cork: thin trails of light that sway wider as they rise and fade
	Px.cycle(t, D, 7, o.seed + 1, func(g: Px.Rng) -> float: return g.range(1.2, 1.8), func(age: float, life: float, r: Px.Rng) -> void:
		var side := r.sign()
		var f := r.range(3.0, 4.5)
		var ph0 := r.range(0.0, TAU)
		var vy := r.range(11.0, 16.0)
		var x0 := r.range(-1.0, 1.0)
		var at := func(a: float) -> Array: return [x0 + sin(a * f + ph0) * (0.8 + a * 3.2) * side, y + CORK_TOP - 1.0 - a * vy]
		for i in 9:
			var a := age - i * 0.04
			if a < 0.0:
				break
			var xy: Array = at.call(a)
			var x: float = xy[0]
			var yy: float = xy[1]
			var k := (1.0 - a / life) * minf(1.0, a / 0.15) * (1.0 - i / 9.0)
			p.dot(x, yy, WHITE if i == 0 else (C[6] if i < 3 else C[5]), k * 1.4)
			if i == 0:
				p.glow(x, yy, 4.0, C[5], 0.3 * k))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var ph := t / D
	var ps := pose(ph)
	var y: float = ps.y
	var tilt: float = ps.tilt
	# the brew glows through the glass
	p.glow(0.0, y + 1.5, 26.0, C[4], 0.22)
	flask(p, C, t, ph, y, tilt, o.seed)
	p.glow(0.0, y + 2.0, 10.0, C[5], 0.38 + 0.08 * sin(ph * TAU * 2.0))
	# a glint on the glass now and then
	var g := fmod(ph + 0.2, 0.5) / 0.5
	if g < 0.16:
		Lib.glint(p, -4.0, y - 4.0, 2.6 * sin((g / 0.16) * PI), WHITE, 0.4)
