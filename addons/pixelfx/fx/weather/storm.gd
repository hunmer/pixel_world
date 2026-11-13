# The bolt (a branching path, a stepped leader, strokes that flicker frame by frame, light along the channel) and
# the rain (streaks with lit heads, splashes that throw droplets) are adapted from Sprite Fusion's open-source
# lightning (https://www.spritefusion.com/pixel-art-vfx/lightning), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/storm.js@b6fb1b121b23df7400fdefbe653d5267ff6a1e55
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P

static var meta := {
	"name": "Storm",
	"desc": "Driving rain at two depths under a churning cloud deck; a forked bolt strikes in a double flash that lights the sky and the rain, then sheet lightning glows in the clouds.",
	"tags": ["weather", "storm", "rain", "lightning", "thunder", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 170],
	"duration": 10.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#09080f", "#121120", "#1b1a30", "#262541", "#363a5c", "#4f5d8c", "#7790c6", "#c2d6ff"],
		"bolt": ["#2a1a6e", "#4835c2", "#6a6cff", "#78b8ff", "#c6ebff", "#ffffff"],
		"seed": 5,
	},
}

const D := 10.0
const SLANT := 0.42
# the strike: a stepped leader feels its way down, the first stroke, a restrike down the same channel
const T_LEAD := 2.62
const T1 := 3.0
const T2 := 3.3
const T_SHEET := 6.4
const T_FAR := 8.6
const BX0 := 62.0
const BY0 := -136.0
const BX1 := 52.0
const BY1 := 3.0
const F1 := [1.0, 0.62, 0.95, 0.4, 0.7, 0.22]
const F2 := [0.92, 0.5, 0.8, 0.3, 0.12]


static func env(t: float, t0: float, E: Array) -> float:
	var i := floori((t - t0) * 30 + 1e-3)
	return E[i] if (i >= 0 and i < E.size()) else 0.0


static func flashAt(t: float) -> float:
	return maxf(env(t, T1, F1), env(t, T2, F2))


# sheet lightning: light that swells inside the clouds with no bolt to see, twice; and a far flicker
static func sheetAt(t: float) -> float:
	var a := t - T_SHEET
	if a < 0 or a > 0.9:
		return 0.0
	var p1 := exp(-pow((a - 0.08) / 0.05, 2))
	var p2 := exp(-pow((a - 0.3) / 0.09, 2))
	var tail := exp(-(a - 0.3) * 6) * 0.5 if a > 0.3 else 0.0
	return minf(1, 0.7 * p1 + p2 + tail) * (0.75 if int(floorf(a * 30)) % 3 == 1 else 1.0)


static func blink(a: float, k: float) -> float:
	return 0.0 if (a < 0 or a > 0.3) else k * (exp(-pow((a - 0.06) / 0.04, 2)) + 0.65 * exp(-pow((a - 0.18) / 0.05, 2)))


static func farAt(t: float) -> float:
	return blink(t - T_FAR, 0.45)


static func far2At(t: float) -> float:
	return blink(t - 0.9, 0.3)


