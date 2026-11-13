# The dithered light ramp and the streaked, knotted disc texture are adapted from Sprite Fusion's open-source
# black hole (https://www.spritefusion.com/pixel-art-vfx/black-hole), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/portal.js@ddd71b9bd069b29ec4fb839fb5c2e200815794bb
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

const D := 2.4

static var meta := {
	"name": "Portal",
	"desc": "An upright rift: fibrous spiral arms wind down into the dark, a lit rim wobbles, motes and streaks are pulled in, the floor glows.",
	"tags": ["arcane", "portal", "rift", "teleport", "magic", "ground", "loop"],
	"size": [152, 116],
	"origin": [76, 106],
	"duration": D,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Px.PAL.arcane, "width": 17, "height": 29, "seed": 4},
}

static func wrapPi(a: float) -> float:
	return a - TAU * floorf((a + PI) / TAU)


static func setup(t: float, o: Dictionary) -> Dictionary:
	var C := Px.fit(o.palette, 8)
	var rx: float = o.width
	var ry: float = o.height
	var ph := t / D
	var S: float = o.seed
	var CY := -(ry + 5.0)
	# the rim's radius (1 = the oval) at angle th: slow noise rolling round it, plus a three-lobed breath
	var rim := func(th: float) -> float: return 1.0 + 0.05 * Px.tileNoise((th / TAU) * 10.0 + ph * 10.0, ph * 4.0, 10.0, 4.0, S) + 0.018 * sin(th * 3.0 - ph * TAU * 2.0)
	# where a point at angle th and radius rho (1 = the rim) sits; outside, the field widens so motes come from round about
	var at := func(th: float, rho: float) -> Array:
		var out := maxf(0.0, rho - 1.0)
		var k := minf(1.0, rho)
		return [cos(th) * (k * rx + out * 21.0), minf(-1.0, CY + sin(th) * (k * ry + out * 16.0))]
	# two hot spots chase round the rim with the spin, and a key light sits at the top left
	var spots := [ph * TAU * 2.0 - 0.6, ph * TAU * 2.0 + PI - 0.6]
	var hot := func(th: float) -> float: return maxf(exp(-pow(wrapPi(th - spots[0]), 2.0) / 0.12), 0.85 * exp(-pow(wrapPi(th - spots[1]), 2.0) / 0.08)) + 0.35 * maxf(0.0, cos(th + 2.3))
	return {"C": C, "rx": rx, "ry": ry, "ph": ph, "S": S, "CY": CY, "rim": rim, "at": at, "hot": hot, "spots": spots}


# the rift itself: the dark well, the fibrous arms winding down into it, the lit rim
static func rift(p: Px.Painter, s: Dictionary) -> void:
	var C: Array = s.C
	var rx: float = s.rx
	var ry: float = s.ry
	var ph: float = s.ph
	var CY: float = s.CY
	var rim: Callable = s.rim
	var hot: Callable = s.hot
	p.shade(-rx - 4.0, CY - ry - 4.0, rx + 4.0, CY + ry + 4.0, func(x: float, y: float, out) -> void:
		var u := x / rx
		var v := (y - CY) / ry
		var r := Px.hypot(u, v)
		if not r:
			r = 1e-6
		var th := atan2(v, u)
		var R0: float = rim.call(th)
		var g := Px.hypot(u / rx, v / ry) / r
		var e := (r - R0) / g
		var h: float = hot.call(th)
		if e > 2.5:
			return
		# outside the rim: a coloured line where it's lit, a dark one elsewhere, a faint halo past it
		if e > 1.5:
			if h > 0.6:
				out.c = C[3]
				out.a = 0.5
			return
		if e > 0.5:
			out.c = C[4] if h > 0.5 else C[2]
			return
		if e > -0.5:
			out.c = WHITE if h > 0.42 else C[6]
			out.k = 0.25 + 0.4 * h
			return
		# inside, in ramp steps: clean depth bands falling away to a dark well; three thin bright arms and three
		# faint ones on a log spiral, flowing inward a turn a loop, with knots of light running down them; the light
		# that spills in round the rim
		var d := r / R0
		var z := -log(maxf(0.02, d))
		var phi := 3.0 * th + 6.5 * z - TAU * 3.0 * ph
		var c1 := 0.5 + 0.5 * cos(phi)
		var c2 := 0.5 + 0.5 * cos(phi + PI + 0.6 * z)
		var lit := pow(d, 1.5)
		var sink := Px.smooth(0.2, 0.62, d)
		var knot := pow(maxf(0.0, cos(4.0 * z - phi / 3.0 + TAU * 5.0 * ph)), 6.0)
		var st := Px.smooth(0.4, 0.7, d) + 0.6 * Px.smooth(0.8, 0.95, d)
		var crest := pow(c1, 16.0) * (0.6 + 5.6 * lit) * (1.0 + 0.5 * knot) * sink
		st += crest + pow(c1, 5.0) * 1.1 * lit
		st += pow(c2, 18.0) * (0.3 + 1.8 * lit) * sink
		# rings of the tunnel shrinking away down the well, two a loop
		st += pow(0.5 + 0.5 * cos(TAU * (z * 1.5 - ph * 2.0)), 20.0) * 1.3 * sink * (1.0 - 0.5 * c1)
		# fine strands between the arms, a step brighter than the dark they run through
		st += pow(0.5 + 0.5 * cos(3.0 * phi + 2.0 * z + 1.3), 10.0) * 1.1 * lit * sink
		st += 2.2 * pow(Px.smooth(0.8, 1.0, d), 2.0) * (0.75 + 0.45 * h)
		out.c = Lib.tone(C, st / 7.0, x, y, 0.0, 0.65)
		if crest > 2.2:
			out.k = 0.12 + 0.05 * crest)


