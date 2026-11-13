# The hover, floor shadow and glints follow Sprite Fusion's open-source pickup
# (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/heart-pickup.js@ef219856394e131ae12eb51dd7dd7a77660f7133
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Heart pickup",
	"desc": "A plump glossy heart hovering over its shadow beats lub-dub: a big squash and stretch, a smaller echo, light and a thin ring pulsing out, tiny hearts drifting off.",
	"tags": ["pickup", "heart", "health", "life", "loop"],
	"size": [56, 60],
	"origin": [28, 52],
	"duration": 1.2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#1a0408", "#4a0a14", "#8a1222", "#d02436", "#ff4a56", "#ff8a8e", "#ffd0cc", "#ffffff"], "seed": 4},
}

static var L := Lib.Layer.new(40, 40)
const HOVER := 18.0
const W := 7.2
static var INK := Px.hex("#12060c")
const MINI := [".a.a.", "abbba", ".aba.", "..a.."]
const LUB := 0.04
const DUB := 0.24 # the two beats, as loop phase


# a beat: a sharp squash that springs back through a stretch
static func beat(ph: float, at: float, s: float) -> float:
	var u := ph - at
	if u < 0.0 or u > 0.3:
		return 0.0
	return s * Px.exp(-u * 16.0) * cos(u * 34.0)


static func pulse(ph: float) -> float:
	return beat(ph, LUB, 1.0) + beat(ph, DUB, 0.55) + beat(ph + 1.0, LUB, 1.0)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var ph := t / D
	var y := -HOVER - 1.2 * sin(ph * TAU)
	Lib.blobShadow(p, 0.0, 8.0 + 1.5 * pulse(ph), 0.8)
	# tiny hearts float off from behind it, wobbling, and fade
	Px.cycle(t, D, 4, o.seed, 0.95, func(age: float, life: float, r: Px.Rng, i: int) -> void:
		var side := 1.0 if i % 2 else -1.0
		var k := age / life
		var x := side * (r.range(2.0, 5.0) + age * r.range(9.0, 15.0)) + sin(age * 7.0 + r.range(0.0, TAU)) * 1.5
		var yy := y - 5.0 - age * r.range(14.0, 19.0)
		var a := minf(1.0, age / 0.12) * (1.0 - k * k)
		p.sprite(MINI, {"a": C[5] if k < 0.5 else C[4], "b": WHITE if k < 0.3 else C[6]}, Px.round(x - 2.5), Px.round(yy - 2.0), {"a": a * 1.3})
		p.glow(x, yy, 5.0, C[4], 0.3 * a))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var ph := t / D
	var y := -HOVER - 1.2 * sin(ph * TAU)
	var b := pulse(ph)
	# squash wide on the beat, then spring back through a stretch
	var sx := 1.0 + 0.16 * b
	var sy := 1.0 - 0.13 * b
	var cy := Px.round(y)
	# light swells on each beat
	p.glow(0.0, cy, 22.0 + 6.0 * maxf(0.0, b), C[4], 0.26 + 0.3 * maxf(0.0, b))
	L.begin(-20.0, cy - 20.0)
	var sdf := func(x: float, yy: float) -> float: return Lib.heartSdf(x, yy, 0.0, cy, W * sx, W * sy)
	var color := func(lt: float, e: float) -> int:
		if lt > 0.92 and e > 1.2:
			return WHITE
		return C[6] if lt > 0.8 else (C[5] if lt > 0.6 else (C[4] if lt > 0.38 else (C[3] if lt > 0.12 else C[2])))
	Lib.pillow(L, -12.0, cy - 11.0, 12.0, cy + 11.0, sdf, color, {"bevel": 3.6})
	L.outline(INK).draw(p)
	# a thin ring of light snaps out on the big beat
	var u := fmod(fmod(ph - LUB, 1.0) + 1.0, 1.0)
	if u < 0.28:
		var k := u / 0.28
		var r := 9.0 + 8.0 * (1.0 - pow(1.0 - k, 3))
		p.ring(0.0, cy, r, 1.0, C[6] if k < 0.2 else C[5], 0.85 * (1.0 - k))
		p.glowRing(0.0, cy, r, 4.0, C[4], 0.25 * (1.0 - k))
	# a glint on its shoulder after each beat
	var g := fmod(fmod(ph - LUB - 0.08, 0.5) + 0.5, 0.5)
	if g < 0.12:
		Lib.glint(p, -3.5, cy - 4.0, 2.6 * sin((g / 0.12) * PI), WHITE, 0.45)
