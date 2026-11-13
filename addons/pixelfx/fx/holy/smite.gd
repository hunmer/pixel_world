# port-of: src/fx/holy/smite.js@bbfe3825e06e97aece43af1099acaf5f3e3a379b
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Smite",
	"desc": "A glint marks the spot, then a bolt of light drops like a hammer: a white flash, a shockwave over the floor, stone chips flying and cracks that glow and cool.",
	"tags": ["holy", "smite", "strike", "impact", "light", "ground", "one-shot"],
	"size": [224, 176],
	"origin": [112, 148],
	"duration": 2.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.GOLD, "stone": "#5a5066", "seed": 9},
}

const TOP := -148.0
const SY := 0.38
const MARK := 0.42
const HIT := 0.54
const LEN := 44.0
static var OUTLINE := Px.hex("#1a1422")

# a chip of stone: lit side, shaded side, outline
static func chip(p: Px.Painter, b: Dictionary, st: Array) -> void:
	var r: float = 0.6 + b.s * 0.7
	var fade := minf(1.0, b.life / 0.5)
	var lx: float = cos(b.a) * r * 0.4
	var ly: float = sin(b.a) * r * 0.4
	p.shade(b.x - r - 1.0, b.y - r - 1.0, b.x + r + 1.0, b.y + r + 1.0, func(x: float, y: float, out) -> void:
		var dx: float = x - b.x
		var dy: float = y - b.y
		var d := Px.hypot(dx * 1.2, dy)
		if d > r + 0.9:
			return
		var lit := dx * lx + dy * ly
		out.c = OUTLINE if d > r else (st[3] if lit < -0.3 else (st[1] if lit > 0.5 else st[2]))
		out.a = fade)


var C: Array
var R: Px.Rng
var s0: int
var st: Array
var dust: int
var ps: Px.Particles
var chips: Px.Bits
var lights: Px.Lights
var cracks: Array
var t := 0.0
var hit := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	s0 = Px.hex(o.stone)
	st = [Px.scale(s0, 0.5), Px.scale(s0, 0.75), s0, Px.mix(Px.scale(s0, 1.4), WHITE, 0.1)]
	dust = Px.mix(s0, Px.hex("#8a8094"), 0.4)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[3]]})
	chips = Px.Bits.new({"ground": func(): return 0.0})
	lights = Px.Lights.new()
	# cracks across the floor, mostly out to the sides and towards us, each its own length
	cracks = Px.arr(7, func(i: int):
		var a := 0.12 + (i / 6.0) * (PI - 0.24) + R.range(-0.12, 0.12)
		var L := R.range(30.0, 54.0) * (0.6 if absf(sin(a)) > 0.7 else 1.0)
		var pts := Px.bolt(R, 0.0, 0.0, cos(a) * L, sin(a) * L, {"jag": 0.28, "depth": 4}).map(func(q): return [q[0], q[1] * SY])
		var fork: Variant = null
		if pts.size() > 6:
			var m: Array = pts[floori(pts.size() * 0.5)]
			fork = Px.bolt(R, m[0], m[1], pts[floori(pts.size() * 0.5)][0] + cos(a + R.sign() * 0.7) * L * 0.35, pts[floori(pts.size() * 0.5)][1] + sin(a + R.sign() * 0.7) * L * 0.35 * SY, {"jag": 0.3, "depth": 3})
		return {"pts": pts, "fork": fork, "L": L, "cool": R.range(1.6, 2.1)})


# the hammer of light: a heavy blunt bolt that falls faster and faster
func tipY(tt: float) -> float:
	return Px.lerp(TOP - 6.0, 0.0, Px.Ease.inCubic(Px.seg(tt, MARK, HIT)))


func hammer(p: Px.Painter) -> void:
	if t < MARK or t >= HIT + 0.06:
		return
	var y1 := 0.0 if t >= HIT else tipY(t)
	var y0 := maxf(TOP + 5.0, y1 - LEN * (1.0 - (t - HIT) / 0.06 if t >= HIT else 1.0))
	var white := t >= HIT
	if y1 < TOP + 12.0:
		return
	var CC := C
	# speed lines above it
	for dk: Array in [[-5.0, 0.6], [-2.0, 0.9], [2.0, 0.8], [5.0, 0.5]]:
		var dx: float = dk[0]
		var k: float = dk[1]
		if y0 > TOP + 2.0:
			p.line(dx, maxf(TOP, y0 - 70.0), dx, y0, func(u): return CC[6] if u > 0.7 else CC[4], func(u): return u * k)
	if y1 - 3.0 > y0:
		p.beam(0.0, y0, 0.0, y1 - 3.0, 9.0, func(u, v): return WHITE if (white or v < 0.35) else (CC[6] if v < 0.7 else CC[5]))
	# the head: wider, white hot
	p.beam(0.0, y1 - 6.0, 0.0, y1 - 1.0, 13.0, func(u, v): return WHITE if (v < 0.6 or white) else CC[6])
	p.glowLine(0.0, y0 + 10.0, 0.0, y1, 16.0, C[5], 0.6)
	p.glow(0.0, y1 - 4.0, minf(22.0, y1 - TOP - 6.0), WHITE, 0.5)


