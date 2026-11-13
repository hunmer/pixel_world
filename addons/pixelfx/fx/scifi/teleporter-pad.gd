# The rising band and the column of light it rides in follow Sprite Fusion's open-source heal
# (https://www.spritefusion.com/pixel-art-vfx/heal), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/scifi/teleporter-pad.js@17aa24bb28e13edf7a8a429b3a5aba7e5cad8eee
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Teleporter pad",
	"desc": "A steel pad glows on the floor, its rings rippling outward; a soft column of light rises off it and rings of light lift away, sparkles drifting up through them.",
	"tags": ["scifi", "teleporter", "pad", "portal", "beam", "spawn", "ground", "loop"],
	"size": [96, 104],
	"origin": [48, 92],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#120a26", "#26145a", "#3c2296", "#5a3ad2", "#7f66f0", "#b4a2ff", "#e6deff", "#ffffff"],
		"metal": ["#0e0d14", "#1e1c27", "#312e3e", "#4b4759", "#6f6a82", "#9d98b0"],
		"seed": 26,
	},
}

static var D: float = meta.duration
const RX := 31.0
const RY := 7.0
const PY := -3.0
const IN := 0.78
const HIGH := -84.0

static var cache := {}


static func ghosts(o: Dictionary, C: Array) -> Lib.Ghosts:
	var key := "%s:%s" % [o.seed, o.palette]
	if cache.has(key):
		return cache[key]
	var rn := Px.Rng.new(o.seed)
	var g := Lib.Ghosts.new(D, {"box": [-46.0, -90.0, 46.0, 10.0]})
	# motes and sparkles drifting up through the column
	for i in 40:
		var a := rn.range(0.0, TAU)
		var r := sqrt(rn.next()) * RX * IN * 0.9
		var star := i % 3 == 0
		g.add(rn.range(0.0, D), P.STAR if star else P.MOTE, cos(a) * r, PY + sin(a) * r * (RY / RX), rn.range(-4.0, 4.0), -rn.range(30.0, 75.0), rn.range(0.7, 1.3), rn.pick([WHITE, C[6], C[5]]), rn.range(1.8, 3.4) if star else rn.range(0.6, 1.2))
	cache[key] = g
	return g


# the pad: a steel rim with a lit far edge, a recessed disc of light whose rings ripple outward, a hot middle
static func pad(p: Px.Painter, t: float, C: Array, H: Array) -> void:
	var ph := t / D
	p.shade(-RX - 1.0, PY - RY - 1.0, RX + 1.0, 2.0, func(x: float, y: float, out):
		var u := x / RX
		var v := (y - PY) / RY
		var d := sqrt(u * u + v * v)
		# the drum's side, below the top face
		if d > 1.0:
			if absf(x) <= RX and y > PY and y <= 1.0 and sqrt(u * u + pow((y - 3.0 - PY) / RY, 2.0)) <= 1.0:
				out.c = H[0] if (y == 1.0 or absf(x) > RX - 1.0) else (H[3] if x < -RX * 0.4 else (H[1] if x > RX * 0.4 else H[2]))
			return
		if d > 0.97:
			out.c = H[0]
			return
		if d > IN:
			# the rim: lit along its far edge, shadowed on the near one, a seam round it
			out.c = H[1] if absf(d - (IN + 0.1)) < 0.03 else (C[3] if d < IN + 0.03 else (H[5] if v < -0.3 else (H[4] if v < 0.2 else H[3])))
			return
		# the light well: rings rolling outward, brighter toward the middle
		var r := d / IN
		var ring := fmod(fmod(r * 3.0 - ph * 3.0, 1.0) + 1.0, 1.0) < 0.16
		var heat := pow(1.0 - r, 1.5)
		out.c = C[3] if r > 0.94 else ((WHITE if heat > 0.3 else C[6]) if ring else (C[6] if heat > 0.55 else (C[5] if heat > 0.25 else (C[3] if r > 0.8 else C[4])))))
	# emitters round the rim, chasing
	for i in 10:
		var a := (i / 10.0) * TAU + 0.15
		var x := cos(a) * RX * 0.885
		var y := PY + sin(a) * RY * 0.885
		var k := 0.5 + 0.5 * cos(TAU * (2.0 * ph - i / 10.0))
		p.px(x, y, WHITE if k > 0.7 else (C[5] if k > 0.4 else C[2]))
		if k > 0.5:
			p.glow(x, y, 4.0, C[4], 0.35 * k)


