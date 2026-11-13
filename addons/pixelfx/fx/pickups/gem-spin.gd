# The hover, floor shadow and twinkle glints follow Sprite Fusion's open-source pickup and sparkle
# (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/gem-spin.js@b273032bb36b755d44fa87359dec2a9837740dcf
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Gem spin",
	"desc": "A brilliant-cut ruby turning on its axis: real facets catch the light in turn, flashes roll over the crown, refracted light slides across the floor, sparkles wink round it.",
	"tags": ["pickup", "gem", "jewel", "treasure", "ruby", "loop"],
	"size": [64, 64],
	"origin": [32, 56],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#16040e", "#3e0a1e", "#760e2e", "#b8163c", "#ec3250", "#ff7482", "#ffc4c8", "#ffffff"], "seed": 6},
}

static var GEM := Lib.brilliant({"r": 7.5, "crown": 3.2, "table": 0.5, "pavilion": 9.5, "girdle": 0.9})
static var L := Lib.Layer.new(32, 32)
const HOVER := 19.0


# where the gem is: hovering, one slow bob a loop, turning four facets a loop
static func pose(t: float, T: float) -> Dictionary:
	return {"y": -HOVER - 1.8 * sin((t / T) * TAU), "spin": (t / T) * PI}


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var T: float = meta.duration
	var ps := pose(t, T)
	var y: float = ps.y
	var spin: float = ps.spin
	var lift := (-y - HOVER + 2.0) / 4.0
	Lib.blobShadow(p, 0.0, 8.0 - lift * 1.5, 0.75 - lift * 0.2)
	# light refracted through the stone, sliding over the floor as it turns
	for k in 3:
		var a := spin * 4.0 + (k * TAU) / 3.0
		var x := sin(a) * 9.0
		var k2 := 0.5 + 0.5 * cos(a)
		if k2 < 0.15:
			continue
		p.dot(x, 0.0, C[6] if k2 > 0.7 else C[5], k2 * 1.2)
		p.dot(x + 1.0, 0.0, C[4], k2 * 0.8)
		p.dot(x - 1.0, 0.0, C[4], k2 * 0.6)
		p.glow(x + 0.5, 0.0, 6.0, C[5], 0.3 * k2)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var T: float = meta.duration
	var ph := t / T
	var ps := pose(t, T)
	var y: float = ps.y
	var spin: float = ps.spin
	# its light: a wide soft halo and a hot heart
	p.glowRing(0.0, y - 1.0, 5.0, 15.0, C[4], 0.34)
	p.glow(0.0, y, 26.0, C[3], 0.14)
	var hi := Lib.drawGem(L, p, GEM, 0.0, y, spin, C, {"tilt": 0.22})
	# a star flares where a facet swings square to the light, twice a loop
	var f := fmod((spin * 4.0) / TAU, 1.0)
	var fk := maxf(0.0, 1.0 - absf(f - 0.5) / 0.08)
	if fk > 0.0:
		Lib.glint(p, -3.0, y - 3.0, 3.4 * Px.Ease.outQuad(fk), C[6], 0.45 * fk)
	# sparkles wink on and off round it, one after another
	for i in 8:
		var life := 0.4
		var age := fmod(fmod(t - (i / 8.0) * T - Px.rand(i, o.seed, 3) * 0.1, T) + T, T)
		if age > life:
			continue
		var a := Px.rand(i, o.seed, 1) * TAU + i * 2.4
		var d := 10.0 + Px.rand(i, o.seed, 2) * 7.0
		var k := sin((age / life) * PI)
		Lib.glint(p, cos(a) * d, y + sin(a) * d * 0.8 - age * 6.0, Px.round(2.4 * k * (0.6 + 0.4 * Px.rand(i, 9))), C[6] if i % 3 else WHITE, 0.4 * k)