func crack(p: Px.Painter) -> void:
	if t < HIT:
		return
	var grow := Px.Ease.outCubic(Px.seg(t, HIT, HIT + 0.1))
	for c: Dictionary in cracks:
		for path: Array in ([c.pts, c.fork] if c.fork else [c.pts]):
			var n := maxf(1.0, Px.round((path.size() - 1) * grow))
			var i := 0
			while i < n:
				var x0: float = path[i][0]
				var y0: float = path[i][1]
				var x1: float = path[i + 1][0]
				var y1: float = path[i + 1][1]
				var d: float = Px.hypot(x0, y0 / SY) / c.L
				var heat := Px.clamp(1.0 - (t - HIT) / c.cool - d * 0.5)
				if heat <= 0.0:
					i += 1
					continue
				var col: int = WHITE if heat > 0.85 else (C[6] if heat > 0.65 else (C[5] if heat > 0.45 else (C[4] if heat > 0.3 else (C[3] if heat > 0.18 else C[2]))))
				p.line(x0, y0, x1, y1, col, heat / 0.12 if heat < 0.12 else 1.0)
				# wide and deep near the heart, a hairline at the tips
				if d < 0.45 and is_same(path, c.pts):
					p.line(x0, y0 + 1.0, x1, y1 + 1.0, C[4] if heat > 0.5 else C[2], heat / 0.12 if heat < 0.12 else 1.0)
				if i % 2 == 0:
					p.glow(x0, y0, 10.0, C[4], 0.45 * heat)
				i += 1
	# the crater glows at the heart and cools
	var h := Px.clamp(1.0 - (t - HIT) / 1.6)
	if h > 0.0:
		Lib.oval(p, 0.0, 0.0, 5.0, 1.6, WHITE if h > 0.6 else (C[5] if h > 0.3 else C[3]), minf(1.0, h * 3.0))
		p.glow(0.0, 0.0, 18.0, C[4], 0.45 * h)


