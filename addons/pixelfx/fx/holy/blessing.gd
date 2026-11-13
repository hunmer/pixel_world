# port-of: src/fx/holy/blessing.js@e3e0ed7add397cb71b4c001e6633497aad44fb3c
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Blessing",
	"desc": "A soft cone of light rests on the character from above; sparkles drift down through it, twinkling, and wink out where they land on the head and shoulders.",
	"tags": ["holy", "blessing", "buff", "light", "sparkle", "character", "loop"],
	"size": [80, 128],
	"origin": [40, 108],
	"duration": 3,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Lib.GOLD, "seed": 7},
}

static var OPEN := {"turn": 1.15, "fx": -13, "fy": -31, "bx": 14, "by": -31, "hy": -1, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"poses": [
		[0, OPEN],
		[0.75, Px.merge(OPEN, {"fy": -33, "by": -33})],
		[1.5, Px.merge(OPEN, {"crouch": -1, "fy": -35, "by": -35})],
		[2.25, Px.merge(OPEN, {"fy": -33, "by": -33})],
		[3, OPEN],
	],
}

const TOP := -108.0
const T := 3.0

static func halfW(y: float) -> float:
	return Px.lerp(5.0, 20.0, (y - TOP) / -TOP)

# the rays in the cone, each shimmering a whole number of times a loop so it closes
const RAYS := [[-0.62, 0.16, 1.0, 0.3], [-0.2, 0.2, 2.0, 1.7], [0.22, 0.14, 1.0, 4.1], [0.6, 0.18, 2.0, 2.6]]

static func ray(q: float, t: float) -> float:
	var I := 0.3 * maxf(0.0, 1.0 - q * q)
	for r: Array in RAYS:
		var o: float = r[0]
		var w: float = r[1]
		var k: float = r[2]
		var ph: float = r[3]
		I += exp(-(pow((q - o) / w, 2.0))) * (0.55 + 0.45 * sin((t / T) * TAU * k + ph)) * 0.6
	return I * Px.smooth(1.25, 0.75, absf(q))

# where each falling sparkle meets the character or the floor (cached per seed and character)
static var LANDS := {}

static func landings(o: Dictionary, S: Dictionary) -> Array:
	var key := "%s:%s:%s" % [o.seed, S.x, S.y]
	if LANDS.has(key):
		return LANDS[key]
	var out := []
	var at: Callable = S.at
	for i in 20:
		var R := Px.rng(o.seed, i)
		var q := R.range(-0.9, 0.9)
		var v := R.range(22.0, 34.0)
		var sway := R.range(1.0, 3.0)
		var ph := R.range(0.0, TAU)
		var size := R.range(0.8, 2.4)
		var land := INF
		var a := 0.0
		while a < 6.0:
			var y := TOP + 6.0 + v * a
			var x := q * halfW(y) + sin(a * 2.2 + ph) * sway
			if y >= -1.0 or at.call(x, y):
				land = a
				break
			a += 0.02
		out.append({"q": q, "v": v, "sway": sway, "ph": ph, "size": size, "land": land})
	LANDS[key] = out
	return out


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	# the cone: soft light with a faint gold haze in it
	p.each(-24.0, TOP, 24.0, 0.5, func(x: float, y: float, sx: int, sy: int) -> void:
		var I := ray(x / halfW(y), t) * (0.6 + 0.4 * Px.smooth(TOP, 0.0, y))
		if I < 0.02:
			return
		p.blendPx(sx, sy, C[6], I * 0.13)
		p.add(sx, sy, C[4], I * 0.22))
	# two of the rays show as fine lines, light running slowly down them
	for r: Array in [RAYS[1], RAYS[2]]:
		var o2: float = r[0]
		var k: float = r[2]
		var ph: float = r[3]
		var y := TOP
		while y < -1.0:
			var pulse := 0.5 + 0.5 * sin(y * 0.11 - (t / T) * TAU * 3.0 + ph)
			p.dot(o2 * halfW(y), y, WHITE if pulse > 0.85 else C[6], (0.1 + 0.45 * pulse) * (0.5 + 0.5 * sin((t / T) * TAU * k + ph)) * Px.smooth(TOP, TOP + 20.0, y))
			y += 1.0
	p.glow(0.0, -4.0, 30.0, C[4], 0.22)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var A: Variant = o.get("actor")
	var S: Variant = Lib.shapeOf(A) if A else null
	# light catching the top of the head and the shoulders
	if A:
		var m: Dictionary = A.mask
		var mw: int = m.w
		var mh: int = m.h
		var PX: PackedInt32Array = A.pixels
		for i in mw:
			for j in mh:
				var c := PX[j * mw + i]
				if not c or Px.luma(c) < 0.15:
					continue
				p.px(A.x + i, A.y + j, Px.mix(c, C[6], 0.35))
				break
		p.glow(0.0, -30.0, 20.0, C[5], 0.22)
	# the floor catches it: a lit line and a pool fading out into the stone
	for y in 4:
		for x in range(-24, 25):
			var u := Px.hypot(x / 24.0, y / 4.0)
			if u >= 1.0:
				continue
			p.dot(x, y, ((C[5] if y else WHITE) if u < 0.3 else (C[5] if u < 0.6 else (C[4] if u < 0.85 else C[3]))), sqrt(1.0 - u) if y == 0 else (1.0 - u) * 0.7)
	# sparkles drifting down, twinkling, winking out where they land
	if S:
		var L := landings(o, S)
		Px.cycle(t, T, L.size(), o.seed, func(g): return 3.0, func(age: float, life: float, R, i: int):
			var s: Dictionary = L[i]
			var y: float = TOP + 6.0 + s.v * age
			var x: float = s.q * halfW(y) + sin(age * 2.2 + s.ph) * s.sway
			var fade := minf(1.0, age / 0.3)
			if age > s.land:
				var w: float = (age - s.land) / 0.14
				if w < 1.0:
					var ly: float = TOP + 6.0 + s.v * s.land
					var lx: float = s.q * halfW(ly) + sin(s.land * 2.2 + s.ph) * s.sway
					Px.sparkle(p, lx, ly, 3.0 * (1.0 - w) + 1.0, WHITE, C[6], 0.5 * (1.0 - w))
				return
			var tw: float = 0.6 + 0.4 * sin(age * (7 + (i % 4)) + s.ph)
			if s.size > 1.2:
				Px.sparkle(p, x, y, s.size * tw * fade, WHITE if tw > 0.85 else C[6], C[5], 0.35 * fade)
			else:
				p.dot(x, y, WHITE if tw > 0.8 else C[6], fade)
				p.glow(x, y, 3.0, C[5], 0.35 * fade))
	# fine motes hanging in the light
	Px.cycle(t, T, 16, o.seed + 9, func(g): return g.range(1.2, 2.4), func(age, life, R):
		var u: float = age / life
		var y: float = TOP + 10.0 + R.range(0.0, 90.0) + u * R.range(6.0, 14.0)
		var q: float = R.range(-1.0, 1.0)
		var x := q * halfW(y) + sin(age * 1.7 + q * 5.0) * 1.5
		var k := sin(u * PI) * ray(q, t)
		if k > 0.12:
			p.dot(x, y, WHITE if k > 0.45 else C[6], minf(1.0, k * 2.2)))
