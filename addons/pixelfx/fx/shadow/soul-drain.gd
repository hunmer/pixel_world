# port-of: src/fx/shadow/soul-drain.js@180649ad575376cfec76edaf4943a8274ae9a5fd
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Soul drain",
	"desc": "Pale souls are torn loose on the right and dragged down a funnel of streaks into a black crystal vessel, which flares violet as each one lands.",
	"tags": ["shadow", "soul", "drain", "necromancy", "funnel", "directional", "magic", "loop"],
	"size": [208, 120],
	"origin": [40, 110],
	"duration": 3.2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOID, "soul": ["#2c3f66", "#7d9fd0", "#cfe6ff", "#ffffff"], "seed": 8},
}

# the vessel's centre; the loop; the funnel's streamlines (start points out on the right); four souls a loop
const VY := -50.0
const D := 3.2
const LINES := 11
const SOULS := 4
const TRAVEL := 1.45


static func wrap_(x: float) -> float:
	return fmod(fmod(x, D) + D, D)


static func line(i: int) -> Dictionary:
	var sx := 96.0 + Px.rand(i, 1) * 64.0
	var sy := -88.0 + Px.rand(i, 2) * 72.0
	var bend := (Px.rand(i, 3) - 0.5) * 50.0
	return {"sx": sx, "sy": sy, "c1x": sx * 0.55, "c1y": sy + bend, "c2x": 22.0 + Px.rand(i, 4) * 14.0, "c2y": VY + (sy - VY) * 0.25}


static var LN := Px.arr(LINES, func(i): return line(i))


# a point along streamline i at u (0 at its start, 1 at the vessel), cubic bezier
static func along(L: Dictionary, u: float) -> Array:
	var v := 1.0 - u
	var a := v * v * v
	var b := 3.0 * v * v * u
	var c := 3.0 * v * u * u
	var d := u * u * u
	return [a * L.sx + b * L.c1x + c * L.c2x, a * L.sy + b * L.c1y + c * L.c2y + d * (VY - L.sy) + d * L.sy]


static func soul(j: int) -> Dictionary:
	return {"born": (j + 0.15 + Px.rand(j, 7) * 0.5) * (D / SOULS), "line": floori(Px.rand(j, 8) * LINES)}


static func landings(t: float) -> float:
	var f := 0.0
	for j in SOULS:
		var since := wrap_(t - soul(j).born - TRAVEL)
		f += exp(-since / 0.14) * (1.0 if since < 1.0 else 0.0)
	return minf(1.4, f)


