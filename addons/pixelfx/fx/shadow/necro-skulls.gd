# port-of: src/fx/shadow/necro-skulls.js@fbc8262598a79bd193eab4ecac05d60829065e91
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Necro skulls",
	"desc": "Spectral skulls circle a cold green flame on a tilted orbit, passing behind and before it, eyes lit, trailing curls of ghost smoke.",
	"tags": ["shadow", "necromancy", "skull", "orbit", "ghost", "spectral", "magic", "loop"],
	"size": [136, 116],
	"origin": [68, 108],
	"duration": 3,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#040e10", "#0a2228", "#0f3d44", "#16615f", "#23907f", "#45c4a0", "#9af0c8", "#e8fff4"],
		"bone": ["#0c1a1c", "#2c4a4a", "#5c847c", "#a6cdb8", "#e4fff0"],
		"seed": 6,
	},
}

# the flame's base and height; the orbit (centre, radii, tilt); six skulls, one turn a loop
const CY := -52.0
const FB := -32.0
const FH := 34.0
const RX := 42.0
const RY := 11.0
const TILT := -0.12
const D := 3.0
const N := 5
const SKULL := [
	"...kkkkk...",
	".kkhhhllkk.",
	"khhhhlllmmk",
	"khhllllllmk",
	"kleeeleeemk",
	"kleeeleeedk",
	"kmleelleedk",
	".kmllnllmk.",
	".kmmlnlmdk.",
	"..kmmmmmk..",
	"..ktgtgtk..",
	"...kkkkk...",
]


# a skull's place at t: round the tilted orbit, bobbing; z > 0 is in front of the flame
static func skullAt(i: float, t: float) -> Dictionary:
	var a := (TAU * t) / D + (i * TAU) / N
	var ex := cos(a) * RX
	var ey := sin(a) * RY
	var bob := sin((TAU * 2.0 * t) / D + i * 1.7) * 2.0
	return {"x": ex * cos(TILT) - ey * sin(TILT), "y": CY + ex * sin(TILT) + ey * cos(TILT) + bob, "z": sin(a), "a": a}


# ghost smoke curling off behind each skull along its orbit: puffs that swell, rise and thin with age
static func tail(p: Px.Painter, C: Array, i: float, t: float) -> void:
	var k := 8
	while k >= 1:
		var tt := t - k * 0.05
		var s := skullAt(i, tt)
		var age := k / 8.0
		var r := 2.0 + age * 3.6
		var a: float = (1.0 - age) * 0.5 * (0.6 + 0.4 * (s.z + 1.0) / 2.0)
		p.disc(s.x, s.y - age * 7.0 + 2.0, r, C[5] if age < 0.4 else (C[4] if age < 0.7 else C[3]), a)
		k -= 1


static func drawSkull(p: Px.Painter, C: Array, K: Array, s: Dictionary, t: float, i: float) -> void:
	var front: bool = s.z >= 0.0
	var depth: float = 0.55 + 0.45 * (s.z + 1.0) / 2.0
	var PAL := {"k": K[0], "d": K[1], "m": K[2], "l": K[3], "h": K[4], "e": C[0], "n": C[0], "t": K[3], "g": K[0]} if front else {"k": K[0], "d": K[0], "m": K[1], "l": K[2], "h": K[3], "e": C[0], "n": C[0], "t": K[2], "g": K[0]}
	var x0 := Px.round(s.x) - 5.0
	var y0 := Px.round(s.y) - 6.0
	p.sprite(SKULL, PAL, x0, y0)
	# eyes: cold points of light in the dark, flaring as the skull swings toward us
	var k := (0.5 + 0.5 * sin((TAU * 3.0 * t) / D + i * 2.1)) * 0.5 + 0.5
	for ex: float in [3.0, 7.0]:
		p.px(x0 + ex + 0.5, y0 + 5.5, (WHITE if k > 0.75 else C[7]) if front else C[6])
		if front:
			p.px(x0 + ex + 0.5, y0 + 4.5, C[5])
		p.glow(x0 + ex + 1.0, y0 + 6.0, 6.0, C[5], 0.45 * depth * k)
	p.glow(s.x, s.y, 11.0, C[4], 0.18 * depth)