# specks of light deep in the well, swept round with the arms and sinking towards the far end
static func well(p: Px.Painter, s: Dictionary) -> void:
	var C: Array = s.C
	var rx: float = s.rx
	var ry: float = s.ry
	var ph: float = s.ph
	var S: float = s.S
	var CY: float = s.CY
	var rim: Callable = s.rim
	var t := ph * D
	Px.cycle(t, D, 18, S * 7.0 + 5.0, func(g: Px.Rng) -> float: return g.range(1.1, 1.8), func(age: float, life: float, r: Px.Rng) -> void:
		var q := age / life
		var th := r.range(0.0, TAU) + q * 2.6
		var rho := 0.92 * (1.0 - Px.Ease.inQuad(q) * 0.9)
		var R0: float = rim.call(th)
		var x := cos(th) * rho * R0 * rx
		var y := CY + sin(th) * rho * R0 * ry
		var tw := sin(ph * TAU * r.int_(14, 22) + r.range(0.0, TAU))
		var a := minf(1.0, q * 6.0) * (1.0 if rho > 0.25 else rho / 0.25)
		if tw > -0.3:
			p.dot(x, y, WHITE if (rho > 0.6 and tw > 0.6) else (C[6] if rho > 0.45 else C[5]), a))


# motes riding round just outside the rim, sinking in as they go
static func orbit(p: Px.Painter, s: Dictionary) -> void:
	var C: Array = s.C
	var rx: float = s.rx
	var ry: float = s.ry
	var ph: float = s.ph
	var S: float = s.S
	var CY: float = s.CY
	for i in 7:
		var k := fmod(ph * 2.0 + i / 7.0, 1.0)
		var th := fmod(i * 2.39 + S, TAU) + ph * TAU * 2.0 + k * 2.5
		var rho := 1.2 + 0.35 * fmod(i * 0.618, 1.0) - 0.3 * Px.Ease.inQuad(k)
		var x := cos(th) * rho * rx
		var y := CY + sin(th) * rho * ry
		var a := minf(1.0, sin(k * PI) * 2.2)
		Lib.mote(p, x, y, -sin(th) * rx * 10.0, cos(th) * ry * 10.0, C[6] if i % 3 else WHITE, 0.6, a, 0.3)


# motes and streaks pulled in from round about, spinning faster as they fall; inside they sink into the dark
static func infall(p: Px.Painter, s: Dictionary) -> void:
	var C: Array = s.C
	var ph: float = s.ph
	var S: float = s.S
	var rim: Callable = s.rim
	var at: Callable = s.at
	var t := ph * D
	Px.cycle(t, D, 60, S * 7.0 + 1.0, func(g: Px.Rng) -> float: return g.range(0.3, 0.5), func(age: float, life: float, r: Px.Rng) -> void:
		var a0 := r.range(0.0, TAU)
		var d0 := r.range(1.8, 3.0)
		var spin := r.range(0.8, 1.8) * (1.0 if r.chance(0.8) else 0.35)
		var size := r.range(0.8, 1.5)
		var hue := r.next()
		var pos := func(q: float) -> Array: return at.call(a0 + spin * q * q, d0 * (1.0 - pow(q, 1.4)))
		var q := age / life
		var xy: Array = pos.call(q)
		var xy2: Array = pos.call(minf(1.0, q + 0.015))
		var x: float = xy[0]
		var y: float = xy[1]
		var x2: float = xy2[0]
		var y2: float = xy2[1]
		var vx := (x2 - x) / (0.015 * life)
		var vy := (y2 - y) / (0.015 * life)
		var rho := d0 * (1.0 - pow(q, 1.4))
		var R0: float = rim.call(a0 + spin * q * q)
		var fade := minf(1.0, q * 5.0)
		if rho > R0 + 0.06:
			Lib.mote(p, x, y, vx, vy, WHITE if hue < 0.25 else (C[6] if hue < 0.55 else (C[5] if hue < 0.8 else C[4])), size if hue < 0.8 else size * 1.4, fade, 0.4 if hue < 0.8 else 0.15)
		elif rho > 0.3:
			p.dot(x, y, C[6] if rho > 0.65 else C[5], rho))
	Px.cycle(t, D, 12, S * 7.0 + 2.0, func(g: Px.Rng) -> float: return g.range(0.36, 0.5), func(age: float, life: float, r: Px.Rng) -> void:
		var a0 := r.range(0.0, TAU)
		var d0 := r.range(2.3, 3.0)
		var spin := r.range(0.2, 0.5)
		var qc := sqrt(1.0 - 1.05 / d0)
		var q := age / life
		var pos := func(qq: float) -> Array: return at.call(a0 + spin * qq * qq, d0 * (1.0 - qq * qq))
		if q < qc:
			var xy: Array = pos.call(q)
			var xy2: Array = pos.call(q + 0.015)
			var x: float = xy[0]
			var y: float = xy[1]
			Lib.streak(p, x, y, (xy2[0] - x) / (0.015 * life), (xy2[1] - y) / (0.015 * life), C[6], minf(1.0, q * 5.0))
		else:
			# it hits the rim: a pinprick of white
			var k := 1.0 - (q - qc) / (1.0 - qc)
			var xy: Array = pos.call(qc)
			if k > 0.55:
				p.px(xy[0], xy[1], WHITE)
			p.glow(xy[0], xy[1], 7.0, C[6], 0.6 * k * k))


