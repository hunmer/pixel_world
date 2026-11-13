# port-of: src/fx/ui/combo-counter.js@2aaf9f4d38a5d88e4eddd76a317b23399b34299e
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Combo counter",
	"desc": "x5 COMBO rockets in on streaming speed lines, smearing, and slams to a stop: a white flash, a ring, sparks; it pulses while a timer bar drains, then whooshes out.",
	"tags": ["ui", "combo", "counter", "combat", "text", "one-shot"],
	"size": [208, 100],
	"origin": [104, 50],
	"duration": 1.45,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": ["#1a0516", "#3d0a33", "#701560", "#b0228f", "#f53cd1", "#ff86e6", "#ffd2f6", "#ffffff"], "count": 5, "label": "COMBO", "seed": 6},
}

const HIT := 0.1
const BEAT := 0.5
const OUT := 1.1


# a burst of speed lines across the frame, re-thrown every frame like a comic panel; k fades them
static func speedLines(p: Px.Painter, C: Array, t: float, k: float, dir: float) -> void:
	if k <= 0.02:
		return
	var f := floorf(t * 30.0)
	for i in 18:
		if Px.rand(f, i, 3) > k:
			continue
		var y := Px.round((Px.rand(f, i, 1) - 0.5) * 60.0)
		var L := 16.0 + Px.rand(f, i, 2) * 50.0
		var x := (Px.rand(f, i, 4) - 0.5) * 190.0
		var x0 := maxf(-100.0, x - L / 2.0)
		var x1 := minf(100.0, x + L / 2.0)
		p.line(x0, y, x1, y, func(u: float): return WHITE if (u if dir > 0.0 else 1.0 - u) > 0.75 else (C[6] if (u if dir > 0.0 else 1.0 - u) > 0.35 else C[4]), func(u: float): return 0.6 if (u if dir > 0.0 else 1.0 - u) < 0.25 else 1.0)


var o: Dictionary
var C: Array
var R: Px.Rng
var SHADOW: int
var ps: Px.Particles
var lights: Px.Lights
var big: Dictionary
var lab: Dictionary
var BS := 4.0
var LS := 2.0
var W: float
var X0: float
var BASE := 12.0
var spikes: Array
var t := 0.0
var hit := false
var out := false


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	SHADOW = Px.scale(C[0], 0.5)
	ps = Px.Particles.new({"rng": R, "sparks": [C[7], C[6], C[5], C[3]]})
	lights = Px.Lights.new()
	big = Lib.spell("x" + str(int(Px.round(o.count))))
	lab = Lib.spell(o.label)
	W = big.w * BS + 4.0 + lab.w * LS
	X0 = -W / 2.0
	spikes = Px.arr(10, func(i): return [(i / 10.0) * TAU + R.range(-0.15, 0.15), R.range(14.0, 24.0)])


# where the words sit: rocketing in from the left, overshooting, settling; whooshing out to the right
static func xAt(tt: float) -> float:
	tt = maxf(0.0, tt)
	if tt < HIT:
		return -32.0 * pow(1.0 - tt / HIT, 2.0)
	if tt < OUT:
		return 7.0 * exp(-(tt - HIT) * 18.0) * sin((tt - HIT) * 34.0)
	var u := Px.seg(tt, OUT, OUT + 0.2)
	return -4.0 * Px.Ease.outQuad(u / 0.3) if u < 0.3 else -4.0 + 24.0 * Px.Ease.inQuad((u - 0.3) / 0.7)


func update(dt: float) -> void:
	t += dt
	if not hit and t >= HIT:
		hit = true
		lights.add(0.0, 0.0, 70.0, C[5], 0.7, 0.4)
		lights.add(-20.0, 0.0, 34.0, WHITE, 0.8, 0.1)
		for i in 26:
			var an := R.range(-1.2, 1.2) + (PI if R.chance(0.3) else 0.0)
			var sp := R.range(120.0, 300.0)
			ps.spawn(P.SPARK, R.range(-20.0, 20.0), R.range(-8.0, 8.0), cos(an) * sp, sin(an) * sp * 0.6 - 20.0, R.range(0.12, 0.3))
	# sparkles pop off the count on its beat
	if t > BEAT and t < OUT and R.chance(0.1):
		var x := X0 + R.range(0.0, big.w * BS)
		var y := BASE - R.range(0.0, 30.0)
		ps.spawn(P.STAR, x, y, R.range(-10.0, 10.0), -R.range(5.0, 20.0), R.range(0.25, 0.45), R.pick([C[7], C[6]]), 1.6 if R.chance(0.3) else 0.6)
	if not out and t >= OUT + 0.06:
		out = true
		for i in 10:
			ps.spawn(P.MOTE, R.range(-50.0, 30.0), R.range(-14.0, 10.0), R.range(220.0, 320.0), R.range(-10.0, 10.0), R.range(0.06, 0.14), R.pick([C[7], C[6]]), 1.0)
	ps.update(dt)
	lights.update(dt)


