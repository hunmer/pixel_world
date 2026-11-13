# The leaves' tumble (turning as they go, flipping over through edge-on, palettes of autumn and green) is adapted
# from Sprite Fusion's open-source falling leaves (https://www.spritefusion.com/pixel-art-vfx/falling-leaves),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/nature/leaf-storm.js@1921a4a3e6c544d875655b2d1b84281e9c93e370
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Leaf storm",
	"desc": "Leaves tumble up a rising spiral round the character, passing behind and in front, turning and flipping, wrapped in bright bands of wind; litter swirls at their feet.",
	"tags": ["nature", "wind", "leaves", "buff", "aura", "actor", "loop"],
	"size": [112, 104],
	"origin": [56, 92],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#1a2420", "#2e4038", "#4a6656", "#7a9a84", "#b4d0b8", "#eef8e8"],
		"leaves": ["#123818", "#2f7a2a", "#6cb83a", "#c8f070", "#4a2a08", "#a8701c", "#e8b42e", "#fff09a", "#3a1010", "#9a2e1c", "#e0642a", "#ffb070"],
		"seed": 5,
	},
}

static var UP := {"turn": 1.1, "crouch": 0, "fx": -13, "fy": -37, "bx": 13, "by": -37, "ffx": -3, "fbx": 4}
static var act := {
	"poses": [
		[0, UP],
		[0.6, Px.merge(UP, {"lean": 2, "fy": -40, "by": -33})],
		[1.2, Px.merge(UP, {"crouch": -1})],
		[1.8, Px.merge(UP, {"lean": -2, "fy": -33, "by": -40})],
		[2.4, UP],
	],
}

const SY := 0.3
const TOP := 64.0


static func ringR(y: float) -> float:
	return 15.0 + 9.0 * Px.clamp(-y / TOP)


# leaves riding the spiral: up from the floor, round two turns or so, flung out off the top
static func leaves(p: Px.Painter, L: Array, t: float, seed: float, back: bool) -> void:
	Px.cycle(t, meta.duration, 28, seed, func(g): return g.range(1.5, 2.3), func(age: float, life: float, R: Px.Rng):
		var k := age / life
		var turns := R.range(1.4, 2.2)
		var th := R.range(0.0, TAU) + turns * TAU * k
		var sn := sin(th)
		if (sn > 0.0) == back:
			return
		var y := -Px.lerp(1.0, TOP, pow(k, 0.9)) - R.range(0.0, 6.0)
		var fling := Px.smooth(0.75, 1.0, k)
		var rr := ringR(y) * R.range(0.85, 1.15) + fling * 22.0
		var x := cos(th) * rr
		var yy := y + sn * rr * SY
		var a := minf(1.0, k * 7.0) * (1.0 - Px.smooth(0.85, 1.0, k))
		var spin := R.range(-9.0, 9.0) * age + th
		var fl := age * R.range(5.0, 11.0)
		var o := R.int_(0, 2) * 4
		var pal := [L[o], L[o], L[o + 1], L[o + 2]] if back else [L[o], L[o + 1], L[o + 2], L[o + 3]]
		Lib.drawLeaf(p, x, yy, R.range(6.5, 9.0), R.range(2.4, 3.3), spin, fl, pal, a)
		# a glint as it turns face on to the light
		if not back and absf(cos(fl)) > 0.97:
			p.px(x, yy, WHITE)
			p.glow(x, yy, 5.0, L[o + 3], 0.35 * a))


# wind bands: 1 px streaks on tilted rings round the character, bright at the head, fading behind, the far
# halves dimmer and behind it
static func wind(p: Px.Painter, C: Array, t: float, seed: float, back: bool) -> void:
	for j in 16:
		var R := Px.rng(seed, j)
		var y0 := -R.range(4.0, TOP - 4.0)
		var r := ringR(y0) * R.range(1.0, 1.25)
		var K := R.int_(2, 3)
		var span := R.range(1.1, 2.4)
		var head: float = R.range(0.0, TAU) + (TAU * K * t) / meta.duration
		var rise := R.range(-0.18, 0.18)
		var s := 0.0
		while s <= span:
			var th := head - s
			var sn := sin(th)
			if (sn > 0.0) == back:
				s += 0.45 / r
				continue
			var k := s / span
			var x := cos(th) * r
			var y := y0 + sn * r * SY + (th - head) * rise * 4.0
			var c: int = (C[3] if k < 0.3 else C[2]) if back else (WHITE if (k < 0.06 and R.next() < 2.0) else (C[5] if k < 0.15 else (C[4] if k < 0.4 else C[3])))
			if k < 0.45:
				p.dot(x, y, c)
			else:
				p.blend(x, y, c, 1.6 * (1.0 - k))
			s += 0.45 / r
		if not back and sin(head) > 0.0:
			p.glow(cos(head) * r, y0 + sin(head) * r * SY, 5.0, C[4], 0.25)


# at the feet: litter and dust swept round on the floor
static func swirl(p: Px.Painter, C: Array, L: Array, t: float, seed: float, back: bool) -> void:
	Px.cycle(t, meta.duration, 14, seed, func(g): return g.range(0.6, 1.1), func(age: float, life: float, R: Px.Rng):
		var k := age / life
		var th := R.range(0.0, TAU) + R.range(6.0, 9.0) * age
		var sn := sin(th)
		if (sn > 0.0) == back:
			return
		var rr := R.range(10.0, 22.0) + k * 8.0
		var x := cos(th) * rr
		var y := -1.0 - k * R.range(2.0, 8.0) + sn * rr * 0.25
		var s := R.range(2.0, 3.5) * (0.6 + k)
		p.disc(x, y, s, C[2] if back else C[3], (1.0 - k) * minf(1.0, k * 6.0) * 0.3))
	for j in 6:
		var R := Px.rng(seed + 9.0, j)
		var rr := R.range(12.0, 24.0)
		var th0: float = R.range(0.0, TAU) + (TAU * 3.0 * t) / meta.duration
		var span := R.range(0.5, 1.0)
		var s := 0.0
		while s < span:
			var th := th0 - s
			if (sin(th) > 0.0) == back:
				s += 0.6 / rr
				continue
			p.dot(cos(th) * rr, 0.5 + rr * 0.2 * sin(th), C[3] if s < span * 0.4 else C[2], 1.0 - s / span)
			s += 0.6 / rr


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 6)
	var L := Px.fit(o.leaves, 12)
	p.glow(0.0, -30.0, 46.0, C[4], 0.12)
	p.glow(0.0, -2.0, 26.0, L[2], 0.12)
	swirl(p, C, L, t, o.seed * 3.0 + 1.0, true)
	wind(p, C, t, o.seed * 5.0 + 2.0, true)
	leaves(p, L, t, o.seed * 7.0 + 3.0, true)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 6)
	var L := Px.fit(o.leaves, 12)
	swirl(p, C, L, t, o.seed * 3.0 + 1.0, false)
	wind(p, C, t, o.seed * 5.0 + 2.0, false)
	leaves(p, L, t, o.seed * 7.0 + 3.0, false)
