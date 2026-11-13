# The orb's build (a see-through body with a lit rim, an inner current drawn as streaks on a tilted plane, motes
# on tilted orbits split behind and in front, a pulsing light) follows Sprite Fusion's open-source energy orb
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/water-orb.js@eca9dab09cf0ac79ba80e6f6afb266756d19fe2f
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const SQRT2 := 1.4142135623730951

static var meta := {
	"name": "Water orb",
	"desc": "A sphere of water floats and wobbles: a current circles inside it, the floor shows upside down through it, it shines, light gathers on the floor under it, and drips fall and plink.",
	"tags": ["water", "orb", "sphere", "magic", "float", "ambient", "loop"],
	"size": [100, 108],
	"origin": [50, 100],
	"duration": 3,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.WATER, "radius": 19, "seed": 2},
}

static var D: float = meta.duration
const SY := 0.3
const G := 700.0
const DRIP := 1.5
const LET := 0.5


static func center(ph: float) -> Array:
	return [0.0, -52.0 + sin(ph * TAU) * 2.0]


# the skin wobbles: radius at angle a, and the belly sags into a drip before each one falls
static func skin(a: float, R: float, ph: float) -> float:
	var sag := pow(maxf(0.0, sin(a)), 6.0) * 2.2 * Px.smooth(0.1, LET, fmod(ph * D, DRIP) / DRIP) * (1.0 if fmod(ph * D, DRIP) / DRIP < LET else 0.0)
	return R + sin(a * 3.0 + ph * TAU * 2.0) * 0.6 + sin(a * 5.0 - ph * TAU * 3.0) * 0.35 + sag


