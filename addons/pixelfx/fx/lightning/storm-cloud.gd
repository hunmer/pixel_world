# The bolt's forked shape, its halo-body-core inking and its flicker follow Sprite Fusion's open-source
# lightning (https://www.spritefusion.com/pixel-art-vfx/lightning), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/storm-cloud.js@ba598245265c83ec0ecaa46d0b3e6ec59e0aaebc
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Storm cloud",
	"desc": "A storm cloud boils overhead, billows lit from inside by flickering discharges, ragged scud under its flat dark base; rain slants down and once a loop a bolt cracks to the floor.",
	"tags": ["lightning", "storm", "weather", "cloud", "rain", "ambient", "loop"],
	"size": [168, 176],
	"origin": [84, 164],
	"duration": 3.0,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOLT, "sparks": Lib.PLASMA, "cloud": ["#09070f", "#120f1e", "#1b182e", "#252640", "#323758", "#464d78", "#646b9c"], "rain": ["#2b3250", "#46527a", "#6d7cab", "#a5b5e0"], "seed": 8},
}

const FPS := 30.0
const N := 90
const P := 3.0
const BASE := -100.0
const TOP := -156.0
const TH := 0.35
static var VIS := sqrt(1.0 - sqrt(TH))
# the billows: [x, y, visible radius, squash]; a tower leaning into a flat anvil sheared off to the right, big
# billows of all sizes below it, smaller shoulders, a flat run along the base
const BILLOWS := [
	[-6, -132, 17], [18, -127, 14], [-28, -122, 12], [38, -118, 10], [0, -142, 12],
	[14, -149, 19, 0.38], [40, -148, 14, 0.34],
	[-48, -113, 10], [55, -110, 9], [-17, -115, 13], [22, -113, 12],
	[-42, -104, 11], [-10, -104, 12], [20, -104, 11], [48, -103, 9], [-63, -104, 7], [66, -103, 6],
]
# discharges inside: [frame, billow, strength]; the bolt to the floor at frame BOLT, out of billow BOLT_B
const FLASHES := [[7, 2, 0.8], [8, 9, 0.55], [29, 1, 0.75], [31, 10, 1.0], [33, 3, 0.5], [70, 0, 0.8], [71, 4, 0.55], [72, 5, 0.35]]
const BOLT := 52
const BOLT_B := 12
const BK := [1.0, 0.7, 0.3, 0.95, 0.5, 0.75, 0.2]
const W0 := -84.0
const H0 := TOP - 6.0
const GW := 168
static var GH := int(BASE + 8.0 - H0)
static var FIELD := _f32(GW * GH)
static var GX := _f32(GW * GH)
static var GY := _f32(GW * GH)
static var LIT := _f32(GW * GH)


