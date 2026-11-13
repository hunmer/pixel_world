# Rocks torn out of the floor with a puff of dust, then hauled up spinning, and matter drawn in as streaks,
# follow Sprite Fusion's open-source black hole (https://www.spritefusion.com/pixel-art-vfx/black-hole),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/scifi/tractor-beam.js@120b64de16152b0598d963091f71d019bf8c0115
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Tractor beam",
	"desc": "A hovering pod projects a cone of light to the floor; rocks tear loose in puffs of dust and spiral up spinning into the lens while rings of light climb the beam.",
	"tags": ["scifi", "beam", "tractor", "lift", "abduct", "debris", "ground", "loop"],
	"size": [120, 132],
	"origin": [60, 114],
	"duration": 3,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#06161a", "#0b2e33", "#11505a", "#1a7f84", "#2bb5a8", "#7ef0c8", "#d6fff0", "#ffffff"],
		"hull": ["#0d0f17", "#1c2030", "#2e3448", "#4a5470", "#7a86a8", "#b8c4e0"],
		"stone": ["#1a1622", "#2e2838", "#4a4258", "#6d6480", "#9a90aa"],
		"seed": 9,
	},
}

static var D: float = meta.duration
const LENS := -84.0
const TOPW := 5.5
const BOTW := 32.0


# the cone's half width at height y
static func half(y: float) -> float:
	return Px.lerp(BOTW, TOPW, Px.clamp(y / LENS))


# where something hauled up the beam is at progress k (0 on the floor, 1 in the lens): quickening as it
# rises, winding round the axis and in toward it. [x, y, depth (> 0 on the near side)]
static func haul(r0: float, th0: float, dir: float, turns: float, k: float) -> Array:
	var s := pow(Px.clamp(k), 1.8)
	var y := Px.lerp(-2.0, LENS + 5.0, s)
	var th := th0 + dir * TAU * turns * s
	var rr := r0 * (half(y) / BOTW) * (1.0 - 0.5 * s)
	return [cos(th) * rr, y, sin(th)]


# a rock's life: it pops out of the floor, wobbles a beat, then spirals up into the lens
const POP := 0.1
const HOVER := 0.32
const RISE := 1.4
const LIFE := POP + HOVER + RISE


static func rockAt(r: Dictionary, age: float) -> Dictionary:
	var lift := Px.clamp((age - POP - HOVER) / RISE)
	if lift > 0.0:
		var a := haul(r.r0, r.th0, r.dir, 1.3, lift)
		var b := haul(r.r0, r.th0, r.dir, 1.3, lift - 0.07)
		return {"x": a[0], "y": a[1], "z": a[2], "px": b[0], "py": b[1], "size": r.s * (1.0 - 0.6 * pow(lift, 2.5)), "a": r.a0 + r.va * age * (0.3 + lift * 2.0), "lift": lift}
	var y := Px.lerp(3.0, -2.0, age / POP) if age < POP else -2.0 - 2.0 * Px.smooth(0.0, HOVER, age - POP)
	var wob: float = sin(age * 55.0 + r.th0 * 9.0) * 0.7 if age > POP else 0.0
	return {"x": cos(r.th0) * r.r0 + wob, "y": y, "z": 1.0, "size": r.s, "a": r.a0 + r.va * age * 0.3, "lift": 0.0}


# a tumbling chunk of stone: an uneven outline, lit from above by the lens, shaded underneath
static func rock(p: Px.Painter, q: Dictionary, r: Dictionary, S: Array, C: Array, back: bool) -> void:
	var n := 6
	var R: float = maxf(0.9, q.size)
	var ca := cos(q.a)
	var sa := sin(q.a)
	var lit := Px.mix(S[4], C[6], 0.3 + 0.6 * q.lift)
	var rid: float = r.id
	var rad := func(ang: float) -> float:
		var f := fmod(fmod((ang / TAU) * n, n) + n, n)
		var i := floori(f)
		var k := f - i
		return R * (0.75 + 0.35 * Px.lerp(Px.rand(rid, i), Px.rand(rid, (i + 1) % n), k))
	# a faint trail of its rush up the beam
	if q.lift > 0.15 and not back:
		p.line(q.px, q.py, q.x, q.y, func(u: float): return C[5] if u > 0.6 else C[3], func(u: float): return 0.7 * u)
		for i in range(1, 4):
			p.disc(Px.lerp(q.x, q.px, i / 3.0), Px.lerp(q.y, q.py, i / 3.0) + 1.0, R * (0.5 + 0.25 * i), Px.mix(S[3], C[5], 0.4), 0.22 * (1.0 - i / 4.0) * q.lift)
	var qx: float = q.x
	var qy: float = q.y
	var qlift: float = q.lift
	p.shade(qx - R - 2.0, qy - R - 2.0, qx + R + 2.0, qy + R + 2.0, func(x: float, y: float, out):
		var dx := x - qx
		var dy := y - qy
		var u := dx * ca + dy * sa
		var v := -dx * sa + dy * ca
		var d := Px.hypot(u, v)
		var e: float = rad.call(atan2(v, u))
		if d > e + 0.8:
			return
		out.c = S[0] if d > e else ((S[3] if dy < -0.3 * R else S[1]) if back else ((C[6] if (qlift > 0.35 and d > e - 1.0) else lit) if dy < -0.45 * R else ((S[4] if dx < 0.0 else S[3]) if dy < -0.1 * R else (S[1] if dy > 0.35 * R else S[2])))))
	if not back and q.lift > 0.0:
		p.glow(q.x, q.y - R, 5.0 + R, C[5], 0.25 * q.lift)


