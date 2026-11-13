# The banded light (posterized steps from a white-hot core out to deep color, fine strands running through it,
# pulses travelling along, light laid over the top) is adapted from Sprite Fusion's open-source holy light
# (https://www.spritefusion.com/pixel-art-vfx/holy-light), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/aurora.js@64b81a2be72cb56f49bc9c37ab228f54322d64f2
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Aurora",
	"desc": "Rippling curtains of green-to-violet light over a starfield: folding hems burn bright, rays shimmer up into violet, and the whole sky slowly breathes.",
	"tags": ["weather", "aurora", "northern lights", "sky", "night", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 180],
	"duration": 12.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#081a1e", "#0d3a36", "#13664e", "#1fa06a", "#3fd88e", "#9af7bf", "#e6fff0"],
		"upper": ["#120b2a", "#26164f", "#41208a", "#6a34c0", "#9c62e8", "#d2b4ff", "#f6eeff"],
		"seed": 3,
	},
}

const D := 12.0
const W := 320
const H := 180
static var BAY := PackedFloat64Array([0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map(func(v): return (v + 0.5) / 16.0))
static var I := _f32(W * H)
static var HV := _f32(W * H)
static var BL := _f32(W * H)
static var TMP := _f32(W * H)


static func _f32(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	return a


# a curtain's light from its hem (v = 0) up its rays (v = 1): a bright hem, a body that holds, rays fading up
# into the dark. Tabled in steps of 1/200. Below the hem there's only a skirt of glow a few pixels deep.
static var PROF := PackedFloat32Array(Px.arr(201, func(i: int) -> float:
	var v := i / 200.0
	return 2.6 if v < 0.035 else (1.15 - v if v < 0.22 else pow(1 - v, 1.5) * 0.9)))


# a soft bloom of the light: a box blur of radius r, across then down, by running sums
static func blur(src: PackedFloat32Array, dst: PackedFloat32Array, r: int) -> void:
	var n := 2 * r + 1
	var tmp := TMP
	for y in H:
		var acc := 0.0
		var o := y * W
		for x in range(-r, W + r):
			if x + r < W:
				acc += src[o + mini(W - 1, x + r)]
			if x - r - 1 >= 0:
				acc -= src[o + x - r - 1]
			if x >= 0 and x < W:
				tmp[o + x] = acc / n
	for x in W:
		var acc := 0.0
		for y in range(-r, H + r):
			if y + r < H:
				acc += tmp[mini(H - 1, y + r) * W + x]
			if y - r - 1 >= 0:
				acc -= tmp[(y - r - 1) * W + x]
			if y >= 0 and y < H:
				dst[y * W + x] = acc / n


static func cyc(t: float, c: float, ph: float = 0.0) -> float:
	return (TAU * c * t) / D + ph


# the curtains, back to front: where each hangs, how it folds and ripples, how tall its rays reach
const CURTAINS := [
	{"y": -132.0, "slope": -0.08, "amp": 8.0, "lam": 210.0, "fold": 14.0, "flam": 150.0, "height": 40.0, "k": 0.6, "s0": -210.0, "s1": 210.0, "rip": 1.6, "c": [1.0, 1.0, 2.0], "hue": 0.35},
	{"y": -88.0, "slope": 0.22, "amp": 13.0, "lam": 250.0, "fold": 19.0, "flam": 165.0, "height": 82.0, "k": 1.5, "s0": -195.0, "s1": 180.0, "rip": 2.4, "c": [1.0, 2.0, 3.0], "hue": 0.0},
	{"y": -38.0, "slope": -0.05, "amp": 5.0, "lam": 150.0, "fold": 10.0, "flam": 110.0, "height": 20.0, "k": 0.45, "s0": -210.0, "s1": 210.0, "rip": 1.4, "c": [2.0, 1.0, 3.0], "hue": 0.0},
]


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var B := Lib.box(meta)
	var S: float = o.seed
	var G := Px.fit(o.palette, 7)
	var U := Px.fit(o.upper, 7)
	stars(q, t, S, G, U)
	I.fill(0)
	HV.fill(0)
	var F := Lib.field(S * 5 + 1, 256, 128, [8, 16, 32])
	var breath := 0.75 + 0.25 * sin(cyc(t, 1, -1.2))
	var rays := []
	for n in CURTAINS.size():
		curtain(q, CURTAINS[n], n, t, F, breath, rays, G)
	blur(I, BL, 5)
	# shade: hue by height (green at the hem, violet up the rays), brightness by intensity in posterized steps.
	# Faint light is only light, so the stars shine through it; the bright parts get crisp color too.
	var GM := []
	for i in G.size():
		GM.append(Px.mix(G[i], U[i], 0.5))
	var by0: int = B.y0
	var Iv := I
	var HVv := HV
	var BLv := BL
	var BY := BAY
	var G4: int = G[4]
	var U4: int = U[4]
	var GM4: int = GM[4]
	Lib.rows(p, meta, B.y0, -12, func(y: float, R: Lib.Row) -> void:
		var Rc := R.c
		var Ra := R.a
		var Rb := R.b
		var Rl := R.l
		var Rk := R.k
		var base := (floori(y) - by0) * W
		var by := (floori(y) & 3) << 2
		for xi in W:
			var i := base + xi
			var raw := Iv[i]
			var bl := BLv[i]
			var k := minf(0.4, bl * 0.6) if bl > 0.015 else 0.0
			if raw >= 0.03:
				var e := (raw * 1.5) / (1 + raw * 1.5)
				var v := HVv[i] / raw
				var th := BY[by | (xi & 3)] * 0.06 if e > 0.45 else 0.0
				var lv := 6 if e > 0.86 + th else (5 if e > 0.72 + th else (4 if e > 0.56 + th else (3 if e > 0.4 + th else (2 if e > 0.24 else 1))))
				if v > 0.35:
					lv = mini(lv, 5)
				var c: int = G[lv] if v < 0.3 else (GM[lv] if v < 0.5 else U[lv])
				if lv >= 3:
					Rc[xi] = c
					Ra[xi] = Px.clamp((e - 0.3) * 2.2)
					Rb[xi] = 1 if lv < 5 else 0
				Rl[xi] = ((G4 if v < 0.4 else U4) if lv >= 3 else (G4 if c == G[lv] else (U4 if c == U[lv] else GM4)))
				k += e * (0.28 if lv >= 3 else 0.72)
			else:
				Rl[xi] = G4
			Rk[xi] = k)
	# the brightest rays as fine strands of light, fading up into violet
	for r: Dictionary in rays:
		var n := Px.round(r.h)
		var j := 1
		while j < n:
			var u := j / n
			q.blend(r.x, r.hem - j, G[5] if u < 0.35 else (Px.mix(G[5], U[5], 0.5) if u < 0.6 else U[5]), r.k * pow(1 - u, 1.3))
			j += 1
		q.px(r.x, r.hem, G[6])


# one curtain: walk along it, drop each ray's light into the columns it covers; where it folds back on itself
# along the line of sight the light piles up, so folds burn brightest
static func curtain(_q: Px.Painter, c: Dictionary, n: int, t: float, F: Lib.Field, breath: float, rays: Array, _G: Array) -> void:
	var X0 := -160.0
	var Y0 := -180.0
	var fast := (256 * 2 * t) / D
	var slow := (256 * t) / D
	var p1 := 0.0
	var p2 := 0.0
	var lastX := -999.0
	var cy: float = c.y
	var slope: float = c.slope
	var amp: float = c.amp
	var lam: float = c.lam
	var fold: float = c.fold
	var flam: float = c.flam
	var height: float = c.height
	var ck: float = c.k
	var s0: float = c.s0
	var s1: float = c.s1
	var rip: float = c.rip
	var cc: Array = c.c
	var hue: float = c.hue
	var Iv := I
	var HVv := HV
	var prof := PROF
	var s := s0
	while s < s1:
		var sv := s
		s += 0.5
		var x := sv + fold * sin((TAU * sv) / flam + cyc(t, cc[0], n * 2)) + 5 * sin((TAU * sv) / 64 + cyc(t, cc[2], n))
		if x < X0 - 2 or x >= X0 + W + 1:
			continue
		var hem := cy + slope * sv + amp * sin((TAU * sv) / lam + cyc(t, cc[1], n * 1.7)) + rip * sin((TAU * sv) / 23 - cyc(t, 7, n))
		var env := Px.smooth(s0, s0 + 60, sv) * (1 - Px.smooth(s1 - 70, s1, sv))
		# rays: fine strands drifting along the curtain, each with its own height; bright patches running along it
		var r1 := Px.clamp((Lib.sample(F, sv * 5 - fast + n * 40, 10 + n * 30) - 0.38) * 3.2)
		var r2 := Px.clamp((Lib.sample(F, sv * 4.3 + fast * 0.7 + n * 90, 50 + n * 13) - 0.35) * 3)
		var patch := Lib.sample(F, sv * 0.7 + slow + n * 17, 80 + n * 9)
		var k := ck * env * breath * (0.2 + 0.8 * r1) * (0.3 + 1.4 * maxf(0, patch - 0.3))
		if k < 0.01:
			continue
		var h := height * (0.45 + 0.75 * r2) * (0.75 + 0.5 * patch)
		var xi := floorf(x - X0)
		var fr := x - X0 - xi
		# a ray peaks here: keep it as a strand; and a soft bloom along the bright hem
		if p1 > 0.75 and p1 >= p2 and p1 >= r1 and absf(x - lastX) > 2 and k > 0.25:
			rays.append({"x": x, "hem": hem - 1, "h": h * 0.9, "k": minf(0.85, k * 0.9)})
			lastX = x
		p2 = p1
		p1 = r1
		if xi < -1 or xi >= W:
			continue
		var top := maxf(0, floorf(hem - h - Y0))
		var bot := minf(H - 1, floorf(hem - Y0) + 3)
		var inv := 1 / h
		var k0 := k * 0.5 * (1 - fr)
		var k1 := k * 0.5 * fr
		var v := (hem - Y0 - 0.5 - top) * inv
		var X := int(xi)
		for yi in range(int(top), int(bot) + 1):
			var vv := v
			v -= inv
			# above the hem: the ray; below it: a skirt of glow gone within three pixels
			var pr := prof[mini(200, int(vv * 200))] if vv >= 0 else maxf(0, 0.45 + vv * h * 0.16)
			var o := yi * W + X
			var hv := 0.0 if vv + hue < 0 else (1.0 if vv + hue > 1 else vv + hue)
			if pr <= 0:
				continue
			if X >= 0:
				Iv[o] += k0 * pr
				HVv[o] += k0 * pr * hv
			if X + 1 < W:
				Iv[o + 1] += k1 * pr
				HVv[o + 1] += k1 * pr * hv


# the starfield: dim specks, steady stars, a few bright ones that twinkle with a glint
static func stars(q: Px.Painter, t: float, S: float, _G: Array, U: Array) -> void:
	for i in 150:
		var x := -160 + Px.rand(S, i, 1) * 320
		var y := -180 + Px.rand(S, i, 2) * 175
		var r := Px.rand(S, i, 3)
		var c := 1 + floorf(Px.rand(S, i, 4) * 4)
		var tw := 0.5 + 0.5 * sin(cyc(t, c, Px.rand(S, i, 5) * TAU))
		var col := Px.mix(U[3], Px.WHITE, 0.2) if r < 0.6 else (Px.mix(U[5], Px.WHITE, 0.5) if r < 0.9 else Px.WHITE)
		if r < 0.6:
			q.dot(x, y, col, 0.35 + 0.5 * tw)
		elif r < 0.95:
			q.px(x, y, col)
			q.glow(x + 0.5, y + 0.5, 3, U[5], 0.25 * tw)
		else:
			Px.sparkle(q, x, y, 1 + Px.round(tw * 2), Px.mix(U[5], Px.WHITE, 0.6), U[4], 0.35 * tw)