func update(dt: float) -> void:
	t += dt
	if t < MARK and R.chance(0.25):
		ps.spawn(P.STAR, R.range(-10.0, 10.0), -R.range(0.0, 18.0), 0.0, -R.range(4.0, 12.0), R.range(0.2, 0.4), WHITE if R.chance(0.5) else C[6], R.range(0.5, 1.2))
	# sparks shed off the sides of the falling hammer
	if t > MARK and t < HIT and tipY(t) > TOP + 50.0 and R.chance(0.6):
		ps.spawn(P.MOTE, R.sign() * R.range(4.0, 7.0), tipY(t) - R.range(4.0, 30.0), R.range(-20.0, 20.0), -R.range(10.0, 40.0), R.range(0.15, 0.3), C[6], 0.7)
	if not hit and t >= HIT:
		hit = true
		lights.add(0.0, -24.0, 92.0, C[5], 1.0, 0.6)
		lights.add(0.0, -8.0, 40.0, WHITE, 0.9, 0.12)
		for i in 60:
			var a := -PI / 2.0 + R.range(-1.25, 1.25)
			var sp := R.range(110.0, 280.0)
			ps.spawn(P.SPARK, R.range(-3.0, 3.0), -2.0, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.75))
		for i in 16:
			var a := -PI / 2.0 + R.range(-1.0, 1.0)
			var sp := R.range(60.0, 160.0)
			ps.spawn(P.STAR, R.range(-4.0, 4.0), -4.0, cos(a) * sp, sin(a) * sp, R.range(0.4, 0.9), WHITE if R.chance(0.5) else C[6], R.range(0.8, 2.4))
		for i in 14:
			var a := -PI / 2.0 + R.range(-1.2, 1.2)
			var sp := R.range(90.0, 230.0)
			chips.add({"kind": B.CHUNK, "x": R.range(-5.0, 5.0), "y": -2.0, "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 1.0, "drag": 0.4, "bounce": 0.35, "life": R.range(1.2, 1.8), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": R.int_(1, 3)})
		for i in 34:
			var a := -PI / 2.0 + R.range(-1.0, 1.0)
			var sp := R.range(60.0, 220.0)
			ps.spawn(P.GRIT, R.range(-4.0, 4.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(0.9, 1.5), R.pick(st.slice(1)), 2.0 if R.chance(0.4) else 1.0)
		# dust rolls out along the floor, a little smoke lifts off the crater
		for i in 9:
			var s := R.sign()
			ps.spawn(P.SMOKE, s * R.range(2.0, 10.0), -R.range(1.0, 4.0), s * R.range(50.0, 130.0), -R.range(2.0, 12.0), R.range(0.7, 1.2), Px.mix(dust, C[4], 0.18), R.range(3.5, 6.0), R.range(0.0, 0.06), PF.BIG)
		for i in 4:
			ps.spawn(P.SMOKE, R.range(-4.0, 4.0), -R.range(2.0, 8.0), R.range(-8.0, 8.0), -R.range(20.0, 45.0), R.range(1.2, 1.8), Px.mix(dust, C[5], 0.25), R.range(4.0, 6.0), R.range(0.05, 0.3))
	# the cracks spit embers while they're hot
	if t > HIT and t < HIT + 1.3 and R.chance(0.5):
		var c: Dictionary = R.pick(cracks)
		var q: Array = R.pick(c.pts)
		if R.chance(0.75):
			ps.spawn(P.EMBER, q[0], q[1] - 1.0, R.range(-8.0, 8.0), -R.range(15.0, 35.0), R.range(0.5, 0.9), C[5])
		else:
			ps.spawn(P.STAR, q[0], q[1] - 2.0, 0.0, -R.range(4.0, 12.0), R.range(0.3, 0.6), WHITE if R.chance(0.5) else C[6], R.range(0.8, 1.8))
	chips.update(dt)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	crack(p)
	ps.draw(p, "back")
	var k := Px.seg(t, HIT, HIT + 0.42)
	if t >= HIT and k < 1.0:
		Px.band(p, 0.0, 0.0, 6.0 + 84.0 * Px.Ease.outCubic(k), SY * 0.8, maxf(1.0, 5.0 * (1.0 - k)), 1.15 - k, C.slice(3), func(g): return sin(g) < 0.0, k < 0.12)


func draw(p: Px.Painter) -> void:
	var CC := C
	# the mark: a glint on the floor and a ring closing on it
	if t < HIT:
		var u := Px.seg(t, 0.0, MARK)
		var k := Px.smooth(0.0, 0.08, t)
		var spin := t * 3.0
		var rr := Px.lerp(26.0, 8.0, Px.Ease.inOutCubic(u))
		Lib.oval(p, 0.0, 0.0, rr, rr * SY, func(g): return WHITE if sin(g * 4.0 + spin) > 0.0 else CC[5], k * (0.65 + 0.35 * sin(t * 40.0)))
		Lib.oval(p, 0.0, 1.0, rr, rr * SY, C[3], k * 0.6, func(g): return sin(g) > 0.0)
		var L := (3.0 + 8.0 * Px.Ease.outBack(Px.clamp(t / 0.2), 2.0)) * (1.0 + 0.6 * Px.seg(t, MARK, HIT) if t > MARK else 1.0)
		for i in 4:
			var a := spin * 0.3 + (i * PI) / 2.0
			var len := L * 0.6 if i % 2 else L
			p.line(0.0, -2.0, cos(a) * len, -2.0 + sin(a) * len, func(v): return WHITE if v < 0.4 else CC[5], func(v): return 1.2 - v)
		p.px(0.0, -2.0, WHITE)
		p.glow(0.0, -2.0, 14.0 + 10.0 * u, C[5], 0.5 * k)
		p.glowLine(0.0, TOP + 6.0, 0.0, -2.0, 5.0, C[4], 0.12 * u)
	hammer(p)
	# the bolt's afterimage: a thread of light from the sky to the mark, thinning out
	var ai := Px.seg(t, HIT + 0.04, HIT + 0.55)
	if t > HIT + 0.04 and ai < 1.0:
		var w := 1.0 + 4.0 * pow(1.0 - ai, 2.0)
		p.beam(0.0, TOP + 4.0, 0.0, -4.0, w, func(u, v): return WHITE if v < 0.5 else CC[5], func(u): return (0.3 + 0.7 * u) * (1.0 - ai * 0.5))
		p.glowLine(0.0, TOP + 16.0, 0.0, -6.0, 10.0, C[5], 0.4 * (1.0 - ai))
	var k := Px.seg(t, HIT, HIT + 0.42)
	if t >= HIT and k < 1.0:
		Px.band(p, 0.0, 0.0, 6.0 + 84.0 * Px.Ease.outCubic(k), SY * 0.8, maxf(1.0, 5.0 * (1.0 - k)), 1.15 - k, C.slice(3), func(g): return sin(g) >= 0.0, k < 0.12)
	# the air shock: a dome of light thrown up over the hit
	var d := Px.seg(t, HIT, HIT + 0.28)
	if t >= HIT and d < 1.0:
		var r := 8.0 + 40.0 * Px.Ease.outCubic(d)
		p.arc(0.0, 0.0, r, maxf(1.0, 3.0 * (1.0 - d)), PI, TAU, func(u, v): return WHITE if (d < 0.2 or v > 0.6) else CC[5], 1.1 - d)
		var g := PI * 1.1
		while g < TAU - 0.2:
			p.glow(cos(g) * r, sin(g) * r, 8.0, C[5], 0.3 * (1.0 - d))
			g += 0.5
	# the white hero frame
	if t >= HIT and t < HIT + 0.07:
		p.circle(0.0, -6.0, 16.0, WHITE)
		p.circle(0.0, -6.0, 19.0, C[6], 0.6)
	for b: Dictionary in chips.list:
		chip(p, b, st)
	ps.draw(p, "front")
	if t >= HIT and t < HIT + 0.25:
		Px.sparkle(p, 0.0, -8.0, 16.0 * (1.0 - (t - HIT) / 0.25), WHITE, C[5], 0.7)
	lights.draw(p)