# the hovering pod: a cockpit dome on a wide hull, a rim of running lights, the lens underneath
static func pod(p: Px.Painter, t: float, C: Array, H: Array, y0: float) -> void:
	var y := Px.round(y0)
	p.shade(-21.0, y - 12.0, 21.0, y + 6.0, func(x: float, yy: float, out):
		var dy := yy - y
		# the cockpit: a small glassy dome, a hot glint top left
		var cx := x / 8.5
		var cy := (dy + 5.0) / 6.0
		if cy < 0.0 and cx * cx + cy * cy <= 1.0:
			var d := cx * cx + cy * cy
			var l := -cx * 0.6 - cy * 0.8
			out.c = H[0] if d > 0.8 else (WHITE if l > 0.85 else (C[6] if l > 0.6 else (C[4] if l > 0.2 else C[3])))
			return
		# the hull: a flat lens shape, lit on its upper face, a dark seam, the rim
		var hx := x / 20.0
		var hy := (dy + 0.5) / 4.5
		if dy <= 0.0 and hx * hx + hy * hy <= 1.0:
			var d := hx * hx + hy * hy
			var l := -hx * 0.55 - hy * 0.7
			out.c = H[0] if d > 0.88 else (H[1] if dy == -2.0 else (H[5] if l > 0.55 else (H[4] if l > 0.25 else (H[3] if l > -0.1 else H[2]))))
			return
		# the underside, tapering in toward the lens housing, lit from below by its own beam
		var w := 19.5 - dy * 2.4
		if dy > 0.0 and dy <= 5.0 and absf(x) <= w:
			out.c = H[0] if absf(x) > w - 1.0 else (H[2] if dy == 1.0 else (C[3] if (dy >= 4.0 and absf(x) < 9.0) else H[1])))
	# running lights chase round the rim
	for i in 6:
		var lx := -15.0 + i * 6
		var k := 0.5 + 0.5 * cos(TAU * (4.0 * (t / D) - i / 6.0))
		p.px(lx, y + 1.0, WHITE if k > 0.7 else (C[5] if k > 0.35 else C[2]))
		if k > 0.5:
			p.glow(lx, y + 1.0, 5.0, C[5], 0.35 * k)
	# the lens: a white-hot eye in a ring of light
	p.ellipse(0.0, y + 5.5, 7.5, 2.2, func(d: float): return WHITE if d < 0.45 else (C[6] if d < 0.75 else (C[5] if d < 0.9 else C[3])))


# a ring of light round the beam at height y: a hard line in front, a fainter one for the far side
static func hoop(p: Px.Painter, y: float, rx: float, c: int, back: bool) -> void:
	var ry := rx * 0.17
	var n := ceili(rx * 7.0)
	for i in n:
		var g := (i / float(n)) * TAU
		var s := sin(g)
		if (s >= 0.0) == back:
			continue
		p.px(cos(g) * rx, y + s * ry, c)


static var cache := {}


