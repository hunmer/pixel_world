# The re-struck filaments, the glass shell with its specular arc and the core follow Sprite Fusion's open-source
# energy orb (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/plasma-ball.js@e62a656394968869264a0276372ff743199ca767
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Plasma ball",
	"desc": "A glass globe on a dark pedestal: wandering plasma tendrils reach from the core to the glass and fan out in bright feet where they touch it, lighting the stand and floor.",
	"tags": ["lightning", "electric", "plasma", "lamp", "prop", "loop"],
	"size": [112, 104],
	"origin": [56, 96],
	"duration": 3.0,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#1a0828", "#3b0f5e", "#6a1d9c", "#a03ad6", "#d46cf2", "#f2a8ff", "#ffe2ff", "#ffffff"], "tendrils": 9, "seed": 6},
}

const FPS := 30.0
const N := 90
const GX := 0.0
const GY := -55.0
const RG := 24.0
static var BASE := Px.ramp(["#0d0b12", "#17131f", "#231d2d", "#342b43", "#4b3f60", "#6b5c87"])


# a tendril at phase ph: its end wanders over the glass, front ones end on the near face, back ones on the far
static func tendril(i: int, n: float, ph: float, seed: float) -> Dictionary:
	var a := ((i + 0.5) / n) * TAU + 0.9 * Px.loopNoise(ph, 0.9, seed + i * 7)
	var z := Px.loopNoise(ph, 0.7, seed + i * 7 + 3)
	var rho := RG * (0.72 + 0.28 * sqrt(1.0 - minf(1.0, z * z * 1.6)))
	return {"a": a, "front": z > -0.15, "ex": GX + cos(a) * rho, "ey": GY + sin(a) * rho, "rim": rho > RG * 0.93, "w1": Px.loopNoise(ph, 1.1, seed + i * 7 + 5), "w2": Px.loopNoise(ph, 1.3, seed + i * 7 + 6)}


# the pedestal: a flared stand lit from above by the globe, a collar under the glass
static func pedestal(p: Px.Painter, C: Array, glow: float) -> void:
	p.shade(-18.0, -32.0, 18.0, 0.0, func(x, y, o):
		var hw: float = 7.0 if y < -27.0 else (9.0 + ((y + 27.0) / 25.0) * 6.0 if y < -2.0 else 16.0)
		if absf(x) > hw:
			return
		var u: float = (x / hw + 1.0) / 2.0
		if y < -27.0:
			o.c = (C[4] if u < 0.6 else BASE[5]) if y < -30.0 else (BASE[5] if u < 0.3 else (BASE[3] if u < 0.75 else BASE[1]))
			return
		if y >= -2.0:
			o.c = (BASE[4] if u < 0.55 else BASE[2]) if y < -1.0 else BASE[1]
			return
		# glossy body: a lit flank, a specular stripe, the far side in shadow, plasma light on the upper rim
		var i: int = 2 if u < 0.1 else (3 if u < 0.2 else (5 if u < 0.3 else (4 if u < 0.42 else (3 if u < 0.6 else (2 if u < 0.8 else (1 if u < 0.92 else 0))))))
		o.c = Px.mix(BASE[i], C[4], 0.3 * glow) if (y < -24.0 and u < 0.5) else (BASE[maxi(0, i - 1)] if y > -5.0 else BASE[i]))
	p.px(9.0, -9.0, C[5])
	p.glow(9.0, -9.0, 3.0, C[5], 0.5)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var f := floori(t * FPS + 1e-6) % N
	var ph := f / float(N)
	var n: float = o.tendrils
	var R := Px.rng(o.seed, 3, f)
	var pulse := 0.85 + 0.15 * sin(ph * TAU * 6.0) + 0.1 * (R.next() - 0.5)
	var ts := Px.arr(n, func(i): return tendril(i, n, ph, o.seed))
	# light the floor and the stand, then the stand
	p.glow(0.0, -6.0, 52.0, C[3], 0.22 * pulse)
	pedestal(p, C, pulse)
	# the glass: a faint tint over what's behind, the plasma's glow inside it
	p.shade(GX - RG, GY - RG, GX + RG, GY + RG, func(x, y):
		var d := Px.hypot(x - GX, y - GY)
		if d < RG - 0.5:
			p.blend(x, y, C[1] if d > RG - 4.0 else C[0], 0.22 + 0.4 * (d / RG) ** 4))
	p.glow(GX, GY, RG + 14.0, C[3], 0.32 * pulse)
	p.glowRing(GX, GY, RG - 1.0, 5.0, C[3], 0.22 * pulse)
	for i in ts.size():
		var q: Dictionary = ts[i]
		if not q.front:
			drawTendril(p, C, o, f, q, i, false)
	# the core: an electrode ball, pulsing
	var cr := 3.6 + 0.5 * pulse
	p.circle(GX, GY, cr + 1.3, C[3])
	p.circle(GX, GY, cr, C[5])
	p.circle(GX - 0.6, GY - 0.6, cr * 0.55, C[6])
	p.circle(GX - 0.8, GY - 0.8, cr * 0.25, WHITE)
	p.glow(GX, GY, 16.0, C[5], 0.65 * pulse)
	for i in ts.size():
		var q: Dictionary = ts[i]
		if q.front:
			drawTendril(p, C, o, f, q, i, true)
	# the glass shell: a thin rim, a bright specular arc upper left, a faint reflection lower right
	p.ring(GX, GY, RG + 1.6, 1.0, C[1])
	p.ring(GX, GY, RG + 0.6, 1.1, func(v, a): return C[5] if (a > 2.2 and a < 3.3) else (C[4] if (a > 0.3 and a < 1.3) else C[3]))
	p.arc(GX, GY, RG - 1.6, 1.3, 3.55, 4.55, func(u): return WHITE if (u > 0.25 and u < 0.7) else C[6])
	var a := 0.35
	while a < 1.15:
		p.dot(GX + cos(a) * (RG - 2.6), GY + sin(a) * (RG - 2.6), C[4], 0.85)
		a += 0.045
	p.px(GX - RG * 0.42, GY - RG * 0.62, WHITE)