func layout(dx: float, pulse: float, stretch: float, flash: float, a: float) -> Array:
	var bs := BS * (1.0 + 0.12 * pulse)
	var items := []
	var bx: float = X0 + dx - (big.w * BS * (stretch - 1.0)) / 2.0
	var by := BASE - 7.0 * bs
	for L: Dictionary in big.letters:
		if L.g != null:
			items.append({"g": L.g, "x": bx + L.x * BS * stretch, "y": by, "sx": BS * stretch, "sy": bs, "slant": 1.0, "flash": flash, "a": a})
	var lx: float = X0 + dx + big.w * BS * stretch + 4.0
	for L: Dictionary in lab.letters:
		if L.g != null:
			items.append({"g": L.g, "x": lx + L.x * LS * stretch, "y": BASE - 7.0 * LS, "sx": LS * stretch, "sy": LS, "slant": 0.5, "flash": flash, "a": a})
	return items


func draw(p: Px.Painter) -> void:
	var sxy := Lib.shake(t, 3.0, HIT, 0.25, o.seed)
	var sx: float = sxy[0]
	var sy: float = sxy[1]
	# speed lines stream behind it as it rockets in, and again as it leaves
	speedLines(p, C, t, 1.0 if t < HIT else (maxf(0.0, 1.0 - (t - HIT) / 0.35) * 0.9 if t < OUT else Px.seg(t, OUT + 0.04, OUT + 0.12) * (1.0 - Px.seg(t, OUT + 0.18, OUT + 0.3))), -1.0 if t >= OUT else 1.0)
	# the slam: a spiky white star behind the count for two frames, then a ring rolling out
	var hk := t - HIT
	if hk >= 0.0 and hk < 0.07:
		var cx: float = X0 + (big.w * BS) / 2.0
		var k := 1.0 if hk < 0.035 else 1.3
		for sp in spikes:
			var an: float = sp[0]
			var L: float = sp[1]
			var ca := cos(an) * 1.4
			var sa := sin(an)
			if k == 1.0:
				p.beam(cx, 0.0, cx + ca * L, sa * L, 3.0, func(u: float): return WHITE if u < 0.5 else C[6])
			else:
				p.line(cx + ca * L * 0.5, sa * L * 0.5, cx + ca * L * k, sa * L * k, C[5])
	var rk := (t - HIT) / 0.32
	if rk > 0.0 and rk < 1.0:
		var r := 20.0 + 34.0 * Px.Ease.outCubic(rk)
		p.ellipse(sx, sy, r * 1.5, r * 0.75, WHITE if rk < 0.3 else C[5], func(d: float): return 1.25 - rk if d > 1.0 - 1.5 / (r * 0.75) else 0.0)
	ps.draw(p)
	# the words: smeared while they fly, white on the slam, a pulse on the beat, a drained timer underneath
	var x := xAt(t)
	var moving := t < HIT or t > OUT + 0.06
	var stretch := (1.22 if t < HIT else 1.12) if moving else 1.0
	var pulse := exp(-(pow((t - BEAT) / 0.05, 2.0)))
	var flash := 1.0 if ((t >= HIT and t < HIT + 0.07) or pulse > 0.6) else 0.0
	var a := 1.0 - Px.seg(t, OUT + 0.08, OUT + 0.2) if t > OUT else (0.5 if t < 0.035 else 1.0)
	if moving and a > 0.0:
		# two dimmer afterimages trailing the words
		for lc in [[0.03, C[2]], [0.015, C[3]]]:
			var lag: float = lc[0]
			var c: int = lc[1]
			var items := layout(xAt(t - (lag if t < HIT else -lag)) + sx, pulse, stretch, flash, a)
			var faded := []
			for it: Dictionary in items:
				faded.append(Px.merge(it, {"flash": 0.0}))
			Lib.drawWord(p, faded, {"fill": [c], "edge": c, "under": c, "outline": 0, "shadow": 0})
	if a > 0.0:
		var sh := Px.seg(t, 0.62, 0.86)
		var items := layout(x + sx, pulse, stretch, flash, a)
		var moved := []
		for it: Dictionary in items:
			moved.append(Px.merge(it, {"y": it.y + sy}))
		Lib.drawWord(p, moved, {"fill": [C[4], C[5], C[6], C[7]], "edge": WHITE, "under": C[3], "outline": C[0], "ow": 2, "shadow": SHADOW, "shine": X0 - 10.0 + (W + 24.0) * sh if (sh > 0.0 and sh < 1.0) else null, "shineY": BASE - 28.0, "glint": C[6]})
		# the combo timer: a thin bar under the words, draining until it goes
		var bk := Px.seg(t, HIT + 0.1, HIT + 0.2) * (0.0 if t > OUT else 1.0)
		if bk > 0.0:
			var bw := W * bk
			var left := 1.0 - Px.seg(t, HIT + 0.2, OUT)
			var bx := X0 + x + sx
			var by := BASE + 5.0 + sy
			p.rect(bx - 1.0, by - 1.0, bw + 2.0, 4.0, C[0])
			p.rect(bx, by, bw, 2.0, C[1])
			if left > 0.0:
				p.rect(bx, by, bw * left, 2.0, C[5])
				p.rect(bx, by, bw * left, 1.0, C[6])
				p.px(bx + bw * left - 1.0, by, WHITE)
	p.glow(sx - 20.0, 0.0, 60.0, C[4], 0.2 * a + (0.5 * (1.0 - (t - HIT) / 0.15) if (t >= HIT and t < HIT + 0.15) else 0.0) + 0.25 * pulse)
	var g := (t - 0.86) / 0.22
	if g > 0.0 and g < 1.0:
		Px.sparkle(p, X0 + W - 2.0, BASE - 14.0, 6.0 * sin(g * PI), C[7], C[5], 0.5)
	lights.draw(p)