static func setup(o: Dictionary) -> Dictionary:
	var key := "%s:%s:%s" % [o.seed, o.palette, o.stone]
	if cache.has(key):
		return cache[key]
	var C := Px.fit(o.palette, 8)
	var S := Px.fit(o.stone, 5)
	var rn := Px.Rng.new(o.seed)
	# rocks torn up one after another, from spots left and right of the middle
	var rocks := []
	for i in 7:
		var id: float = i + o.seed * 31.0
		var born := (i / 7.0) * D + rn.range(-0.06, 0.06)
		var r0 := rn.range(8.0, 25.0)
		var th0 := (0.0 if i % 2 else PI) + rn.range(-0.45, 0.45)
		var dir := rn.sign()
		var s := rn.range(2.4, 4.4)
		var a0 := rn.range(0.0, TAU)
		var va := rn.range(-7.0, 7.0)
		rocks.append({"id": id, "born": born, "r0": r0, "th0": th0, "dir": float(dir), "s": s, "a0": a0, "va": va})
	var g := Lib.Ghosts.new(D, {"ground": func(): return 0.0, "box": [-58.0, -112.0, 58.0, 14.0]})
	# each rock leaves the floor in a puff of dust and a spray of grit
	for r: Dictionary in rocks:
		var x: float = cos(r.th0) * r.r0
		for i in 5:
			g.add(r.born + 0.02, P.DUST, x + rn.range(-3.0, 3.0), -1.0, rn.range(-34.0, 34.0), -rn.range(8.0, 26.0), rn.range(0.5, 0.9), Px.mix(S[3], C[4], 0.3), rn.range(2.2, 3.6))
		for i in 6:
			g.add(r.born + 0.02, P.GRIT, x + rn.range(-2.0, 2.0), -2.0, rn.range(-45.0, 45.0), -rn.range(60.0, 150.0), rn.range(0.5, 0.9), rn.pick([S[2], S[3], S[4]]), 2.0 if rn.chance(0.3) else 1.0)
	# dust always swirling round the foot of the beam
	for i in 16:
		var s := rn.sign()
		g.add(rn.range(0.0, D), P.DUST, s * rn.range(14.0, 34.0), -rn.range(0.0, 3.0), -s * rn.range(6.0, 22.0), -rn.range(4.0, 14.0), rn.range(0.9, 1.5), Px.mix(S[3], C[5], 0.3), rn.range(2.6, 4.4))
	var v := {"C": C, "S": S, "rocks": rocks, "g": g}
	cache[key] = v
	return v


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var st := setup(o)
	var C: Array = st.C
	var S: Array = st.S
	var rocks: Array = st.rocks
	var g: Lib.Ghosts = st.g
	# the pool of light where the beam meets the floor, and the far half of its rim
	for yi in range(-6, 7):
		var y := float(yi)
		var x := -BOTW
		while x <= BOTW:
			var d := Px.hypot((x + 0.5) / BOTW, (y + 0.5) / 5.5)
			if d <= 1.0:
				p.blend(x + 0.5, y + 0.5, C[6] if d < 0.35 else C[5], 0.2 + 0.55 * pow(1.0 - d, 1.5))
			x += 1.0
	hoop(p, 0.0, BOTW + 1.0, C[5], true)
	g.at(t).draw(p, "back")
	# rocks on the far side of the beam, seen through it
	for r: Dictionary in rocks:
		var age := Lib.since(t, r.born, D)
		if age >= LIFE:
			continue
		var q := rockAt(r, age)
		if q.z < 0.0 and q.lift > 0.0:
			rock(p, q, r, S, C, true)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var st := setup(o)
	var C: Array = st.C
	var S: Array = st.S
	var rocks: Array = st.rocks
	var g: Lib.Ghosts = st.g
	var H := Px.fit(o.hull, 6)
	var ph := t / D
	var podY := LENS - 5.0 + 1.5 * sin(TAU * 2.0 * ph)
	var seed: float = o.seed
	# the beam: a glassy cone, white-hot at the lens, hard bright edges with a soft fringe, light drifting in it
	var y := ceilf(LENS + 3.0)
	while y < 0.0:
		var w := half(y)
		var v := (y - LENS) / -LENS
		var pulse := 1 if fmod(fmod(v * 3.2 + ph * 6.0, 1.0) + 1.0, 1.0) < 0.08 else 0
		var x := floorf(-w) - 1.0
		while x <= ceilf(w):
			var q := absf(x + 0.5) / w
			if q > 1.0 + 1.2 / w:
				x += 1.0
				continue
			if q > 1.0:
				p.dot(x, y, C[4], 0.6 - 0.3 * v)
			elif q > 1.0 - 1.0 / w:
				p.px(x, y, WHITE if v < 0.2 else (C[6] if v < 0.45 else C[5]))
			else:
				var curtain := 0
				for s in 4:
					if absf((x + 0.5) / w - (Px.rand(seed, s, 7) - 0.5) * 1.4 - 0.12 * sin(TAU * ph + s * 1.7)) < 0.045:
						curtain = 1
				var core := pow(1.0 - q, 2.0) * pow(1.0 - v, 1.6)
				var a := 0.08 + 0.22 * pow(q, 4.0) + 0.6 * core + 0.12 * pulse + 0.18 * curtain
				p.blend(x + 0.5, y + 0.5, WHITE if core > 0.45 else (C[5] if (curtain or pulse or v < 0.35) else C[4]), Px.clamp(a))
			x += 1.0
		if (int(y) & 3) == 0:
			for s: float in [-1.0, 1.0]:
				p.glow(s * w, y, 8.0, C[4], 0.18)
		y += 1.0
	# rings climbing the beam, quickening and narrowing with it
	for i in 5:
		var k := Lib.since(t, (i / 5.0) * D, D) / 1.1
		if k >= 1.0:
			continue
		var ry := Px.lerp(0.0, LENS + 5.0, Px.Ease.inQuad(k))
		var w := half(ry) + 1.0
		hoop(p, ry, w, C[3], true)
		hoop(p, ry, w, WHITE if k < 0.12 else C[6], false)
		p.glow(0.0, ry + w * 0.17, w + 4.0, C[5], 0.12)
	# light streaks drawn up the beam
	Px.cycle(t, D, 22, seed + 1.0, func(r: Px.Rng): return r.range(0.6, 1.0), func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var yy := Px.lerp(-2.0, LENS + 5.0, k * k)
		var w := half(yy)
		var x := r.range(-0.85, 0.85) * w
		var L := 2.0 + 6.0 * k
		p.line(x, yy, x, yy + L, func(u: float): return WHITE if u < 0.3 else C[5], minf(1.0, (1.0 - k) * 3.0)))
	# dust drawn up in soft puffs, thinning as it goes
	Px.cycle(t, D, 9, seed + 3.0, func(r: Px.Rng): return r.range(1.4, 2.0), func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var xy := haul(r.range(8.0, 26.0), r.range(0.0, TAU), r.sign(), 0.8, k)
		p.disc(xy[0], xy[1], Px.lerp(4.0, 1.5, k), Px.mix(S[3], C[5], 0.25 + 0.5 * k), 0.4 * minf(1.0, k * 6.0) * (1.0 - k)))
	# grit and motes of light hauled up in a quick spiral, streaking as they go
	Px.cycle(t, D, 46, seed + 2.0, func(r: Px.Rng): return r.range(0.8, 1.3), func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var r0 := r.range(6.0, 30.0)
		var th0 := r.range(0.0, TAU)
		var dir := r.sign()
		var turns := r.range(1.0, 1.8)
		var mote := r.chance(0.45)
		var a := haul(r0, th0, dir, turns, k)
		var b := haul(r0, th0, dir, turns, k - (0.13 if mote else 0.06))
		var x: float = a[0]
		var yy: float = a[1]
		var z: float = a[2]
		var c: int = (WHITE if r.chance(0.5) else C[6]) if mote else r.pick([S[3], S[4], S[4]])
		p.line(b[0], b[1], x, yy, func(u: float): return ((c if z > 0.0 else Px.scale(c, 0.7)) if u > 0.5 else (C[4] if mote else S[2])))
		if mote:
			p.px(x, yy, WHITE)
			p.glow(x, yy, 4.0, C[5], 0.45))
	# twinkles caught in the light
	Px.cycle(t, D, 8, seed + 4.0, 0.5, func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var xy := haul(r.range(4.0, 24.0), r.range(0.0, TAU), r.sign(), 0.6, r.range(0.1, 0.7) + k * 0.15)
		var arm := Px.round(2.0 * sin(PI * k))
		if arm > 0.0:
			Px.sparkle(p, xy[0], xy[1], arm, C[6], C[5], 0.4))
	# the rocks on the near side and those still on the floor
	for r: Dictionary in rocks:
		var age := Lib.since(t, r.born, D)
		if age >= LIFE:
			continue
		var q := rockAt(r, age)
		if q.z >= 0.0 or q.lift <= 0.0:
			rock(p, q, r, S, C, false)
		# swallowed: a glint at the lens
		if age > LIFE - 0.1:
			Px.sparkle(p, q.x, LENS + 3.0, 5.0, C[6], C[5], 0.5)
	for r: Dictionary in rocks:
		Lib.flash(p, t, r.born + LIFE - 0.08, 0.0, LENS + 3.0, 30.0, C[5], 0.7, 0.28)
	g.at(t).draw(p, "front")
	hoop(p, 0.0, BOTW + 1.0, WHITE, false)
	hoop(p, 1.0, BOTW, C[5], false)
	# light: the lens, the beam's body, the pool on the floor
	pod(p, t, C, H, podY)
	var fl := 0.85 + 0.15 * sin(TAU * 6.0 * ph)
	p.glow(0.0, LENS + 6.0, 36.0, C[5], 0.7 * fl)
	p.glow(0.0, LENS + 6.0, 12.0, WHITE, 0.7 * fl)
	var gy := LENS + 16.0
	while gy < -8.0:
		p.glow(0.0, gy, half(gy) + 10.0, C[4], 0.16)
		gy += 14.0
	for x: float in [-20.0, 0.0, 20.0]:
		p.glow(x, -2.0, 22.0, C[4], 0.26)
