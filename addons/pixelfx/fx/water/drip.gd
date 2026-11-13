# The bead swelling at the tip and the falling drop's tail follow Sprite Fusion's open-source blood
# (https://www.spritefusion.com/pixel-art-vfx/blood), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/drip.js@ac2ede2ee25d1751b63f9f1cc6d4a75eb686e812
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Drip",
	"desc": "A bead swells under a wet stone tip and catches the light, pinches off, falls stretched by its speed and plinks into a puddle with a crown, a ring and a tiny rebound.",
	"tags": ["water", "drip", "drop", "puddle", "cave", "ambient", "loop"],
	"size": [72, 88],
	"origin": [36, 78],
	"duration": 1.6,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.WATER, "height": 62, "source": true, "seed": 1},
}

static var D: float = meta.duration
const SY := 0.28
const G := 760.0
const LET := 0.78
const PRX := 20.0


# the stone the water gathers on: a lump of ceiling rock tapering to a dripstone point, lit on its left, a dark
# rim, a wet streak running down to the point
static func dripstone(p: Px.Painter, H: float) -> void:
	var ST := Lib.rock()
	var top := -H - 14.0
	p.shade(-24.0, top, 22.0, -H + 0.5, func(x: float, y: float, out):
		# a ragged underside of ceiling rock that hangs down into a short dripstone, its point at x = 0
		var under := top + 7.0 + sin(x * 0.45) * 1.2 + sin(x * 1.3 + 1.0) * 0.6 - absf(x + 4.0) * 0.12
		var cone := -H - absf(x) * 1.25
		var bottom := maxf(under, minf(cone, -H))
		var span := 24.0 if x < 0.0 else 22.0
		if y > bottom or absf(x) > span - maxf(0.0, top + 3.0 - y) * 4.0:
			return
		var rim := y > bottom - 1.0 or absf(x) > span - 1.0
		var lx := (x + 24.0) / 46.0
		var v := (y - top) / 14.0
		out.c = ST[0] if rim else (ST[1] if v < 0.25 else ((ST[4] if x < 0.0 else ST[2]) if (y > under and absf(x) < 6.0) else (ST[4] if lx < 0.3 else (ST[3] if lx < 0.62 else ST[2]))))
		if not rim and absf(x - 9.0 - (y - top) * 0.4) < 0.5 and v > 0.3 and v < 0.7:
			out.c = ST[0])
	# a wet streak down to the point, catching the light
	var y := -H - 7.0
	while y < -H:
		p.px(-1.0, y, C_WET[1] if y > -H - 3.0 else C_WET[0])
		y += 1.0
	p.px(-1.0, -H - 2.0, WHITE)


static var C_WET: Array = ["#5d6a86", "#9fb6d6"].map(func(h: String): return Px.i32(h.substr(1, 2).hex_to_int() | (h.substr(3, 2).hex_to_int() << 8) | (h.substr(5, 2).hex_to_int() << 16) | 0xff000000))


# the puddle: dark see-through water with a lit far edge, the drop's light in it
static func puddle(p: Px.Painter, C: Array) -> void:
	var ry := PRX * SY
	var Y := floorf(-ry)
	while Y < ry:
		var X := -PRX
		while X < PRX:
			var x := X + 0.5
			var y := Y + 0.5
			var d := pow(x / PRX, 2.0) + pow(y / ry, 2.0)
			if d > 1.0:
				X += 1.0
				continue
			p.blend(x, y, C[1], 0.72 * minf(1.0, (1.0 - d) * 5.0))
			X += 1.0
		Y += 1.0
	# the far edge catches the light in one fine line
	var X := -PRX + 3.0
	while X < PRX - 3.0:
		var x := X + 0.5
		var y := -sqrt(1.0 - pow(x / PRX, 2.0)) * ry
		p.dot(x, y + 0.5, C[4] if absf(x) < PRX * 0.5 else C[3], 0.95)
		X += 1.0


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	puddle(p, C)
	var u := t - landAt(o.height)
	if u >= 0.0:
		Lib.ring(p, 0.0, 0.0, 2.0 + 17.0 * Px.Ease.outCubic(u / 0.75), SY, 1.1 * (1.0 - u / 0.75), C, {"n": 2.0, "gap": 2.5, "half": -1.0, "seed": 1.0, "wob": 0.4})
	var v := t - landAt(o.height) - REBOUND - BACK
	if v >= 0.0:
		Lib.ring(p, 0.0, 0.0, 1.5 + 9.0 * Px.Ease.outCubic(v / 0.5), SY, 0.9 * (1.0 - v / 0.5), C, {"n": 1.0, "half": -1.0, "seed": 2.0})


