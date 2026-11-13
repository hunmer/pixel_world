# The coin's pop (a white disc, then a ring and stars) and the trails of flying coins adapt Sprite Fusion's
# open-source pickup (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ui/coin-collect.js@7bed56e70ec15538b8147f3f8caf16fd2811993b
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Coin collect",
	"desc": "A coin bursts into a fountain of spinning coins that hang, then zip one by one into a HUD counter that pops and ticks up, glints and folds away.",
	"tags": ["ui", "coins", "pickup", "reward", "hud", "counter", "one-shot"],
	"size": [176, 116],
	"origin": [60, 102],
	"duration": 2.45,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#2a1405", "#5c3008", "#9a5a0e", "#d48e18", "#f5b92c", "#ffde5e", "#fff4bc", "#ffffff"], "count": 10, "from": 12, "seed": 4},
}

const POP := 0.3
const FLY0 := 0.58
const GAP := 0.075
const FLY := 0.28
const FOLD := 2.0
const CY := -16.0
# the HUD: a plate at the top right with a coin icon and the count
const HX := 50.0
const HY := -88.0
const HW := 60.0
const HH := 22.0
const IX := HX + 12.0
const IY := HY + 11.0
static var INK := {"outline": Px.hex("#0d0a14"), "rim": Px.hex("#4a4060"), "top": Px.hex("#2a2338"), "body": Px.hex("#1e1929"), "low": Px.hex("#141019")}
static var K5A4F6E := Px.hex("#5a4f6e")
static var K0D0A14 := Px.hex("#0d0a14")


# a coin r px across, turned so its face is w wide (0..1): a dark edge, a rim lit on its upper left, a face lit
# from the top left with an embossed bar, white when it flashes
static func coin(p: Px.Painter, C: Array, x: float, y: float, r: float, w: float, white: bool = false) -> void:
	var rx := maxf(0.7, r * w)
	var ry := r
	p.shade(x - rx - 1.0, y - ry - 1.0, x + rx + 1.0, y + ry + 1.0, func(px: float, py: float):
		var u := (px - x) / rx
		var v := (py - y) / ry
		var d := Px.hypot(u, v)
		if d > 1.0:
			return null
		var e := (1.0 - d) * minf(rx * 1.6, ry)
		if white:
			return C[6] if e < 1.0 else WHITE
		if e < 1.0:
			return C[1]
		if rx < 2.0:
			return C[6] if v < -0.2 else (C[4] if v < 0.4 else C[3])
		if e < 2.0:
			return C[6] if u + v < -0.2 else C[3]
		if absf(px - x) < 0.55 and absf(v) < 0.5:
			return C[3]
		if px - x >= 0.55 and px - x < 1.55 and absf(v) < 0.5:
			return C[7]
		var l := -(u * 0.6 + v * 0.8)
		return C[7] if l > 0.4 else (C[6] if l > 0.05 else (C[5] if l > -0.35 else C[4])))


var C: Array
var R: Px.Rng
var N: float
var ps: Px.Particles
var lights: Px.Lights
var end: float
var coins: Array
var t := 0.0
var popped := false
var count: int
var bump := 0.0
var flash := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	N = Px.clamp(Px.round(o.count), 1.0, 12.0)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [C[7], C[6], C[5], C[3]]})
	lights = Px.Lights.new()
	end = meta.duration - 0.05
	coins = Px.arr(N, func(i: int):
		var s := (i / maxf(1.0, N - 1.0)) * 2.0 - 1.0
		return {"x": 0.0, "y": CY, "vx": s * R.range(55.0, 90.0) + R.range(-12.0, 12.0), "vy": -R.range(170.0, 285.0), "ph": R.range(0.0, TAU), "spin": R.range(9.0, 14.0) * R.sign(), "state": 0, "t0": FLY0 + i * GAP, "fx": 0.0, "fy": 0.0, "trail": [], "bob": R.range(0.0, TAU)})
	count = int(Px.round(o.from))