# the cold flame: a body that swells off its base and tapers into licking tongues, white only low in its heart,
# cooling outward and upward through the ghost greens, scrolling up (the noise wraps once a loop)
static func flame(p: Px.Painter, C: Array, t: float) -> void:
	var W := 10.0
	var scroll := t / D
	p.shade(-W - 4.0, FB - FH - 4.0, W + 4.0, FB + 2.0, func(x, y, out):
		var u: float = (FB - y) / FH
		if u < -0.04 or u >= 1.0:
			return null
		var n1 := Px.tileNoise(x * 0.3, y * 0.2 + scroll * 8.0, 0.0, 8.0, 3)
		var n2 := Px.tileNoise(x * 0.6, y * 0.45 + scroll * 16.0, 0.0, 16.0, 5)
		var prof := 0.35 + 0.65 * sqrt(maxf(0.0, u) / 0.22) if u < 0.22 else pow(1.0 - (u - 0.22) / 0.78, 0.85)
		var w := W * prof * (1.0 + 0.3 * n1) + n2 * 2.2 * u
		var sway := n1 * 3.0 * u * u
		var d: float = absf(x - sway) / maxf(0.6, w)
		if d > 1.0:
			return null
		var heat := pow(1.0 - d, 0.7) * pow(maxf(0.0, 1.0 - u), 0.55) + n2 * 0.12
		if ((floori(x) + floori(y)) & 1) == 0:
			out.k = 0.16 * heat
		return WHITE if heat > 0.82 else (C[7] if heat > 0.66 else (C[6] if heat > 0.46 else (C[5] if heat > 0.27 else (C[4] if heat > 0.12 else C[3])))))
	p.glow(0.0, FB - FH * 0.35, 40.0, C[5], 0.45)
	p.glow(0.0, FB - 5.0, 12.0, C[7], 0.25)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var K := Px.fit(o.bone, 5)
	p.glow(0.0, -1.0, 40.0, C[4], 0.2)
	# the far half of the orbit: tails and skulls behind the flame, back to front
	var order := Px.arr(N, func(i): return [i, skullAt(i, t)]).filter(func(e): return e[1].z < 0.0)
	Px.sort(order, func(a, b): return a[1].z - b[1].z)
	for e: Array in order:
		tail(p, C, e[0], t)
	for e: Array in order:
		drawSkull(p, C, K, e[1], t, e[0])


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var K := Px.fit(o.bone, 5)
	var S: float = o.seed
	# motes and cold sparks rising off the flame
	Px.cycle(t, D, 18, S, func(r): return r.range(0.8, 1.4), func(age, L, r):
		var x0: float = r.range(-6.0, 6.0)
		var u: float = age / L
		var x: float = x0 + sin(u * 5.0 + r.range(0.0, 6.0)) * 3.0 * u
		var y: float = FB - 6.0 - u * r.range(36.0, 56.0)
		p.dot(x, y, C[7] if u < 0.5 else C[6], 1.0 if u < 0.7 else (1.0 - u) * 3.3)
		p.glow(x, y, 3.0, C[6], 0.3 * (1.0 - u)))
	flame(p, C, t)
	# the near half of the orbit, back to front
	var order := Px.arr(N, func(i): return [i, skullAt(i, t)]).filter(func(e): return e[1].z >= 0.0)
	Px.sort(order, func(a, b): return a[1].z - b[1].z)
	for e: Array in order:
		tail(p, C, e[0], t)
	for e: Array in order:
		drawSkull(p, C, K, e[1], t, e[0])
	Lib.halo(p, 0.0, CY, 0.0, 46.0, C[4], 0.12)