# motes of spray on tilted orbits round it: position, and whether it's in front
static func motes(ph: float, R: float) -> Array:
	return Px.arr(7, func(i: int):
		var a := (i / 7.0) * TAU + ph * TAU * (1.0 if i % 2 else -1.0)
		var r := R + 5.0 + (i % 3) * 3.0
		var tilt := (i - 3) * 0.22
		var x := cos(a) * r
		var z := sin(a)
		return {"x": x * cos(tilt), "y": x * sin(tilt) + z * r * 0.28, "z": z, "i": i})


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var R: float = o.radius
	var cxy := center(ph)
	var cx: float = cxy[0]
	var cy: float = cxy[1]
	# light gathers on the floor under it, the orb's caustic
	p.glow(cx, 0.0, 22.0, C[5], 0.32)
	p.shade(cx - 9.0, -2.0, cx + 9.0, 2.0, func(x: float, y: float, out):
		var d := pow(x - cx, 2.0) / 64.0 + pow(y * 2.5, 2.0) / 9.0
		if d > 1.0:
			return
		out.c = WHITE if d < 0.25 else (C[6] if d < 0.6 else C[5])
		out.a = 1.2 - d)
	for m: Dictionary in motes(ph, R):
		if m.z < 0:
			p.px(cx + m.x, cy + m.y, C[4])
	p.glow(cx, cy, R * 3.2, C[4], 0.3 + 0.05 * sin(ph * TAU * 2.0))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var R: float = o.radius
	var cxy := center(ph)
	var cx: float = cxy[0]
	var cy: float = cxy[1]
	var T := ph * TAU
	# the body: see-through water, deeper toward the bottom; the floor seen upside down through its lower half
	p.shade(cx - R - 4.0, cy - R - 4.0, cx + R + 4.0, cy + R + 6.0, func(x: float, y: float, out):
		var dx := x - cx
		var dy := y - cy
		var d := Px.hypot(dx, dy)
		var a := atan2(dy, dx)
		var r := skin(a, R, ph)
		if d > r:
			return
		var q := d / r
		var lit := (-dx - dy) / SQRT2 / maxf(0.5, d)
		if q > 0.9:
			out.c = WHITE if lit > 0.35 else (C[5] if lit > -0.2 else C[3])
			return
		# a lens of water: dark on the side the light comes from, the light gathering low on the far side inside
		var gather := maxf(0.0, (dx + dy) / SQRT2 / r) * q
		p.blend(x, y, C[4] if gather > 0.45 else (C[3] if gather > 0.25 else (C[2] if q > 0.7 else C[1])), 0.7 if gather > 0.25 else 0.35 + 0.3 * q))
	# the current inside: streaks circling on a tilted plane, bright where they pass in front
	for k in 3:
		var rr := R * (0.38 + 0.2 * k)
		var tilt := -0.5 + k * 0.35
		var spin := T * (-2.0 if k % 2 else 3.0) + k * 2
		var s := 0.0
		while s < 1.0:
			var a := spin + s * TAU
			var x := cos(a) * rr
			var z := sin(a)
			var y := x * sin(tilt) * 0.6 + z * rr * 0.62
			var dash := fmod(s * 3.0 + k * 0.3, 1.0)
			if dash > 0.62:
				s += 0.012
				continue
			p.px(cx + x * cos(tilt), cy + y, ((WHITE if dash < 0.1 else (C[6] if dash < 0.4 else C[5])) if z > 0.0 else C[3]))
			s += 0.012
	# bubbles drift up inside it
	Px.cycle(t, D, 8, o.seed, func(g: Px.Rng): return g.range(1.0, 1.8), func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var x := r.range(-0.5, 0.5) * R + sin(age * 4.0 + r.range(0.0, TAU)) * 1.5
		var y := R * 0.6 - k * R * 1.2
		if Px.hypot(x, y) > R * 0.8:
			return
		p.px(cx + x, cy + y, C[6] if k < 0.8 else WHITE)
		if r.next() < 0.35:
			p.px(cx + x + 1.0, cy + y, C[5]))
	# the shine: a bright crescent up on the left, a small refracted glint low on the right
	p.arc(cx, cy, R * 0.74, 1.8, PI * 1.12, PI * 1.4, func(u: float, v: float): return WHITE if (u > 0.25 and u < 0.75 and v > 0.4) else C[6])
	p.px(cx - R * 0.45, cy - R * 0.62, WHITE)
	p.px(cx + R * 0.48, cy + R * 0.5, C[6])
	p.px(cx + R * 0.48 + 1.0, cy + R * 0.5, C[5])
	# motes in front
	for m: Dictionary in motes(ph, R):
		if m.z >= 0:
			p.px(cx + m.x, cy + m.y, WHITE)
			p.px(cx + m.x - (-1.0 if m.i % 2 else 1.0), cy + m.y, C[5])
			p.glow(cx + m.x, cy + m.y, 4.0, C[5], 0.35)
	# drips: one swells on its belly and lets go every DRIP seconds, landing with a plink and a ring
	var dt := fmod(t, DRIP) / DRIP
	var fall := fmod(t, DRIP) - DRIP * LET
	var y0 := cy + R + 3.0
	var land := sqrt((2.0 * -y0) / G)
	if fall < 0.0 and dt > 0.2:
		var s := Px.smooth(0.2, LET, dt)
		p.circle(cx, cy + R + 1.0 + s * 1.5, 0.8 + s * 1.2, C[5])
		p.px(cx - 0.5, cy + R + s * 1.5, C[6])
	elif fall >= 0.0 and fall < land:
		Lib.bead(p, cx, y0 + 0.5 * G * fall * fall, 0.0, G * fall, 2.0, C)
	elif fall >= land:
		var since := fall - land
		if since < 0.08:
			p.px(cx, 0.0, WHITE)
		Lib.ring(p, cx, 0.0, 1.5 + since * 18.0, SY, 1.1 * (1.0 - since / 0.4), C, {"n": 1.0, "half": 1.0, "seed": 3.0, "hot": since < 0.05})
	# where the lens brings the light to a point, low on the far side: a bright fleck, pulsing
	var fx := cx + R * 0.36
	var fy := cy + R * 0.4
	var pulse := 0.8 + 0.2 * sin(T * 4.0)
	p.circle(fx, fy, 1.6, C[6])
	p.px(fx, fy, WHITE)
	p.glow(fx, fy, 9.0, C[5], 0.45 * pulse)
	p.glow(cx, cy, R * 1.4, C[5], 0.22)
	p.glow(cx - R * 0.4, cy - R * 0.5, 6.0, WHITE, 0.25)