static func _f32(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	return a


# where each billow is this frame: drifting, breathing and boiling up on its own clock, all seamless over the loop
static func billows(seed: float, ph: float) -> Array:
	var out := []
	for i in BILLOWS.size():
		var bl: Array = BILLOWS[i]
		var x: float = bl[0]
		var y: float = bl[1]
		var v: float = bl[2]
		var sq: float = bl[3] if bl.size() > 3 else 1.0
		var top := y < -112.0 and sq == 1.0
		var boil := 0.82 + 0.3 * sin(PI * fmod(ph + i * 0.37, 1.0)) ** 2
		out.append({"sq": sq, "x": x + 3.5 * Px.loopNoise(ph, 0.7, seed + i) + (4.0 * Px.loopNoise(ph, 0.5, seed + i + 90) if sq < 1.0 else 0.0), "y": y + 2.0 * Px.loopNoise(ph, 0.7, seed + i + 30) - (4.0 * (boil - 0.97) if top else 0.0), "r": (v * (boil if top else 1.0 + 0.08 * Px.loopNoise(ph, 0.6, seed + i + 60))) / VIS})
	return out


# the cloud as one field: billows summed so they fuse, clipped flat at the base, its edge ragged with drifting
# noise; shaded as one mass (a lit top, a cool middle, a dark belly), discharges lighting whole billows from inside
static func cloud(p: Px.Painter, B: Array, ph: float, seed: float, K: Array, C: Array, flashes: Dictionary) -> void:
	FIELD.fill(0.0)
	GX.fill(0.0)
	GY.fill(0.0)
	LIT.fill(0.0)
	for i in B.size():
		var b: Dictionary = B[i]
		var k: float = flashes.get(i, 0.0)
		var br: float = b.r
		var bsq: float = b.sq
		var bx: float = b.x
		var by: float = b.y
		var r2 := br * br
		var ry := br * bsq
		for y in range(maxi(0, floori(by - ry - H0)), mini(GH, ceili(by + ry - H0))):
			for x in range(maxi(0, floori(bx - br - W0)), mini(GW, ceili(bx + br - W0))):
				var dx := x + W0 + 0.5 - bx
				var dy := (y + H0 + 0.5 - by) / bsq
				var d2 := (dx * dx + dy * dy) / r2
				if d2 >= 1.0:
					continue
				var j := y * GW + x
				var u := 1.0 - d2
				var c := u * u
				FIELD[j] += c
				GX[j] += (-4.0 * u * dx) / r2
				GY[j] += (-4.0 * u * dy) / (r2 * bsq)
				if k:
					LIT[j] += k * (0.25 + 0.75 * c) * (1.0 if d2 < 1.0 else 0.0)
	var ramp := K + [C[3], C[4], C[5], C[6]]
	var n := K.size()
	for y in GH:
		var cy := y + H0 + 0.5
		for x in GW:
			var j := y * GW + x
			if FIELD[j] < TH - 0.06:
				continue
			var cx := x + W0 + 0.5
			var base := BASE + 1.5 * Px.tileNoise(cx * 0.12 + 9.0 * ph, 3.0, 9.0, 0.0, seed + 5.0)
			var F := FIELD[j] * (1.0 - Px.smooth(base - 3.0, base, cy)) + 0.05 * Px.tileNoise(cx * 0.21 + 18.0 * ph, cy * 0.21, 18.0, 0.0, seed)
			if F < TH:
				continue
			# the field's slope rounds each billow's top; height does the rest: lit above, cool in the middle, dark below
			var gl := Px.hypot(GX[j], GY[j])
			if not gl:
				gl = 1.0
			var lam := -(GX[j] * 0.42 + GY[j] * 0.9) / gl
			var edge := minf(1.0, gl * 5.0) * (1.0 if F < TH + 0.08 else 0.55)
			var h := 1.0 - 2.0 * Px.clamp((cy - TOP) / (BASE - TOP))
			var i := 2.7 + 2.2 * h + 1.3 * lam * edge + 0.4 * Px.tileNoise(cx * 0.16 + 12.0 * ph, cy * 0.16, 12.0, 0.0, seed + 9.0)
			if F < TH + 0.05 and lam > 0.3 and h > -0.5:
				i += 1.0
			if cy > base - 6.0:
				i -= 1.0
			i = Px.clamp(Px.round(i), 0.0, n - 1.0)
			# lit from inside: brightest deep in the billow, breaking up through the cloud's own lumps toward its edges
			var L := LIT[j] * (0.7 + 0.6 * Px.tileNoise(cx * 0.2 - 14.0 * ph, cy * 0.2, 14.0, 0.0, seed + 3.0))
			if L > 0.12:
				i = minf(ramp.size() - 1.0, i + Px.round(L * 5.5))
			p.px(cx, cy, ramp[int(i)])


# scud: ragged wisps that form under the base, drift off on the wind and fray away
static func scud(p: Px.Painter, ph: float, seed: float, K: Array) -> void:
	var r := Px.rng(seed, 13)
	for w in 6:
		var x0 := r.range(-60.0, 60.0)
		var y0 := BASE + r.range(3.0, 9.0)
		var rx := r.range(10.0, 20.0)
		var ry := r.range(1.3, 2.2)
		var off := r.next()
		var u := fmod(ph + off, 1.0)
		var a := sin(PI * u) ** 0.8
		var xc := x0 + 16.0 * (u - 0.5)
		var y := floori(y0 - ry - 1.0)
		while y <= y0 + ry + 1.0:
			var x := floori(xc - rx - 1.0)
			while x <= xc + rx + 1.0:
				var dx := (x + 0.5 - xc) / rx
				var dy := (y + 0.5 - y0) / ry
				var nz := Px.tileNoise((x + 0.5) * 0.35 + 10.0 * ph + w * 7, (y + 0.5) * 0.5, 10.0, 0.0, seed + 20.0 + w)
				var v := (1.0 - dx * dx - dy * dy) * a + 0.6 * nz - 0.25
				if v > 0.0:
					p.blend(x + 0.5, y + 0.5, K[2] if v > 0.4 else K[3], minf(0.6, 0.2 + v * 0.7))
				x += 1
			y += 1


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var K := Px.fit(o.cloud, 7)
	var RN := Px.fit(o.rain, 4)
	var S := Px.ramp(o.sparks)
	var f := floori(t * FPS + 1e-6) % N
	var ph := f / float(N)
	var B := billows(o.seed, ph)
	var br := Px.rng(o.seed, 5, BOLT)
	var ba := f - BOLT
	var bx0: float = BILLOWS[BOLT_B][0] + br.range(-4.0, 4.0)
	var bx1 := br.range(-24.0, 24.0)
	# what's lighting the cloud this frame: discharges inside billows, and the billow the bolt leaves from
	var flashes := {}
	for fl: Array in FLASHES:
		if fl[0] == f:
			flashes[fl[1]] = fl[2]
	if ba >= 0 and ba < BK.size():
		flashes[BOLT_B] = maxf(flashes.get(BOLT_B, 0.0), BK[ba])
	var lights := []
	for b: int in flashes:
		var k: float = flashes[b]
		var bb: Dictionary = B[b]
		lights.append({"x": bb.x, "y": bb.y, "k": k, "r": bb.r * VIS * (1.6 if bb.sq < 1.0 else 2.2)})
	var flash: float = lights.reduce(func(s, l): return maxf(s, l.k), 0.0)

	# rain: slanting streaks from the belly, splashing on the floor, lit when the sky flashes
	Px.cycle(t, P, 150, o.seed + 11, func(g): return g.range(0.5, 0.62), func(age, life, r):
		var x0: float = r.range(-62.0, 62.0)
		var vy: float = r.range(190.0, 240.0)
		var vx := -vy * 0.18
		var tf := (0.0 - (BASE + 4.0)) / vy
		if age < tf:
			var x: float = x0 + vx * age
			var y: float = BASE + 4.0 + vy * age
			var l: float = r.range(4.0, 6.5)
			p.line(x - vx * 0.018 * (l / 4.0), y - l, x, y, func(u): return ((C[5] if flash > 0.5 else RN[3])) if u > 0.7 else (C[3] if flash > 0.5 else RN[2 if u > 0.35 else 1]))
		elif age < tf + 0.12:
			var x: float = x0 + vx * tf
			var a: float = (age - tf) / 0.12
			for s in [-1, 1]:
				p.px(x + s * (1.0 + a * 2.5), -1.0 - sin(a * PI) * 2.5, RN[3] if a < 0.5 else RN[2])
			if a < 0.4:
				p.px(x, 0.0, RN[3]))
	# the scud hanging under the base, the cloud, then the light of whatever burns inside it
	scud(p, ph, o.seed, K)
	cloud(p, B, ph, o.seed, K, C, flashes)
	for l: Dictionary in lights:
		p.glow(l.x, l.y, l.r, C[4], 0.4 * l.k)
	p.glow(0.0, -122.0, 80.0, C[2], 0.05 + 0.22 * flash)
	# a discharge crawls along the belly now and then
	for fl: Array in FLASHES:
		var ff: int = fl[0]
		var b: int = fl[1]
		var k: float = fl[2]
		if ff == f and k > 0.6:
			var r := Px.rng(o.seed, 7, ff)
			var x: float = B[b].x
			Lib.crackle(p, Lib.zigzag(r, x - r.range(12.0, 22.0), BASE - r.range(2.0, 6.0), x + r.range(12.0, 22.0), BASE - r.range(1.0, 5.0), 0.25, 0.5), 0.6, C, 0.4)
	# the bolt: struck once a loop, forked, flickering, the floor lit and sparks thrown where it lands
	if ba >= 0 and ba < BK.size():
		var k: float = BK[ba]
		Lib.stroke(p, Lib.zigzag(Px.rng(o.seed, 9, BOLT), bx0, BASE - 3.0, bx1, 0.0, 0.22, 0.7), k, C, 1.15 if ba == 0 else 1.0, {"hero": ba == 0})
		p.circle(bx1, -1.0, 3.0 * k + 1.5, C[2])
		p.circle(bx1, -1.0, 3.0 * k + 0.5, C[5])
		p.circle(bx1, -1.0, 2.0 * k, WHITE)
		p.glow(bx1, -22.0, 78.0, C[3], 0.5 * k)
		p.glow(bx1, -3.0, 18.0, C[5], 0.45 * k)
		p.glow(bx0, BASE, 84.0, C[4], 0.3 * k)
	var sa := Px.wrap(t - BOLT / FPS, P)
	for j in 16:
		var q := Px.rng(o.seed, 31, j)
		var life := q.range(0.25, 0.6)
		if sa >= life:
			continue
		var a := -PI / 2.0 + q.range(-1.3, 1.3)
		var sp := q.range(60.0, 200.0)
		var fl := Lib.flight(bx1, -1.0, cos(a) * sp, sin(a) * sp, sa, {"floor": 0.0})
		Lib.spark(p, fl[0], fl[1], fl[2], fl[3], 1.0 - sa / life, S)
