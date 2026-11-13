# port-of: src/fx/status/frozen.js@7ef8ecedc74ea65e71899349d414192b1e8b2126
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Frozen",
	"desc": "Chilled to the bone: frost ferns creep over the body, icicles hang from chin and hands and drip, breath steams, snow settles, a shiver every second, frost spreads underfoot.",
	"tags": ["status", "ice", "freeze", "frozen", "cold", "chill", "debuff", "loop"],
	"size": [72, 64],
	"origin": [36, 54],
	"duration": 2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "seed": 4},
}

static var STIFF := {"turn": 0.9, "crouch": 1, "fx": -6, "fy": -15, "bx": 7, "by": -15, "ffx": -2, "fbx": 3}
static var act := {
	"onBody": true,
	"poses": [[0, Px.merge(STIFF, {"crouch": 2})], [0.22, STIFF], [1, STIFF], [1, Px.merge(STIFF, {"crouch": 2}), "snap"], [1.22, STIFF], [2, Px.merge(STIFF, {"crouch": 2})]],
}

static var D: float = meta.duration
const SHIVER := 1.0
static func since(t: float) -> float:
	return fmod(fmod(t, SHIVER) + SHIVER, SHIVER)
## The effect draws the whole (chilled, shivering) body, so the stand-in is hidden throughout.
static func actorAlpha(_t: float, _o: Dictionary) -> float:
	return 0.0
static func shake(t: float) -> int:
	return (1 if floori(t * 50.0) % 2 else -1) if since(t) < 0.22 else 0

# worked out once per character: fern paths creeping in from the outline, icicle roots, snow ledges, the mouth
static var PLANS := {}
static func plan(a: Dictionary, seed: float) -> Dictionary:
	var m: Variant = PLANS.get(a.mask.id)
	if not m:
		m = {}
		PLANS[a.mask.id] = m
	if m.has(seed):
		return m[seed]
	var S := Lib.shape(a)
	var H: int = S.h
	var W: int = S.w
	var on: Callable = S.on
	var R := Px.Rng.new(seed * 11.0 + 1.0)
	# ferns: a stem walking in from an edge with fronds branching off it at alternate sides, each pixel ordered by when it grows
	var ferns := []
	var roots: Array = Px.sort(S.side.filter(func(xyd): return xyd[1] > H * 0.2 and xyd[1] < H * 0.85), func(_p, _q): return R.next() - 0.5).slice(0, 6)
	for i in roots.size():
		var x: float = roots[i][0]
		var y: float = roots[i][1]
		var dir: int = roots[i][2]
		var ang := -0.5 if dir < 0 else PI + 0.5
		ang += R.range(-0.4, 0.4)
		for s in 9:
			x += cos(ang) * 1.1
			y += sin(ang) * 1.1
			var px := Px.round(x)
			var py := Px.round(y)
			if not on.call(px, py):
				break
			ferns.append([px, py, s / 9.0, i])
			if s % 2 == 1:
				for side: int in [-1, 1]:
					var ba := ang + side * 1.05
					var L := 1.0 + Px.round(R.range(0.0, 2.0) * (1.0 - s / 9.0))
					var k := 1
					while k <= L:
						var bx := Px.round(x + cos(ba) * k)
						var by := Px.round(y + sin(ba) * k)
						if on.call(bx, by):
							ferns.append([bx, by, (s + k * 0.6) / 9.0, i])
						k += 1
			ang += R.range(-0.25, 0.25)
	# icicles under the hair tips, the jaw and the hands: bottom edges with clear space under them
	var clear := func(x: int, y: int) -> int:
		var n := 0
		while n < 7 and y + 1 + n < H and not on.call(x, y + 1 + n):
			n += 1
		return n
	var hangs: Array = S.body.filter(func(xy): return not on.call(xy[0], xy[1] + 1) and on.call(xy[0], xy[1] - 1) and xy[1] < H * 0.72 and xy[1] > 4).map(func(xy): return [xy[0], xy[1], clear.call(xy[0], xy[1])]).filter(func(xyc): return xyc[2] >= 4)
	var best := func(f: Callable, key: Callable) -> Variant:
		var l: Array = Px.sort(hangs.filter(f), key)
		return l[0] if l.size() else null
	var picks := [
		best.call(func(h): return h[1] < H * 0.36, func(p, q): return p[0] - q[0]),
		best.call(func(h): return h[1] < H * 0.36, func(p, q): return q[0] - p[0]),
		best.call(func(h): return h[1] >= H * 0.36 and h[1] < H * 0.5 and h[0] < W / 2.0, func(p, q): return q[0] - p[0]),
		best.call(func(h): return h[1] >= H * 0.36 and h[1] < H * 0.5 and h[0] >= W / 2.0, func(p, q): return p[0] - q[0]),
		best.call(func(h): return h[1] >= H * 0.5 and h[0] < W / 2.0, func(p, q): return p[0] - q[0]),
		best.call(func(h): return h[1] >= H * 0.5 and h[0] >= W / 2.0, func(p, q): return q[0] - p[0]),
	].filter(func(v): return v != null)
	var icicles := []
	for i in picks.size():
		var xyc: Array = picks[i]
		icicles.append({"x": xyc[0], "y": xyc[1] + 1, "len": minf(xyc[2] - 1, R.range(3.0, 5.5)), "phase": R.next(), "period": 1.0 if i % 2 else 2.0})
	# snow ledges: the upward edges of the head and the shoulders
	var snow: Array = S.up.filter(func(xy): return xy[1] < H * 0.6).map(func(xy): return [xy[0], xy[1], 1 + (1 if Px.rand(xy[0], seed, 3) < 0.45 else 0)])
	var E := Lib.eyes(a)
	var mouth := [(E[0].x1 + E[1].x0 + 1) / 2.0, maxi(E[0].y1, E[1].y1) + 2] if E.size() == 2 else [W / 2.0, H * 0.38]
	var out := {"ferns": ferns, "icicles": icicles, "snow": snow, "mouth": mouth}
	m[seed] = out
	return out


