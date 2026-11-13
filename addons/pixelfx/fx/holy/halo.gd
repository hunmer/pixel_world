# port-of: src/fx/holy/halo.js@cd89a1b1703a0a88a94bd76d18577d657bff8c50
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Halo",
	"desc": "A ring of gold light floats over the head with a glint running round it; fine dust sifts down from it and the head catches its light.",
	"tags": ["holy", "halo", "saint", "buff", "glow", "character", "loop"],
	"size": [56, 80],
	"origin": [28, 70],
	"duration": 2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Lib.GOLD, "seed": 5},
}

static var PRAY := {"turn": 1.1, "fx": -1, "fy": -26, "bx": 2, "by": -26, "armsFront": true, "hy": 1, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"poses": [[0, PRAY], [0.5, Px.merge(PRAY, {"crouch": 1})], [1, Px.merge(PRAY, {"crouch": 1, "hy": 2})], [1.5, Px.merge(PRAY, {"crouch": 1})], [2, PRAY]],
}

const HY := -46.0
const RX := 9.5
const RY := 2.6

# how far apart two angles are (0..π)
static func apart(a: float, b: float) -> float:
	return absf(fmod(fmod(a - b + PI, TAU) + TAU, TAU) - PI)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var T: float = meta.duration
	var ph := (t / T) * TAU
	var A: Variant = o.get("actor")
	var y0 := HY + (-1.0 if sin(ph) > 0.55 else 0.0)
	var gl := PI / 2.0 + ph
	# the hair under it catches the light
	if A:
		# a warm rim on the top edge of each column of the head, and light falling off below it
		var m: Dictionary = A.mask
		var mw: int = m.w
		var mh: int = m.h
		var PX: PackedInt32Array = A.pixels
		for i in mw:
			for j in mini(mh, 9):
				var c := PX[j * mw + i]
				# skip empty space and the dark outline, light the first pixel of hair under it
				if not c or Px.luma(c) < 0.15:
					continue
				var x: float = A.x + i
				var y: float = A.y + j
				p.px(x, y, Px.mix(c, C[6], 0.45))
				var i2 := (j + 1) * mw + i
				var c2 := PX[i2] if i2 < PX.size() else 0
				if c2 and Px.luma(c2) >= 0.15:
					p.px(x, y + 1.0, Px.mix(c2, C[5], 0.18))
				for d in 5:
					p.light(x, y + d, C[4], 0.3 * (1.0 - d / 5.0))
				break
	# the ring: a thick bright near side, a thin far side, a slow shimmer running round, the glint
	var n := 92.0
	for j in int(n):
		var g := (j / n) * TAU
		var x := cos(g) * RX
		var y := y0 + sin(g) * RY
		var near := sin(g) >= 0.0
		var shimmer := sin(g * 3.0 - ph * 2.0) > 0.7
		var hot := apart(g, gl) < 0.3
		if near:
			p.px(x, y, WHITE if hot else (WHITE if shimmer else C[6]))
			p.px(x, y + 1.0, C[6] if hot else C[4])
		else:
			p.dot(x, y, WHITE if hot else (C[6] if shimmer else C[5]), 0.9)
	p.glow(0.0, y0, 20.0, C[4], 0.4)
	p.glow(0.0, y0 + 1.0, 9.0, WHITE, 0.16)
	var gx := cos(gl) * RX
	var gy := y0 + sin(gl) * RY
	if sin(gl) > -0.2:
		Px.sparkle(p, gx, gy + 0.5, 1.5 + 2.5 * maxf(0.0, sin(gl)), WHITE, C[6], 0.45)
	else:
		p.glow(gx, gy, 5.0, C[6], 0.3)
	# light falls from it onto the head
	p.glowLine(0.0, y0 + 2.0, 0.0, y0 + 9.0, 9.0, C[4], 0.16)
	# little stars wink on and off about the ring
	Px.cycle(t, T, 6, o.seed + 3, func(g): return g.range(0.3, 0.5), func(age, life, R):
		var g: float = R.range(0.0, TAU)
		var d: float = R.range(1.1, 1.5)
		var k := sin((age / life) * PI)
		Px.sparkle(p, cos(g) * RX * d, y0 + sin(g) * RY * d - R.range(1.0, 4.0), 1.0 + 2.0 * k, WHITE, C[6], 0.4 * k))
	# dust sifting down off the ring
	Px.cycle(t, T, 16, o.seed, func(g): return g.range(0.8, 1.5), func(age, life, R):
		var g: float = R.range(0.0, TAU)
		var u: float = age / life
		var x: float = cos(g) * RX * R.range(0.8, 1.0) + sin(u * 5.0 + g) * 1.2
		var y: float = y0 + sin(g) * RY + 1.0 + u * R.range(7.0, 14.0)
		var tw := 0.6 + 0.4 * sin(age * 18.0 + g * 7.0)
		var k := sin(u * PI) * tw
		p.dot(x, y, WHITE if tw > 0.85 else C[6], minf(1.0, k * 1.5))
		p.light(x, y, C[5], 0.5 * k))