# grit and sparks skating in along the floor, lifting into the foot of the rift
static func skaters(p: Px.Painter, s: Dictionary) -> void:
	var C: Array = s.C
	var ph: float = s.ph
	var S: float = s.S
	var CY: float = s.CY
	var ry: float = s.ry
	var t := ph * D
	var foot := CY + ry
	Px.cycle(t, D, 14, S * 7.0 + 3.0, func(g: Px.Rng) -> float: return g.range(0.7, 1.1), func(age: float, life: float, r: Px.Rng) -> void:
		var side := r.sign()
		var x0 := side * r.range(22.0, 50.0)
		var y0 := -1.0 - r.range(0.0, 1.5)
		var q := age / life
		var e := Px.Ease.inCubic(q)
		var x := x0 * (1.0 - e)
		var y := y0 + (foot + 2.0) * Px.smooth(0.55, 1.0, q)
		var xb := x0 * (1.0 - Px.Ease.inCubic(maxf(0.0, q - 0.04)))
		var yb := y0 + (foot + 2.0) * Px.smooth(0.55, 1.0, q - 0.04)
		var big := r.chance(0.3)
		Lib.mote(p, x, y, (x - xb) * 25.0, (y - yb) * 25.0, C[6] if big else C[5], 0.9 if big else 0.6, minf(1.0, q * 4.0) * (1.0 - Px.smooth(0.85, 1.0, q)), 0.3))


static func floor_(p: Px.Painter, s: Dictionary) -> void:
	var C: Array = s.C
	var ph: float = s.ph
	var pulse := 0.85 + 0.15 * sin(ph * TAU * 2.0)
	for x in range(-36, 37):
		var u := absf(x + 0.5) / 36.0
		var a := (1.0 if u < 0.55 else 1.0 - (u - 0.55) / 0.45) * (0.8 + 0.2 * pulse)
		p.dot(x, 0.0, WHITE if u < 0.2 else (C[6] if u < 0.5 else C[5]), a)
		if u < 0.3:
			p.dot(x, 1.0, C[5] if u < 0.15 else C[4], 1.0 if u < 0.15 else 0.5)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	floor_(p, setup(t, o))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var s := setup(t, o)
	var C: Array = s.C
	var CY: float = s.CY
	var rx: float = s.rx
	var ry: float = s.ry
	var ph: float = s.ph
	var rim: Callable = s.rim
	var spots: Array = s.spots
	var pulse := 0.85 + 0.15 * sin(ph * TAU * 2.0)
	rift(p, s)
	well(p, s)
	orbit(p, s)
	infall(p, s)
	skaters(p, s)
	# light comes off the rim, not the void: a big soft pool, a halo hugging the rim, hot spots that shine, the floor lit
	p.glow(0.0, CY, ry * 5.0, C[4], 0.17 * pulse)
	p.glow(0.0, CY, ry * 2.6, C[4], 0.1 * pulse)
	for i in 16:
		var th := (i / 16.0) * TAU
		var R0: float = rim.call(th) * 1.08
		p.glow(cos(th) * R0 * rx, CY + sin(th) * R0 * ry, 15.0, C[4], 0.15 * pulse)
	for th: float in spots:
		p.glow(cos(th) * rim.call(th) * rx, CY + sin(th) * rim.call(th) * ry, 16.0, C[6], 0.42)
	for i in range(-3, 4):
		p.glow(i * 7.0, -1.0, 16.0, C[5], 0.12 * pulse)
