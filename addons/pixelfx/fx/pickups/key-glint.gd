# The hover, floor shadow and star glints follow Sprite Fusion's open-source pickup and sparkle
# (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/key-glint.js@54c0c595030bb998d8d29298b6eb3ebd12a7ec83
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Key glint",
	"desc": "An ornate silver key hovering and rocking; a glint runs from its bow down the shaft to the teeth and bursts off the tip as falling sparks.",
	"tags": ["pickup", "key", "unlock", "item", "loop"],
	"size": [72, 60],
	"origin": [36, 54],
	"duration": 2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#0e1018", "#222838", "#3c4660", "#5e6d8e", "#8c9cbc", "#bccae2", "#e6eeff", "#ffffff"], "seed": 7},
}

static var L := Lib.Layer.new(48, 40)
const HOVER := 19.0
const MID := 8.0
const TIP := 17.5
const G0 := 0.18
const G1 := 0.5 # the glint's run, as loop phase


# where the key hangs: bobbing and rocking, bow up to the left, teeth down to the right
static func pose(ph: float) -> Dictionary:
	return {"y": -HOVER - 1.6 * sin(ph * TAU), "a": 0.42 + 0.11 * sin(ph * TAU + 0.9)}


static func toWorld(u: float, v: float, cx: float, cy: float, a: float) -> Array:
	return [cx + (u - MID) * cos(a) - v * sin(a), cy + (u - MID) * sin(a) + v * cos(a)]


# the key in its own frame: u along the shaft (bow at 0, tip at 17.5), v across it
static func part(u: float, v: float) -> int:
	var rb := Px.hypot(u, v)
	if rb <= 4.6 and rb >= 2.1:
		return 1 # the bow's ring
	if u >= 4.3 and u <= 6.0 and absf(v) <= 1.9:
		return 2 # the collar
	if u >= 6.0 and u <= TIP and absf(v) <= 1.0:
		return 3 # the shaft
	if u >= 12.6 and u <= TIP - 0.3 and v > 1.0 and v <= 4.6 and not (u > 14.3 and u < 15.4 and v > 2.7):
		return 4 # the bit
	return 0


static func key(p: Px.Painter, C: Array, cx: float, cy: float, a: float, gu: float) -> void:
	var ca := cos(a)
	var sa := sin(a)
	L.begin(floorf(cx) - 24.0, floorf(cy) - 20.0)
	L.fill(floorf(cx) - 24.0, floorf(cy) - 20.0, floorf(cx) + 23.0, floorf(cy) + 19.0, func(px: float, py: float) -> Variant:
		var dx := px - cx
		var dy := py - cy
		var u := dx * ca + dy * sa + MID
		var v := -dx * sa + dy * ca
		var k := part(u, v)
		if not k:
			return 0
		# light from the top left of the screen: work out which way this bit of metal faces
		var ny: float
		if k == 1:
			var rb := Px.hypot(u, v)
			var out := 1.0 if rb > 3.4 else -1.0
			var wx := (u / rb) * out
			var wy := (v / rb) * out
			ny = -(((wx * ca - wy * sa) * -0.6) + (wx * sa + wy * ca) * -0.8)
		else:
			ny = 0.8 if v < -0.35 else (-0.6 if (v > 0.35 and k != 4) else ((-0.5 if v > 3.6 else 0.1) if k == 4 else 0.2))
		var c := 6 if ny > 0.55 else (4 if ny > 0.15 else (3 if ny > -0.3 else 2))
		if k == 2:
			c = mini(7, c + 1)
		# the glint: a slanted band of white running down the key
		var g := absf(u + v * 0.45 - gu)
		if g < 0.8:
			return WHITE
		if g < 2.0:
			c = mini(7, c + 2)
		return C[c])
	L.outline(C[0]).draw(p)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var D: float = meta.duration
	var y: float = pose(t / D).y
	Lib.blobShadow(p, 0.0, 10.0, 0.8 - (-y - HOVER + 1.6) * 0.06)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var T: float = meta.duration
	var ph := t / T
	var ps := pose(ph)
	var y: float = ps.y
	var a: float = ps.a
	var q := (ph - G0) / (G1 - G0)
	var gu := -5.0 + (TIP + 7.0) * Px.Ease.inOutSine(q) if (q > 0.0 and q < 1.0) else -100.0
	# cool light round it and all along it
	var bxy := toWorld(0.0, 0.0, 0.0, y, a)
	var exy := toWorld(TIP, 0.0, 0.0, y, a)
	p.glow(0.0, y, 24.0, C[4], 0.3)
	p.glowLine(bxy[0], bxy[1], exy[0], exy[1], 7.0, C[5], 0.16)
	key(p, C, 0.0, y, a, gu)
	# a few idle twinkles round it, one after another
	for i in 4:
		var life := 0.4
		var age := fmod(fmod(t - ((i + 0.6) / 4.0) * T, T) + T, T)
		if age > life:
			continue
		var an := Px.rand(i, o.seed, 8) * TAU
		var d := 9.0 + Px.rand(i, o.seed, 9) * 6.0
		var k := sin((age / life) * PI)
		Lib.glint(p, cos(an) * d, y + sin(an) * d * 0.8 - age * 6.0, Px.round(1.8 * k), C[6] if i % 2 else WHITE, 0.35 * k)
	# light rides with the glint
	if gu > -6.0:
		var gxy := toWorld(Px.clamp(gu, 0.0, TIP), 0.0, 0.0, y, a)
		p.glow(gxy[0], gxy[1], 10.0, C[6], 0.45 * sin(q * PI))
	# as it leaves the tip: a star, and sparks that arc away and fall
	var txy := toWorld(TIP, 0.0, 0.0, y, a)
	var tx: float = txy[0]
	var ty: float = txy[1]
	var at := (ph - G1 + 0.02) * T
	if at > 0.0 and at < 0.3:
		Lib.glint(p, tx, ty, 4.5 * (1.0 - at / 0.3), C[6], 0.6 * (1.0 - at / 0.3))
	for i in 9:
		var life := 0.32 + Px.rand(i, o.seed, 4) * 0.3
		var age := at - Px.rand(i, o.seed, 5) * 0.05
		if age < 0.0 or age > life:
			continue
		var sp := 25.0 + Px.rand(i, o.seed, 1) * 45.0
		var an := a + (Px.rand(i, o.seed, 2) - 0.5) * 2.2
		var xy := Px.fly(tx, ty, cos(an) * sp, sin(an) * sp - 25.0, age, 380.0, 2.5)
		var vxy := Px.flyV(cos(an) * sp, sin(an) * sp - 25.0, age, 380.0, 2.5)
		var x: float = xy[0]
		var yy: float = xy[1]
		var vx: float = vxy[0]
		var vy: float = vxy[1]
		if yy > -0.5:
			continue # it has reached the floor
		var s := Px.hypot(vx, vy)
		if not s:
			s = 1.0
		var L2 := minf(4.0, 1.0 + s * 0.03)
		var k := 1.0 - age / life
		p.line(x - (vx / s) * L2, yy - (vy / s) * L2, x, yy, func(u: float) -> int: return WHITE if u > 0.6 else C[5], k * 1.6)
		p.glow(x, yy, 3.0, C[5], 0.4 * k)