# times are snapped so a runtime's accumulated float time (2.9999999) lands on the frame it means
static func snap(t: float) -> float:
	return Px.round(t * 3e4) / 3e4


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	t = snap(t)
	var q := Lib.clip(p, meta)
	var B := Lib.box(meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	var V := Px.fit(o.bolt, 6)
	var f := flashAt(t)
	var sh := sheetAt(t)
	var far := farAt(t)
	var lead := 0.25 + 0.2 * sin(t * 70) if (t > T_LEAD and t < T1) else 0.0
	var pre := 0.12 * maxf(0, sin((t - T_LEAD) * 41)) if (t > T_LEAD - 0.5 and t < T_LEAD) else 0.0
	# what lights the clouds from inside: the bolt's root, the sheet lightning, the far flicker
	var srcs := []
	if f + lead + pre > 0:
		srcs.append([BX0, BY0 - 6, 150.0, f + lead * 0.5 + pre])
	if sh > 0:
		srcs.append([-96.0, -146.0, 120.0, sh])
	if far > 0:
		srcs.append([128.0, -156.0, 80.0, far])
	if far2At(t) > 0:
		srcs.append([-40.0, -160.0, 70.0, far2At(t)])
	var litAt := func(x: float, y: float) -> float: return _litAt(srcs, x, y)
	sky(p, t, f, V)
	if sh > 0.05:
		var V2: int = V[2]
		Lib.pass_(p, meta, -170, 0, func(x: float, y: float, out: Lib.Out) -> void:
			var d := Px.hypot(x + 96, (y + 150) * 1.3) / 170
			if d < 1:
				out.l = V2
				out.k = sh * 0.3 * (1 - d) * (1 - d))
	veil(p, t, S, C, V, f)
	# far rain behind the bolt; the bolt's root disappears up into the cloud
	rain(q, t, S, C, V, f, 0)
	if t > T_LEAD and t < T2 + 0.7:
		bolt(q, t, S, V)
	deck(q, B, t, S, C, V, litAt, srcs.size() > 0)
	crawler(q, t, S, V)
	floor_(q, B, t, S, C, V, f)
	strike(q, t, S, C, V)


# drawBack()'s litAt(x, y)
static func _litAt(srcs: Array, x: float, y: float) -> float:
	var L := 0.0
	for s: Array in srcs:
		var sx: float = s[0]
		var sy: float = s[1]
		var R: float = s[2]
		var k: float = s[3]
		var d := Px.hypot(x - sx, (y - sy) * 1.5) / R
		if d < 1:
			L += k * (1 - d) * (1 - d)
	return minf(1, L)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	t = snap(t)
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	var V := Px.fit(o.bolt, 6)
	var f := flashAt(t)
	rain(q, t, S, C, V, f, 1)


# the whole sky lights up with each stroke, most near the bolt
static func sky(p: Px.Painter, _t: float, f: float, V: Array) -> void:
	var k := f * 0.36
	if k <= 0.01:
		return
	var c := Px.mix(V[2], V[3], 0.6)
	Lib.pass_(p, meta, -170, 9, func(x: float, _y: float, out: Lib.Out) -> void:
		var d := absf(x - (BX0 + BX1) / 2) / 230
		out.l = c
		out.k = k * (0.2 + 0.8 * pow(maxf(0, 1 - d), 2.2)))


# the cloud deck, seen from below in perspective: rows of rolls, the nearest and biggest at the top, each row
# further off hanging a little lower, smaller and hazier. Every roll swells, drifts on the wind and dissolves on
# its own clock (born once a loop), so the underside churns with no seam. Each row's lower edge catches a 1 px
# rim of light and throws a line of shadow on the row behind it.
const ROWS := [
	{"base": -161.0, "wob": 3.0, "n": 18, "rx": [16.0, 30.0], "ry": 0.8, "drift": 15.0, "life": [4.0, 7.0], "tone": [1, 2, 3, 4], "tex": 1},
	{"base": -150.0, "wob": 3.0, "n": 22, "rx": [10.0, 20.0], "ry": 0.85, "drift": 10.0, "life": [3.5, 6.5], "tone": [1, 2, 3, 5], "tex": 1},
	{"base": -140.0, "wob": 3.0, "n": 26, "rx": [7.0, 14.0], "ry": 0.9, "drift": 6.0, "life": [3.0, 6.0], "tone": [2, 2, 3, 5], "tex": 0, "haze": true},
]


# the storm cell hangs lowest over the strike
static func sag(x: float) -> float:
	return 9 * exp(-pow((x - 40) / 95, 2)) - 3


# each roll pushes down out of its row, drifts on the wind and draws back up, on its own clock (born once a loop)
static func rolls(S: float, t: float) -> Array:
	var all := []
	for j in ROWS.size():
		var Rw: Dictionary = ROWS[j]
		var out := []
		for i in Rw.n:
			var L: float = Rw.life[0] + Px.rand(S, j, i, 1) * (Rw.life[1] - Rw.life[0])
			var age := Px.wrap(t - Px.rand(S, j, i, 2) * D, D)
			if age >= L:
				continue
			var u := age / L
			var g := pow(sin(PI * u), 0.6)
			var rx: float = Rw.rx[0] + Px.rand(S, j, i, 3) * (Rw.rx[1] - Rw.rx[0])
			var ry: float = rx * Rw.ry
			var x: float = -200 + Px.rand(S, j, i, 4) * 400 + Rw.drift * (age - L / 2)
			out.append({"x": x, "h": ry * g * (0.6 + 0.4 * Px.rand(S, j, i, 5)), "rx": rx * (0.8 + 0.2 * g)})
		all.append(out)
	return all


# sheets of rain sweeping across on the gusts: a translucent haze, streaked along the rain, that hides the stars
# and catches the flash where it's thickest
static func veil(p: Px.Painter, t: float, S: float, C: Array, V: Array, f: float) -> void:
	var F := Lib.field(S + 11, 256, 128, [4, 8, 16])
	var shift := (256 * 2 * t) / D
	var glow := Px.mix(C[3], V[3], 0.5)
	var C1: int = C[1]
	Lib.pass_(p, meta, -170, -0.5, func(x: float, y: float, out: Lib.Out) -> void:
		var n := Lib.sample(F, (x - y * SLANT) * 1.9 - shift, y * 0.16 + 7)
		var dens := Px.clamp(0.45 + (n - 0.5) * 2.6)
		out.c = Px.mix(C1, glow, minf(1, f * dens * 0.7 * maxf(0.25, 1 - absf(x - BX1) / 220))) if f > 0.05 else C1
		out.a = 0.4 + 0.38 * dens
		out.b = 1)


static func deck(q: Px.Painter, B: Dictionary, t: float, S: float, C: Array, V: Array, litAt: Callable, lit: bool) -> void:
	var R := rolls(S, t)
	var F := Lib.field(S * 3 + 1, 256, 128)
	var drift := (256 * t) / D
	var n := ROWS.size()
	var mo := pow(cos((PI * t) / D), 2)
	var RAMP := [C[0], C[1], C[2], C[3], C[4], C[5], C[6], V[4], Px.WHITE]
	var top := PackedFloat32Array()
	top.resize(n)
	var bot := PackedFloat32Array()
	bot.resize(n)
	var bulge := PackedFloat32Array()
	bulge.resize(n)
	var V3: int = V[3]
	for x in range(B.x0, B.x1):
		var cx := x + 0.5
		var low := -170.0
		# each row hangs as a curtain: a wavy base with rolls bulging out of it
		for j in n:
			var Rw: Dictionary = ROWS[j]
			var und := (Lib.sample(F, cx * 0.55 + j * 91, 3) * mo + Lib.sample(F, cx * 0.55 + j * 91, 60) * (1 - mo) - 0.5) * 2
			var c: float = Rw.base + sag(cx) * (0.4 + j * 0.3) + 7 * und + Rw.wob * 2 * (Lib.sample(F, cx * 1.8 + j * 61 - drift * (0.5 - j * 0.1), 20 + j * 17) - 0.5)
			var bump := 0.0
			for b: Dictionary in R[j]:
				var dx: float = (cx - b.x) / b.rx
				if dx * dx < 1:
					bump = maxf(bump, b.h * sqrt(1 - dx * dx))
			var y1 := c + bump
			top[j] = -999
			bot[j] = y1
			bulge[j] = bump
			low = maxf(low, y1)
		var prev := -1
		var prevBot := -999.0
		var y: int = B.y0
		while y < low:
			var cy := y + 0.5
			var j := 0
			while j < n and not (cy >= top[j] and cy < bot[j]):
				j += 1
			if j >= n:
				prev = -1
				y += 1
				continue
			if j != prev:
				if prev >= 0 and prev < j:
					prevBot = cy
				prev = j
			var Rw: Dictionary = ROWS[j]
			var d := bot[j] - cy
			var tone: Array = Rw.tone
			var th := Lib.bayer(x, y)
			# light catches the lower edge of each row, most on the big bulges, and fades up into a dark core
			var i: int
			if d < 1:
				i = tone[3] if bulge[j] > 3 else tone[3] - 1
			elif cy - prevBot < 1.5 and j > 0:
				i = maxi(0, tone[0] - 1)  # shadow under the row in front
			elif d < 2 + bulge[j] * 0.25 + th * 2:
				i = tone[2]
			elif d < 6 + bulge[j] * 0.4 + th * 3:
				i = tone[1]
			else:
				var nn := Lib.sample(F, cx * 0.9 + j * 77 - drift * (0.6 - j * 0.12), cy * 1.7 + j * 31)
				i = tone[0] + (1 if (Rw.tex and nn > 0.6) else 0)
			var lk := 0.0
			if lit:
				var Lv: float = litAt.call(cx, cy)
				if Lv > 0.02:
					i = mini(8, i + Px.roundi(Lv * (4.4 if d < 1 else (3.8 if d < 4 else 3.1))))
					lk = Lv
			if Rw.get("haze", false) and not lk and d >= 1:
				q.blend(x, y, RAMP[i], 0.75)
			else:
				q.px(x, y, RAMP[maxi(0, i)])
			if lk > 0.03:
				q.light(x, y, V3, lk * (0.4 if d < 3 else 0.22))
			y += 1


# the rain: far drops thin and dim, near drops long with bright heads; the flash lights every drop
static func rain(q: Px.Painter, t: float, S: float, C: Array, V: Array, f: float, near: int) -> void:
	if not near:
		var BODY := [C[4], C[4], C[5]]
		var HEAD := [C[5], C[6], C[6]]
		Lib.trips(t, D, 300, S * 7 + 1, 22, 28, func(u: float, k: float, m: float, i: int) -> void:
			var j := Px.wrap(k, m)
			var stop := -14 - Px.rand(S, i, j, 1) * 90
			var y := -176 + (stop + 176) * u
			var x := -170 + Px.rand(S, i, j, 2) * 360 - (stop - y) * SLANT
			var L := 3 + Px.rand(S, i, j, 3) * 2
			var ux := SLANT / Px.hypot(SLANT, 1)
			var uy := 1 / Px.hypot(SLANT, 1)
			var lit := rainLit(f, x)
			var body: int = BODY[lit]
			var head: int = HEAD[lit]
			q.line(x - ux * L, y - uy * L, x - ux * L * 0.4, y - uy * L * 0.4, body)
			q.line(x - ux * L * 0.4, y - uy * L * 0.4, x, y, head))
		return
	var BODY := [C[6], C[6], V[4]]
	var HEAD := [C[7], Px.WHITE, Px.WHITE]
	var TAIL := [C[4], C[5], V[3]]
	Lib.trips(t, D, 84, S * 7 + 2, 30, 38, func(u: float, k: float, m: float, i: int) -> void:
		var j := Px.wrap(k, m)
		var z := 1 + Px.rand(S, i, j, 1) * 4
		var y := -180 + (z + 180) * u
		var x := -175 + Px.rand(S, i, j, 2) * 370 - (z - y) * SLANT
		var L := 9 + Px.rand(S, i, j, 3) * 5
		var ux := SLANT / Px.hypot(SLANT, 1)
		var uy := 1 / Px.hypot(SLANT, 1)
		var lit := rainLit(f, x)
		var body: int = BODY[lit]
		var head: int = HEAD[lit]
		var tail: int = TAIL[lit]
		q.line(x - ux * L, y - uy * L, x - ux * L * 0.55, y - uy * L * 0.55, tail)
		q.line(x - ux * L * 0.55, y - uy * L * 0.55, x - ux, y - uy, body)
		q.px(x, y, head)
		# the drop before this one landed: splash
		var dur := D / m
		var age := u * dur
		if age < 0.4:
			var jp := Px.wrap(k - 1, m)
			var zp := 1 + Px.rand(S, i, jp, 1) * 4
			var xp := -175 + Px.rand(S, i, jp, 2) * 370
			var lit2 := rainLit(f, xp)
			Lib.splash(q, xp, zp, age, 0.25 + (zp - 1) / 5.3, {"hot": Px.WHITE if lit2 else C[7], "cool": [C[5], C[6], V[4]][lit2]}, Px.rand(S, i, jp, 4)))


# rain()'s litAt(x)
static func rainLit(f: float, x: float) -> int:
	var L := f * (0.3 + 0.7 * maxf(0, 1 - absf(x - BX1) / 170))
	return 2 if L > 0.45 else (1 if L > 0.15 else 0)


# the channel: a jagged trunk, three long forks peeling off it (alternating sides), each with twigs of its own
static func channel(S: float) -> Array:
	var R := Px.Rng.new(S * 31 + 1)
	var Pt := Lib.tree(R, BX0, BY0, BX1, BY1, 0.26, 0.18)
	var pts: Array = Pt[0].pts
	var side := R.sign()
	var us := [0.2, 0.38, 0.55]
	for i in us.size():
		var u: float = us[i]
		var k := floori(u * (pts.size() - 1))
		var ax: float = pts[k][0]
		var ay: float = pts[k][1]
		var bp: Array = pts[mini(pts.size() - 1, k + 3)]
		var bx: float = bp[0]
		var by: float = bp[1]
		var a := atan2(by - ay, bx - ax) + (-side if i % 2 else side) * R.range(0.6, 1.0)
		var l := R.range(36, 56) * (1 - u * 0.45)
		Pt.append_array(Lib.tree(R, ax, ay, ax + cos(a) * l, ay + sin(a) * l, 0.3, 0.5, 0.6, 1))
	return Pt


static func bolt(q: Px.Painter, t: float, S: float, V: Array) -> void:
	var P1 := channel(S)
	if t < T1:
		var reach := BY0 + (BY1 - BY0) * pow(floorf(((t - T_LEAD) / (T1 - T_LEAD)) * 9) / 9, 1.25)
		for p: Dictionary in P1:
			var pts: Array = p.pts
			for i in pts.size() - 1:
				var ax: float = pts[i][0]
				var ay: float = pts[i][1]
				var bx: float = pts[i + 1][0]
				var by: float = pts[i + 1][1]
				if by > reach:
					break
				q.line(ax, ay, bx, by, V[2] if p.w >= 1 else V[1])
				if i % 4 == 0:
					q.glow(ax, ay, 6, V[3], 0.22 * p.w)
		return
	# the restrike runs down the same channel, with fewer, shorter forks
	var P2: Array = [P1[0]] + Lib.tree(Px.Rng.new(S * 31 + 2), BX0, BY0, BX1, BY1, 0.3, 0.3).slice(1, 3)
	var s := 2 if t >= T2 else 1
	var a := t - (T2 if s == 2 else T1)
	var k := env(t, T2 if s == 2 else T1, F2 if s == 2 else F1)
	var paths := P2 if s == 2 else P1
	if k > 0:
		stroke(q, paths, k, V)
	elif a < 0.5:
		var g := 1 - a / 0.5
		for p: Dictionary in paths:
			if p.w >= 1:
				for xy: Array in p.pts:
					q.dot(xy[0], xy[1], V[1], g * 0.9)


# spider lightning crawling along the cloud base while the sheet lightning glows: drawn a frame at a time, the
# crawl reaching a little further each frame, then gone
static func crawler(q: Px.Painter, t: float, S: float, V: Array) -> void:
	var a := t - T_SHEET - 0.22
	if a < 0 or a > 0.17:
		return
	var Pt := Lib.tree(Px.Rng.new(S * 7 + 3), -150, -138, -26, -134, 0.2, 0.7)
	var reach := -150 + 130 * minf(1, (floorf(a * 30) + 1) / 3)
	var k := 1.0 if a < 0.1 else 0.5
	for p: Dictionary in Pt:
		var pts: Array = p.pts
		for i in pts.size() - 1:
			var ax: float = pts[i][0]
			var ay: float = pts[i][1]
			var bx: float = pts[i + 1][0]
			var by: float = pts[i + 1][1]
			if ax > reach:
				break
			q.line(ax, ay, bx, by, V[4] if (p.w >= 1 and k > 0.6) else V[3])
			if p.w >= 1:
				q.dot(ax, ay + 1, V[2], k)
			if i % 3 == 0:
				q.glow(ax, ay, 10, V[3], 0.35 * k * p.w)


# a stroke: a violet sheath, a pale blue body, a white-hot core (two pixels wide at the peak), light all along
static func stroke(q: Px.Painter, paths: Array, k: float, V: Array) -> void:
	for pass_ in [0, 1, 2]:
		for p: Dictionary in paths:
			var w: float = p.w
			var trunk := w >= 1
			if not trunk and (k < 0.4 or (pass_ == 0 and w < 0.5)):
				continue
			var pts: Array = p.pts
			for i in pts.size() - 1:
				var ax: float = pts[i][0]
				var ay: float = pts[i][1]
				var bx: float = pts[i + 1][0]
				var by: float = pts[i + 1][1]
				var l := maxf(1, Px.hypot(bx - ax, by - ay))
				var d := 0.0
				while d <= l:
					var x := ax + ((bx - ax) * d) / l
					var y := ay + ((by - ay) * d) / l
					if pass_ == 0:
						q.circle(x, y, ((2.3 if k > 0.6 else 1.7) if trunk else 1.2), V[2] if k > 0.6 else V[1])
					elif pass_ == 1:
						q.circle(x, y, ((1.4 if k > 0.6 else 0.9) if trunk else 0.6), V[4] if trunk else V[3])
					elif trunk:
						q.px(x, y, Px.WHITE if k > 0.3 else V[4])
						if k > 0.85:
							q.px(x + 1, y, Px.WHITE)
					elif w > 0.4 and k > 0.6:
						q.px(x, y, V[4])
					d += 0.5
				if pass_ == 0 and i % 3 == 0:
					q.glow(ax, ay, 18 if trunk else 8, V[3], (0.5 if trunk else 0.3) * k * w)


# where the bolt lands: a blinding hit, sparks that skip off the wet floor, steam, a glow that cools
static func strike(q: Px.Painter, t: float, S: float, C: Array, V: Array) -> void:
	var a := t - T1
	if a < 0 or a > 1.8:
		return  # the last spray is gone by 1.6 s
	var k := flashAt(t)
	if k > 0:
		# arcs skitter out along the wet floor, new ones every frame
		var fr := floorf(t * 30 + 1e-3)
		var Rc := Px.Rng.new(S * 977 + fr)
		for i in 4:
			var side := 1 if i % 2 else -1
			var l := Rc.range(10, 30) * (0.6 + 0.4 * k)
			for p: Dictionary in Lib.tree(Rc, BX1 + side, BY1 - 1, BX1 + side * l, BY1 + Rc.range(-2, 3), 0.35, 0.5, 0.6, 1):
				var pts: Array = p.pts
				q.polyline(pts, V[4] if (k > 0.6 and p.w > 0.5) else V[3])
				q.glow(pts[pts.size() >> 1][0], pts[pts.size() >> 1][1], 8, V[3], 0.3 * k)
		q.circle(BX1, BY1 - 1, 2 + 3 * k, V[4])
		q.circle(BX1, BY1 - 1, 1 + 2 * k, Px.WHITE)
		q.glow(BX1, BY1 - 12, 95, V[2], 0.55 * k)
		q.glow(BX1, BY1 - 4, 40, V[3], 0.5 * k)
		q.glow(BX1, BY1 - 2, 14, Px.WHITE, 0.6 * k)
	var ps := Px.Particles.new({"rng": Px.Rng.new(S * 13 + 5), "ground": func(): return 4.0, "sparks": [Px.WHITE, V[4], V[3], V[2]], "haze": V[2]})
	var R := ps.R
	var steam := Px.mix(C[4], V[3], 0.3)
	var burst := func(n: float, pw: float) -> void:
		for i in int(n):
			var an := -PI / 2 + R.range(-1.35, 1.35)
			var sp := R.range(110, 420) * pw
			ps.spawn(P.SPARK, BX1, BY1 - 1, cos(an) * sp, sin(an) * sp, R.range(0.18, 0.6))
		# a skirt of spray and steam blown out along the floor
		var i := 0
		while i < 6 * pw:
			var sd := R.sign()
			ps.spawn(P.VAPOUR, BX1 + sd * R.range(2, 8), BY1 - R.range(1, 3), sd * R.range(30, 90), -R.range(4, 16), R.range(0.6, 1.2), steam, R.range(2.5, 4.5), R.range(0, 0.08))
			i += 1
	burst.call(48, 1)
	var tt := 0.0
	var second := false
	var dt := 1 / 120.0
	while tt + dt <= a:
		if not second and tt >= T2 - T1:
			second = true
			burst.call(16, 0.7)
		ps.update(dt)
		tt += dt
	ps.draw(q)
	if a < 1.6:
		q.glow(BX1, BY1, 16, V[2], 0.4 * pow(1 - a / 1.6, 2))


# the wet floor: a dark sheen, a broken lip of light, pools that reflect the sky and flash with it, mist kicked
# up by the rain drifting along the ground
static func floor_(q: Px.Painter, _B: Dictionary, t: float, S: float, C: Array, V: Array, f: float) -> void:
	var F := Lib.field(S + 3, 256, 128)
	var M := Lib.field(S + 4, 256, 128, [4, 8, 16])
	var wind := (256 * 3 * t) / D
	var C1: int = C[1]
	var C3: int = C[3]
	var C4: int = C[4]
	var C5: int = C[5]
	var V3: int = V[3]
	var V4: int = V[4]
	Lib.pass_(q, meta, -14, -0.5, func(x: float, y: float, out: Lib.Out) -> void:
		var m := Lib.sample(M, x * 1.1 - wind, y * 4 + 9) - 0.4
		if m <= 0:
			return
		out.c = Px.mix(C4, V3, f) if f > 0.1 else C4
		out.a = minf(0.3, m * 0.9) * (1 + y / 14)
		out.b = 1)
	Lib.pass_(q, meta, 0, 9, func(x: float, y: float, out: Lib.Out) -> void:
		var wet := _pool(F, x, y)
		var lip := wet and not _pool(F, x, y - 1)
		out.b = 1
		out.c = C1
		out.a = 0.5
		if y < 1:
			out.c = C4 if Lib.sample(F, x * 2, 50) > 0.5 else C3
			out.a = 1
			out.b = 0
		elif wet:
			var d := absf(x - BX1) / 150
			if f > 0.06:
				out.c = V4 if ((d < 0.25 and f > 0.5) or lip) else V3
				out.a = Px.clamp(f * (1.35 - d) * (1.4 if lip else 1.0))
				out.b = 0
			else:
				out.c = C5 if lip else C3
				out.a = 1.0 if lip else 0.7
			out.l = V3
			out.k = f * 0.25 * maxf(0, 1 - d))
	# the bolt's reflection in the pools, broken by ripples
	if f > 0.2:
		for y in range(1, 10):
			if Px.rand(y, floorf(t * 30), 3) < 0.8:
				q.dot(BX1 + sin(y * 1.7 + t * 40) * 1.2, y, Px.WHITE if y < 4 else V[4], f * (1.1 - y / 12.0))


# floor_()'s pool(yy)
static func _pool(F: Lib.Field, x: float, yy: float) -> bool:
	return Lib.sample(F, x * 1.3 + 31, yy * 9) > 0.6 - yy * 0.006