static func drawTendril(p: Px.Painter, C: Array, o: Dictionary, f: int, q: Dictionary, i: int, bright: bool) -> void:
	var sx: float = GX + cos(q.a) * 4.5
	var sy: float = GY + sin(q.a) * 4.5
	var dx: float = q.ex - sx
	var dy: float = q.ey - sy
	var L := Px.hypot(dx, dy)
	var nx := -dy / L
	var ny := dx / L
	var r := Px.rng(o.seed, 17, i, f)
	var pts := []
	var m := maxi(4, Px.roundi(L / 2.2))
	for j in m + 1:
		var u := j / float(m)
		var w: float = 3.2 * q.w1 * sin(PI * u) + 1.6 * q.w2 * sin(TAU * u + i)
		var jit := r.range(-0.7, 0.7) if (j and j < m) else 0.0
		pts.append([sx + dx * u + nx * (w + jit), sy + dy * u + ny * (w + jit)])
	# the foot: the filament fans into short fingers where it meets the glass
	var paths := [{"pts": pts, "w": 1.0}]
	for k in 3:
		var bx: float = pts[m - 2][0]
		var by: float = pts[m - 2][1]
		var a: float = q.a + (k - 1) * r.range(0.25, 0.45)
		var l := r.range(2.5, 5.0)
		paths.append({"pts": [[bx, by], [bx + cos(a) * l * 0.5 + r.range(-0.6, 0.6), by + sin(a) * l * 0.5 + r.range(-0.6, 0.6)], [bx + cos(a) * l, by + sin(a) * l]], "w": 0.5})
	var hot := r.next() < 0.2
	for q2: Dictionary in paths:
		var qp: Array = q2.pts
		for j in qp.size() - 1:
			var ax: float = qp[j][0]
			var ay: float = qp[j][1]
			var bx: float = qp[j + 1][0]
			var by: float = qp[j + 1][1]
			var u := j / float(qp.size() - 1)
			if bright and q2.w >= 1.0:
				p.line(ax + 1.0, ay + 1.0, bx + 1.0, by + 1.0, C[3])
			var c: int = ((C[3] if q2.w >= 1.0 else C[2])) if not bright else (C[6] if q2.w < 1.0 else (C[6] if (hot or u > 0.75) else (C[6] if u < 0.2 else C[5])))
			p.line(ax, ay, bx, by, c)
			if q2.w >= 1.0 and j % 3 == 0:
				p.glow(ax, ay, 6.0 if bright else 4.0, C[4], (0.4 if hot else 0.24) if bright else 0.12)
	# where it touches, the glass flares
	if bright:
		p.circle(q.ex, q.ey, 1.6, C[6])
		p.px(q.ex, q.ey, WHITE)
		p.glow(q.ex, q.ey, 9.0, C[5], 0.55)
		if q.rim:
			var s := -1
			while s <= 1:
				p.px(GX + cos(q.a + s * 0.09) * (RG - 0.5), GY + sin(q.a + s * 0.09) * (RG - 0.5), C[6])
				s += 2
	else:
		p.glow(q.ex, q.ey, 6.0, C[4], 0.25)