static func landAt(H: float) -> float:
	return LET + sqrt((2.0 * H) / G)


const REBOUND := 0.06
const BACK := 0.2


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var H: float = o.height
	var land := landAt(H)
	if o.source:
		dripstone(p, H)
	# the bead swells at the tip, wobbling, and catches the light; its neck stretches before it lets go
	if t < LET:
		var k := t / LET
		var r := 0.7 + 2.3 * Px.Ease.inQuad(k)
		var wob := 0.15 * sin(t * 26.0) * k
		var neck := Px.smooth(0.82, 1.0, k) * 2.5
		var cy := -H + r + neck
		if neck > 0.2:
			p.line(0.0, -H, 0.0, cy - r, C[5])
		p.ellipse(0.0, cy, r * (1.0 - wob), r * (1.0 + wob) + 0.3 * k, func(d: float, a: float): return ((C[5] if (cos(a) < 0.0 and sin(a) < 0.3) else C[3]) if d > 0.72 else (C[6] if (d < 0.35 and cos(a) > 0.0) else C[4])))
		if r > 1.0:
			p.px(-r * 0.4, cy - r * 0.45, WHITE)
		p.glow(0.0, cy, 4.0 + r * 2.0, C[5], 0.14 + 0.14 * k)
	else:
		# a little of it springs back up the tip after it lets go
		var s := (t - LET) / 0.15
		if s < 1.0:
			p.ellipse(0.0, -H + 0.8, 1.2 * (1.0 - s * 0.6), 1.0 + sin(s * PI) * 0.8, C[4])
	# the fall, stretched by its speed
	var f := t - LET
	if f > 0.0 and t < land:
		var y := -H + 3.0 + 0.5 * G * f * f
		var vy := G * f
		Lib.bead(p, 0.0, y, 0.0, vy, 3.0, C)
		p.glow(0.0, y, 6.0, C[5], 0.2)
	# the plink: a white fleck, a little crown thrown up, the near half of the ring, light
	var u := t - land
	if u >= 0.0:
		Lib.ring(p, 0.0, 0.0, 2.0 + 17.0 * Px.Ease.outCubic(u / 0.75), SY, 1.1 * (1.0 - u / 0.75), C, {"n": 2.0, "gap": 2.5, "half": 1.0, "hot": u < 0.08, "seed": 1.0, "wob": 0.4, "glint": 1.0 - u * 2.0 if u < 0.5 else 0.0})
		if u < 0.06:
			p.px(0.0, 0.0, WHITE)
			p.px(-1.0, 0.0, C[6])
			p.px(1.0, 0.0, C[6])
			p.glow(0.0, -1.0, 10.0, C[5], 0.5 * (1.0 - u / 0.06))
		# the crown: three flecks thrown out and back
		for vv: Array in [[-26.0, 70.0], [24.0, 64.0], [-6.0, 90.0]]:
			var vx: float = vv[0]
			var vh: float = vv[1]
			var h := vh * u - 0.5 * G * u * u
			if h > 0.0 and u < 0.3:
				p.px(vx * u, -h, WHITE if u < 0.1 else C[6])
		# the rebound: a bead pops up out of the middle and drops back
		var r := u - REBOUND
		var h := 52.0 * r - 0.5 * G * 0.5 * r * r * 2.0
		if r > 0.0 and h > 0.0:
			p.line(0.0, -1.0, 0.0, -h + 1.0, C[5])
			p.circle(0.0, -h, 1.1, C[6])
			p.px(0.0, -h - 1.0, WHITE)
		var v := u - REBOUND - BACK
		if v >= 0.0:
			Lib.ring(p, 0.0, 0.0, 1.5 + 9.0 * Px.Ease.outCubic(v / 0.5), SY, 0.9 * (1.0 - v / 0.5), C, {"n": 1.0, "half": 1.0, "seed": 2.0, "hot": v < 0.06})
		p.glow(0.0, 0.0, 18.0, C[4], 0.22 * (1.0 - Px.clamp(u / 0.6)))
	# the tip and the drop shimmer in the puddle
	var sh := 0.0 if sin(t * 20.0) > 0.0 else 1.0
	p.px(-1.0 + sh, 2.0, C[4])
	if f > 0.0 and t < land:
		var ry := 2.0 + 0.5 * G * f * f * 0.04
		p.px(sh, minf(4.0, ry), C[5])
	# the wet light under the tip and in the puddle
	p.glow(0.0, -H + 2.0, 8.0, C[5], 0.16)
	p.glow(0.0, 0.0, 26.0, C[3], 0.14)
