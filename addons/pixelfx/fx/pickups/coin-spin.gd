# The hover, floor shadow and glints follow Sprite Fusion's open-source pickup
# (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/coin-spin.js@81cb46352223a77eb73e1de2f92694bacb1e8021
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Coin spin",
	"desc": "A thick gold coin turning on its edge: an embossed star face, a reeded rim showing as it goes edge-on, a flash sweeping the face, bobbing over its shadow.",
	"tags": ["pickup", "coin", "gold", "money", "loop"],
	"size": [56, 56],
	"origin": [28, 48],
	"duration": 1.6,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#1e1206", "#4a2c08", "#86520c", "#c48412", "#f0b424", "#ffe066", "#fff6c4", "#ffffff"], "seed": 3},
}

static var L := Lib.Layer.new(32, 32)
const R := 7.0
const TH := 3.0
const HOVER := 17.0


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var T: float = meta.duration
	var ph := t / T
	var th := ph * TAU
	var y := -HOVER - 2.0 * sin(ph * TAU)
	# the shadow narrows as the coin turns edge-on and thins as it rises
	Lib.blobShadow(p, 0.0, 2.5 + 4.5 * absf(cos(th)) + 1.5 * absf(sin(th)), 0.85 - (-y - HOVER + 2.0) * 0.06)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var T: float = meta.duration
	var ph := t / T
	var th := ph * TAU
	var y := -HOVER - 2.0 * sin(ph * TAU)
	# warm light round it, swelling when the face catches the light
	var facing := absf(cos(th))
	p.glow(0.0, y, 20.0, C[4], 0.3 + 0.12 * facing)
	var flash := Lib.coin3d(L, p, 0.0, y, R, TH, th, C)
	p.glow(-1.0, y - 1.0, 12.0, C[6], 0.35 * flash)
	# a star glint where the flash leaves the rim
	if flash > 0.3:
		Lib.glint(p, -4.0, y - 4.0, 1.0 + 3.2 * flash, C[6], 0.5 * flash)
	# little twinkles round it, one after another
	for i in 5:
		var life := 0.35
		var age := fmod(fmod(t - (i / 5.0) * T - Px.rand(i, o.seed, 3) * 0.08, T) + T, T)
		if age > life:
			continue
		var a := Px.rand(i, o.seed, 1) * TAU + i * 2.1
		var d := 10.0 + Px.rand(i, o.seed, 2) * 5.0
		var k := sin((age / life) * PI)
		Lib.glint(p, cos(a) * d, y + sin(a) * d * 0.85 - age * 8.0, Px.round(2.0 * k), C[6] if i % 2 else WHITE, 0.35 * k)