func update(dt: float) -> void:
	t += dt
	if not popped and t >= POP:
		popped = true
		lights.add(0.0, CY, 46.0, WHITE, 0.8, 0.14)
		lights.add(0.0, CY, 48.0, C[5], 0.6, 0.5)
		for i in 14:
			var an := (i / 14.0) * TAU + R.range(-0.2, 0.2)
			var sp := R.range(80.0, 170.0)
			ps.spawn(P.SPARK, cos(an) * 3.0, CY + sin(an) * 3.0, cos(an) * sp, sin(an) * sp - 30.0, R.range(0.15, 0.35))
		for i in 4:
			ps.spawn(P.DUST, R.range(-6.0, 6.0), -1.0, R.sign() * R.range(15.0, 40.0), -R.range(2.0, 8.0), R.range(0.3, 0.5), K5A4F6E, R.range(1.5, 2.5))
		# a ring of stars flung out of the burst
		for i in 10:
			var an := (i / 10.0) * TAU + R.range(-0.2, 0.2)
			var sp := R.range(70.0, 130.0)
			var down := 0.25 if sin(an) > 0.0 else 1.0
			ps.spawn(P.STAR, cos(an) * 6.0, CY + sin(an) * 6.0, cos(an) * sp, sin(an) * sp * down, R.range(0.35, 0.6), R.pick([C[7], C[6], C[5]]), 0.6 if i % 3 else R.range(1.2, 2.0))
	for c: Dictionary in coins:
		if not popped or c.state == 3:
			continue
		c.ph += c.spin * dt
		if c.state < 2:
			# the fountain: thrown up, slowed by the air, then they hang and bob
			if c.state == 0:
				c.vy += 640.0 * dt
				c.vx -= c.vx * 2.2 * dt
				if c.vy > 0.0:
					c.state = 1
			else:
				c.vy -= c.vy * 7.0 * dt
				c.vx -= c.vx * 4.0 * dt
			c.x += c.vx * dt
			c.y += c.vy * dt
			if t >= c.t0:
				c.state = 2
				c.fx = c.x
				c.fy = c.y + sin(t * 6.0 + c.bob) * 1.5
		if c.state == 2:
			# the flight: an arc up and over into the HUD's coin, quickening as it goes
			var u := Px.clamp((t - c.t0) / FLY)
			var e := u * u
			var mx: float = c.fx + (IX - c.fx) * 0.35
			var my: float = minf(c.fy, IY) - 26.0
			c.x = (1.0 - e) * (1.0 - e) * c.fx + 2.0 * (1.0 - e) * e * mx + e * e * IX
			c.y = (1.0 - e) * (1.0 - e) * c.fy + 2.0 * (1.0 - e) * e * my + e * e * IY
			c.trail.push_front([c.x, c.y])
			if c.trail.size() > 7:
				c.trail.pop_back()
			# it sheds sparkles as it goes
			if R.chance(0.25):
				ps.spawn(P.STAR, c.x + R.range(-2.0, 2.0), c.y + R.range(-2.0, 2.0), R.range(-8.0, 8.0), R.range(-4.0, 10.0), R.range(0.2, 0.4), R.pick([C[7], C[6]]), 0.6)
			if u >= 1.0:
				c.state = 3
				count += 1
				bump = 1.0
				flash = 1.0
				lights.add(IX, IY, 26.0, C[5], 0.6, 0.25)
				for i in 3:
					var an := R.range(0.0, TAU)
					var sp := R.range(18.0, 40.0)
					ps.spawn(P.STAR, IX + cos(an) * 5.0, IY + sin(an) * 5.0, cos(an) * sp, sin(an) * sp, minf(R.range(0.25, 0.45), end - t), R.pick([C[7], C[6]]), 0.6 if i else R.range(1.2, 1.8))
	bump = maxf(0.0, bump - dt / 0.14)
	flash = maxf(0.0, flash - dt / 0.07)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# a ring on the floor where the coin bursts
	var k := (t - POP) / 0.45
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.0, 4.0 + 34.0 * Px.Ease.outCubic(k), 0.22, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, C, func(g: float): return sin(g) < 0.0)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var k := (t - POP) / 0.45
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.0, 4.0 + 34.0 * Px.Ease.outCubic(k), 0.22, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, C, func(g: float): return sin(g) >= 0.0)
	# the big coin: bobbing and turning above its shadow, then it bursts in a white disc
	if t < POP + 0.02:
		var y := CY + sin(t * 9.0) * 1.5
		var w := absf(cos(t * 7.0))
		p.ellipse(0.0, 0.5, 6.0 - 0.5 * sin(t * 9.0), 1.3, K0D0A14, 0.6)
		# two motes circle it, passing behind and in front
		for i in 2:
			var an := t * 7.0 + i * PI
			var ox := cos(an) * 11.0
			var oy := sin(an) * 3.0
			if sin(an) < 0.0:
				p.px(ox, y + oy, C[4])
		coin(p, C, 0.0, y, 7.0, maxf(0.12, w), t > POP - 0.04)
		for i in 2:
			var an := t * 7.0 + i * PI
			var ox := cos(an) * 11.0
			var oy := sin(an) * 3.0
			if sin(an) >= 0.0:
				p.px(ox, y + oy, C[7])
				p.glow(ox, y + oy, 4.0, C[5], 0.4)
		p.glow(0.0, y, 20.0, C[5], 0.45 + 0.4 * Px.seg(t, POP - 0.15, POP))
		if t > 0.06 and t < 0.2:
			Px.sparkle(p, -3.0, y - 3.0, 3.5 * sin(((t - 0.06) / 0.14) * PI), C[7], C[6], 0.4)
	var pk := (t - POP) / 0.1
	if pk > 0.0 and pk < 1.0:
		p.circle(0.0, CY, 13.0 * (1.0 - pk) + 1.0, WHITE if pk < 0.5 else C[6])
	var fk := (t - POP) / 0.2
	if fk > 0.0 and fk < 1.0:
		Px.flare(p, 0.0, CY, 26.0 * pow(1.0 - fk, 1.5), 1.0 - fk, C)
	var rk := (t - POP - 0.03) / 0.35
	if rk > 0.0 and rk < 1.0:
		p.ring(0.0, CY, 6.0 + 22.0 * Px.Ease.outCubic(rk), maxf(1.0, 2.0 * (1.0 - rk)), WHITE if rk < 0.3 else C[6], 1.2 - rk)
	# the coins and their trails
	for c: Dictionary in coins:
		if not popped or c.state == 3:
			continue
		var tr: Array = c.trail
		for i in tr.size():
			if i > 0:
				p.line(tr[i - 1][0], tr[i - 1][1], tr[i][0], tr[i][1], C[6] if i < 3 else C[4], 1.2 - i / 7.0)
		var hover: float = sin(t * 6.0 + c.bob) * 1.5 if c.state == 1 else 0.0
		var w := absf(cos(c.ph))
		coin(p, C, c.x, c.y + hover, 5.0, maxf(0.15, w))
		p.glow(c.x, c.y + hover, 10.0, C[5], 0.5 if c.state == 2 else 0.32)
		# light catches each hanging coin now and then
		var gl := fmod(t * 1.7 + c.bob, 1.0)
		if c.state == 1 and gl < 0.12 and w > 0.5:
			Px.sparkle(p, c.x - 1.0, c.y + hover - 2.0, 3.0 * sin((gl / 0.12) * PI), C[7], C[6], 0.4)
	# the HUD: unfolds, counts up with a pop on every coin, glints, folds away
	var open := Px.Ease.outBack(Px.seg(t, 0.06, 0.26), 2.2) * (1.0 - Px.Ease.inBack(Px.seg(t, FOLD, FOLD + 0.2), 2.0))
	if open > 0.04:
		var h := HH * open
		var y0 := HY + (HH - h) / 2.0
		var sh := Px.seg(t, 1.5, 1.76)
		Lib.panel(p, HX, y0, HW, h, INK, {"r": minf(4.0, h / 2.0), "shine": HX - 6.0 + (HW + 16.0) * sh if (sh > 0.0 and sh < 1.0) else null})
		if open > 0.7:
			coin(p, C, IX, IY, 5.5 * (1.0 + 0.3 * bump), 1.0, flash > 0.5)
			p.glow(IX, IY, 14.0, C[5], 0.25 + 0.4 * bump)
			if bump > 0.0:
				p.ring(IX, IY, 7.0 + 8.0 * (1.0 - bump), 1.0, WHITE if bump > 0.6 else C[6], bump * 1.3)
			var s := 2.0 * (1.0 + 0.22 * bump)
			var st := "x" + str(count)
			var word := Lib.spell(st)
			var W: float = word.w * s
			var H := 7.0 * s
			var x0 := IX + 9.0
			var ty := IY - H / 2.0
			var items := []
			for L: Dictionary in word.letters:
				if L.g != null:
					items.append({"g": L.g, "x": x0 + L.x * s, "y": ty, "sx": s, "sy": s, "flash": 1.0 if flash > 0.5 else 0.0})
			Lib.drawWord(p, items, {"fill": [C[4], C[5], C[6], C[7]], "edge": WHITE, "under": C[3], "outline": INK.outline, "shadow": 0})
			if bump > 0.0:
				p.glow(x0 + W / 2.0, IY, 16.0, C[5], 0.3 * bump)
	ps.draw(p, "front")
	lights.draw(p)