# frost on the floor round the feet: a white crust, a pale bloom under it, its edge creeping out and back
static func frost(p: Px.Painter, C: Array, t: float, reach: float) -> void:
	for x in range(-ceili(reach) - 1, floori(reach + 1.0) + 1):
		var q := absf(x + 0.5) / reach
		var h := Px.rand(x, 17)
		var k := 1.0 - q * q
		if q > 1.0 + h * 0.15:
			continue
		var tw := sin((t / D) * TAU * 2.0 + Px.rand(x, 3) * TAU) > 0.94
		p.px(x, 0.0, C[7] if (tw or h < 0.3) else (C[5] if q > 0.85 else C[6]))
		if h < 0.3 * k:
			p.px(x, -1.0, C[6])
		for j in range(1, 1 + Px.roundi(2.0 * k) + 1):
			p.dot(x, j, C[5] if j == 1 else C[4], (1.05 - j / 4.0) * 0.85)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var reach := 13.0 + 3.5 * sin((t / D) * TAU)
	p.shade(-28.0, -3.0, 28.0, 6.0, func(x, y, out):
		var d := Px.hypot(x / 24.0, (y - 0.5) / 4.0)
		if d < 1.0:
			out.l = C[4]
			out.k = 0.24 * (1.0 - d) * (1.0 - d))
	frost(p, C, t, reach)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var a: Dictionary = o.actor
	var S := Lib.shape(a)
	var H: int = S.h
	var P := plan(a, o.seed)
	var dx := shake(t)
	var ph := since(t)
	var on: Callable = S.on
	var ax: int = a.x
	var ay: int = a.y
	var X := func(mx): return ax + mx + dx
	var Y := func(my): return ay + my
	# the body, chilled: its colours pulled toward ice; the rim frosted and lit
	for b: Array in S.body:
		var mx: int = b[0]
		var my: int = b[1]
		var c := Lib.colorAt(a, mx, my)
		var ice: int = C[int(Px.clamp(1.0 + Px.round(Px.luma(c) * 5.6), 1.0, 7.0))]
		var rim: bool = not on.call(mx - 1, my) or not on.call(mx, my - 1) or not on.call(mx + 1, my)
		p.px(X.call(mx), Y.call(my), (C[5] if (my < H * 0.5 or not on.call(mx - 1, my)) else C[3]) if (rim and Px.luma(c) < 0.3) else Px.mix(c, ice, 0.38))
	# frost ferns creeping in from the outline; each shiver cracks most of it off and it creeps back
	var grow := 0.2 + 0.65 * Px.smooth(0.05, 0.95, ph)
	for fe: Array in P.ferns:
		var x: float = fe[0]
		var y: float = fe[1]
		var u: float = fe[2]
		if u < grow:
			p.px(X.call(x), Y.call(y), WHITE if u > grow - 0.1 else (C[6] if Px.rand(x, y, 5) < 0.5 else C[5]))
	# snow settled on the head and shoulders
	for sn: Array in P.snow:
		var x: int = sn[0]
		var y: int = sn[1]
		var d: int = sn[2]
		p.px(X.call(x), Y.call(y) - 1, C[7])
		if d > 1:
			p.px(X.call(x), Y.call(y) - 2, C[7] if Px.rand(x, y, 9) < 0.5 else C[6])
	# icicles hanging under the chin, hands and hair: they grow, a drop gathers and falls, they shrink back
	for ic: Dictionary in P.icicles:
		var per: float = ic.period
		var u := fmod(fmod(t / per + ic.phase, 1.0) + 1.0, 1.0)
		var L: float = ic.len * (0.55 + 0.45 * Px.smooth(0.0, 0.7, u))
		var x: float = X.call(ic.x)
		var y0: float = Y.call(ic.y)
		var j := 0
		while j < L:
			var v := j / L
			p.px(x, y0 + j, WHITE if v > 0.75 else (C[7] if v < 0.3 else C[6]))
			if v < 0.5:
				p.px(x + 1.0, y0 + j, C[4])
			j += 1
		# the drop: it swells at the tip, lets go and falls to the floor
		if u > 0.7 and u < 0.86:
			p.px(x, y0 + L, C[6])
		elif u >= 0.86:
			var f := (u - 0.86) * per
			var y := y0 + L + 0.5 * 760.0 * f * f
			if y < -1.0:
				p.px(x, y, C[6])
				p.px(x, y - 1.0, C[5])
		p.glow(x, y0 + L * 0.6, 4.0, C[5], 0.18)
	# breath steaming from the mouth between shivers
	var mx0: float = P.mouth[0]
	var my0: float = P.mouth[1]
	for i in 4:
		var age := ph - 0.35 - i * 0.05
		if age < 0.0 or age > 0.65:
			continue
		var u := age / 0.65
		var x: float = X.call(mx0) + 1.0 + Lib.travel(16.0, 0.0, 2.2, age) + i
		var y: float = Y.call(my0) - Lib.travel(6.0, 3.0, 1.0, age) - i * 0.5
		var rad := 0.8 + 2.4 * sqrt(u)
		p.disc(x, y, rad, C[7], 0.5 * (1.0 - u) * minf(1.0, u * 8.0))
		p.disc(x - rad * 0.2, y - rad * 0.3, rad * 0.5, WHITE, 0.4 * (1.0 - u))
	# snow falling and settling; flakes flung off by the shiver
	Px.cycle(t, D, 9, o.seed + 2, func(r): return r.range(1.2, 1.8), func(age, _life, r):
		var x: float = r.range(-14.0, 14.0) + sin(age * 3.0 + r.next() * TAU) * 1.5
		var y: float = a.y - 16.0 + age * 14.0
		if y > a.y + 2.0:
			return
		p.dot(x, y, WHITE if r.next() < 0.5 else C[6], minf(1.0, age * 4.0)))
	if ph < 0.5:
		for i in 8:
			var side := 1.0 if i % 2 else -1.0
			var vx := side * (20.0 + 30.0 * Px.rand(i, 4))
			var vy := -(20.0 + 30.0 * Px.rand(i, 5))
			var x := side * (6.0 + 6.0 * Px.rand(i, 6)) + vx * ph
			var y: float = a.y + 3.0 * Px.rand(i, 7) + vy * ph + 0.5 * 300.0 * ph * ph
			p.dot(x, y, C[6] if i % 3 else WHITE, 1.2 - ph * 2.0)
	if ph < 0.25:
		Px.sparkle(p, X.call(Px.round(S.w * 0.3)), Y.call(4), Px.round(3.0 * (1.0 - ph / 0.25)), C[6], C[5], 0.4)
	# cold light: off the body, lifting with each shiver
	p.glow(0.0, a.y + H * 0.45, 30.0, C[4], 0.2 + 0.12 * exp(-ph / 0.2))
	p.glow(0.0, a.y + 2.0, 16.0, C[5], 0.1)