# the vessel: a black crystal, two facets lit violet from inside, a hard ridge, a heart of stolen light
static func vessel(p: Px.Painter, C: Array, t: float, f: float) -> float:
	var y0 := VY + sin((TAU * t) / D) * 1.5
	var W := 9.0
	var UP := 14.0
	var DN := 12.0
	p.shade(-W - 1.0, y0 - UP - 1.0, W + 1.0, y0 + DN + 1.0, func(x, y):
		var dy: float = y - y0
		var half := W * (1.0 + dy / UP) if dy < 0.0 else W * (1.0 - dy / DN)
		if half <= 0.0 or absf(x) > half + 0.6:
			return null
		if absf(x) > half - 0.4:
			return C[6] if f > 0.5 else C[1]
		var ridge := absf(x + dy * 0.12) < 0.6
		var heart := absf(x) + absf(dy - 1.0) < 2.6 + f * 1.5
		if heart:
			return WHITE if f > 0.4 else C[6]
		if ridge:
			return C[7] if f > 0.3 else C[5]
		if x < 0.0:
			return (C[5] if f > 0.2 else C[4]) if dy < 0.0 else C[3]
		return C[2] if dy < 0.0 else C[1])
	p.glow(0.0, y0, 30.0 + 14.0 * f, C[5], 0.5 + 0.5 * f)
	p.glow(0.0, y0 + 1.0, 8.0, WHITE, 0.25 + 0.6 * f)
	return y0


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	# the funnel: streamlines bunching into the vessel, dashes running down them, brighter as they close in
	for i in LINES:
		var L: Dictionary = LN[i]
		var ph := wrap_(t + i * 0.37) / D
		var px: Variant = null
		var py: Variant = null
		var u := 0.0
		while u <= 1.0001:
			var xy := along(L, u)
			var x: float = xy[0]
			var y: float = xy[1]
			var dash := fmod(fmod(u * 5.0 - ph * 10.0 + i * 0.3, 1.0) + 1.0, 1.0)
			# a faint line the whole way, bright dashes riding it inward, all brighter as it narrows
			if px != null:
				p.line(px, py, x, y, C[3] if u > 0.6 else C[2], 0.4 + 0.6 * u)
			if dash < 0.18:
				p.px(x, y, C[7] if u > 0.7 else (C[6] if u > 0.35 else C[5]))
			px = x
			py = y
			u += 0.01
	p.glow(10.0, VY, 40.0, C[4], 0.22)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var S := Px.fit(o.soul, 4)
	var f := landings(t)
	# where the souls are torn from: a faint pale haze out on the right
	Px.cycle(t, D, 10, o.seed, func(r): return r.range(0.8, 1.3), func(age, Lf, r):
		var x: float = r.range(100.0, 150.0)
		var y: float = r.range(-80.0, -20.0) - age * 18.0
		var u: float = age / Lf
		p.dot(x, y, S[2], (1.0 - u) * 0.8)
		p.glow(x, y, 4.0, S[1], 0.2 * (1.0 - u)))
	# streaks racing down the funnel, faster as they close on the vessel, white at the head
	Px.cycle(t, D, 22, o.seed + 1.0, func(r): return r.range(0.4, 0.7), func(age, Lf, r):
		var L: Dictionary = LN[floori(r.next() * LINES)]
		var u0: float = r.range(0.15, 0.5)
		var q := u0 + (1.0 - u0) * pow(age / Lf, 2.2)
		var q2 := u0 + (1.0 - u0) * pow(maxf(0.0, age - 0.06) / Lf, 2.2)
		var a := along(L, q)
		var b := along(L, q2)
		p.line(b[0], b[1], a[0], a[1], func(v): return WHITE if v > 0.7 else (C[6] if v > 0.35 else C[4]))
		p.glow(a[0], a[1], 4.0, C[6], 0.35))
	var y0 := vessel(p, C, t, f)
	# motes circling the vessel, in front and behind it
	for k in 6:
		var a := (TAU * (2.0 * t)) / D + (k * TAU) / 6.0
		var ex := cos(a) * 15.0
		var ey := sin(a) * 5.0 - 2.0
		var z := sin(a)
		p.px(ex, y0 + ey, C[7] if z > 0.0 else C[4])
		if z > 0.0:
			p.glow(ex, y0 + ey, 4.0, C[6], 0.35)
	# the souls: a pale head with hollow eyes and an open mouth, a wavering tail, dragged faster as they go
	for j in SOULS:
		var s := soul(j)
		var age := wrap_(t - s.born)
		if age > TRAVEL:
			continue
		var L: Dictionary = LN[s.line]
		var u := pow(age / TRAVEL, 1.8)
		var xy := along(L, u)
		var x: float = xy[0]
		var y: float = xy[1]
		if age < 0.18:
			var k := 1.0 - age / 0.18
			Lib.ringFast(p, L.sx, L.sy, 3.0 + 9.0 * (1.0 - k), 1.0, S[2] if k > 0.5 else S[1])
			p.glow(L.sx, L.sy, 12.0, S[1], 0.5 * k)
		# the tail: a wavering wisp, pale near the head, thinning to violet
		var k := 14
		while k >= 1:
			var uu := pow(maxf(0.0, age - k * 0.03) / TRAVEL, 1.8)
			var txy := along(L, uu)
			var w := sin(t * 12.0 + k * 0.8 + j) * k * 0.16
			var r := maxf(0.5, 2.6 - k * 0.17)
			p.disc(txy[0], txy[1] + w, r, S[2] if k < 4 else (S[1] if k < 9 else C[5]), 0.75 * (1.0 - k / 15.0))
			k -= 1
		# the head: a pale round face, hollow eyes and an open mouth, a lit rim, stretched as it nears the vessel
		var near := Px.smooth(0.82, 1.0, u)
		var hr := 3.4 - near * 1.6
		p.circle(x, y, hr + 0.8, S[1])
		p.circle(x, y, hr, S[2])
		p.px(x - 1.0, y - 2.0, S[3])
		p.px(x - 2.0, y - 1.0, S[3])
		if near < 0.5:
			p.px(x - 1.5, y, S[0])
			p.px(x + 1.5, y, S[0])
			p.px(x, y + 1.6, S[0])
			p.px(x, y + 2.4, S[0])
		p.glow(x, y, 10.0, S[1], 0.5)
	# each landing: a flash in the heart, a ring off the crystal, a glint
	for j in SOULS:
		var since := wrap_(t - soul(j).born - TRAVEL)
		if since < 0.3:
			var k := since / 0.3
			Lib.ringFast(p, 0.0, y0, 6.0 + 18.0 * Px.Ease.outCubic(k), maxf(1.0, 2.0 * (1.0 - k)), C[7] if k < 0.4 else (C[5] if k < 0.7 else C[3]))
	Lib.halo(p, 0.0, y0, 4.0, 22.0, C[6], 0.25 * f)