# a ring of light lifting off the pad: crisp lines stepping down the ramp as it climbs, a glint running round it;
# its far half or its near half
static func lift(p: Px.Painter, t: float, C: Array, near: bool) -> void:
	for i in 4:
		var k := Lib.since(t, (i / 4.0) * D, D) / 1.25
		if k >= 1.0:
			continue
		var y := Px.lerp(PY, HIGH + 12.0, pow(k, 0.85))
		var rx := RX * IN * (1.0 + 0.08 * k)
		var ry := rx * (RY / RX)
		var c: int = WHITE if k < 0.12 else (C[6] if k < 0.4 else (C[5] if k < 0.65 else (C[4] if k < 0.85 else C[3])))
		var glint := fmod(i * 0.37 + k * 1.5, 1.0) * TAU
		var n := ceili(rx * 7.0)
		for j in n:
			var g := (j / float(n)) * TAU
			var sg := sin(g)
			if (sg >= 0.0) != near:
				continue
			var x := cos(g) * rx
			var yy := y + sg * ry
			var hot := absf(fmod(g - glint + PI * 3.0, TAU) - PI) < 0.25
			if k > 0.85 and (j & 1):
				continue
			p.px(x, yy, WHITE if (hot and k < 0.8) else (c if near else (C[5] if k < 0.4 else C[3])))
			if k < 0.3:
				p.px(x, yy + 1.0, C[5] if near else C[3])
		if near:
			p.glow(0.0, y + ry * 0.5, rx + 8.0, C[4], 0.22 * (1.0 - k))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var H := Px.fit(o.metal, 6)
	pad(p, t, C, H)
	# the column: a soft tube of light standing on the well, fading as it rises, light drawn up it
	var W := RX * IN
	var y := HIGH
	while y < PY:
		var v := (y - PY) / (HIGH - PY)
		var fade := pow(1.0 - v, 1.6)
		var x := floorf(-W)
		while x <= ceilf(W):
			var q := absf(x + 0.5) / W
			if q > 1.0:
				x += 1.0
				continue
			p.blend(x + 0.5, y + 0.5, C[6] if q > 0.9 else C[5], fade * (0.07 + 0.26 * pow(q, 4.0) + 0.12 * pow(1.0 - v, 4.0)))
			x += 1.0
		y += 1.0
	Px.cycle(t, D, 30, o.seed + 3.0, func(r: Px.Rng): return r.range(0.6, 1.1), func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var x := r.range(-0.9, 0.9) * W
		var yy := Px.lerp(PY - 2.0, HIGH + 10.0, k)
		var L := 3.0 + 7.0 * k
		p.line(x, yy, x, yy + L, func(u: float): return C[6] if u < 0.3 else C[4], (1.0 - k) * 1.2))
	lift(p, t, C, false)
	y = PY - 6.0
	while y > HIGH + 20.0:
		p.glow(0.0, y, W + 8.0, C[4], 0.16 * (1.0 - (y - PY) / (HIGH - PY)))
		y -= 12.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	lift(p, t, C, true)
	ghosts(o, C).at(t).draw(p)
	# the light: a pool on the floor, a hot heart to the well, pulsing
	var k := 0.85 + 0.15 * sin(TAU * 2.0 * ph)
	for x: float in [-RX * 0.6, 0.0, RX * 0.6]:
		p.glow(x, PY, 20.0, C[4], 0.25 * k)
	p.glow(0.0, PY, 10.0, WHITE, 0.3 * k)
