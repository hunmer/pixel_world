# The spark and fire-ball recipes are adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/rocket.js@f932d473c6560de8f5c78fb1ef60bd98602a6615
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Rocket",
	"desc": "A steel rocket roars along: a flickering jet with shock diamonds and a white-hot nozzle, a thick billowing smoke trail lit by the flame, sparks shed behind.",
	"tags": ["projectile", "rocket", "missile", "smoke", "fire", "directional", "loop"],
	"size": [288, 76],
	"origin": [252, 42],
	"duration": 1.2,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"metal": ["#0f0d16", "#25243a", "#3e4058", "#61667f", "#8e97b0", "#c4cce0", "#f2f6ff"],
		"paint": ["#3a0d14", "#7c1a22", "#bd2f2c", "#ec5a45", "#ff9b7e"],
		"smoke": ["#26222e", "#3d3846", "#5a5463", "#7e7887", "#a7a1ad", "#d0cad2", "#f1ecee"],
		"speed": 120,
		"seed": 5,
	},
}

static var OUTLINE := Px.hex("#100d17")
const NOZZLE := -14.0 # the bell's exit: the jet starts here
const J0 := 22.0 # the jet's mean length

# the rocket: a steel body lit from above with a specular line, a painted ogive nose and band, swept fins with
# lit leading edges, a dark bell with a glowing lip
static var SHIP := Lib.pixelShape(-15, -9, 30, 19, func(set_: Callable) -> void:
	var body := {-3: "4", -2: "6", -1: "5", 0: "4", 1: "3", 2: "2", 3: "1"}
	var seam := {-3: "3", -2: "4", -1: "4", 0: "3", 1: "2", 2: "1", 3: "1"}
	var paint := {-3: "d", -2: "e", -1: "e", 0: "d", 1: "c", 2: "b", 3: "a"}
	for y in range(-3, 4):
		for x in range(-11, 6):
			set_.call(x, y, body[y])
	for y in range(-3, 4):
		set_.call(-3, y, seam[y])
		set_.call(-9, y, paint[y])
		set_.call(-8, y, paint[y])
	var nose := {6: 3, 7: 3, 8: 2, 9: 2, 10: 1, 11: 1, 12: 0, 13: 0}
	for xs: int in nose:
		var h: int = nose[xs]
		for y in range(-h, h + 1):
			set_.call(xs, y, paint[y])
	set_.call(7, -2, "w")
	set_.call(8, -2, "w")
	set_.call(9, -1, "e")
	set_.call(13, 0, "e")
	# fins, the top one in the light, the bottom one in shadow; each leading edge catches a highlight
	var fins := [[-13, -8], [-13, -9], [-13, -10], [-13, -11]]
	for i in fins.size():
		var a: int = fins[i][0]
		var b: int = fins[i][1]
		for x in range(a, b + 1):
			set_.call(x, -4 - i, "5" if x == b else ("4" if i > 1 else "3"))
			set_.call(x, 4 + i, "3" if x == b else ("1" if i > 1 else "2"))
	# the bell: a throat and a flared exit, its lip glowing
	for y in range(-2, 3):
		set_.call(-12, y, "3" if y < 0 else "2")
	for y in range(-3, 4):
		set_.call(-13, y, "2" if y < -1 else "1")
	set_.call(-14, -3, "h")
	set_.call(-14, 3, "h")
	for y in range(-2, 3):
		set_.call(-14, y, "x" if absi(y) < 2 else "h"))


# the jet: a cone of flame out of the bell in clean bands (a red rim, orange, a gold core), white-hot at the
# nozzle, with a chain of shock diamonds down its middle; fr changes every frame so it flickers
static func jet(p: Px.Painter, F: Array, x0: float, y0: float, J: float, wob: float, fr: float) -> void:
	var dia := []
	for i in 4:
		dia.append(3.6 + i * 4.3 + (Px.rand(fr, i, 41) - 0.5) * 0.7)
	p.shade(x0 - J - 2.0, y0 - 6.0, x0, y0 + 6.0, func(x: float, y: float) -> Variant:
		var u := x0 - x
		if u < 0.0:
			return null
		var q := u / J
		if q > 1.05:
			return null
		var ady := absf(y - y0)
		var qq := minf(q, 1.0)
		var w := (2.6 + 2.4 * pow(qq, 0.7)) * (1.0 - qq * qq) * wob
		var m := w - ady + (Px.rand(floorf(x) * 7.0 + floorf(y) * 131.0, fr) - 0.5) * 0.9 * minf(1.0, 0.25 + q * 2.0)
		if m < -0.5:
			return null
		if m < 0.5:
			return F[3 if q < 0.45 else 2]
		for i in dia.size():
			if dia[i] > J * 0.72:
				break
			var d: float = absf(u - dia[i]) / (1.9 - i * 0.15) + ady / (1.7 - i * 0.25)
			if d < 1.0:
				return F[8] if (d < 0.55 and i < 3) else F[7]
		if u < 1.6 and ady < 1.6:
			return F[8]
		var lvl := (1.0 - ady / maxf(0.6, w)) * (1.0 - pow(qq, 1.5))
		return (F[7] if u < 3.0 else F[5]) if lvl > 0.62 else (F[5] if lvl > 0.38 else (F[4] if lvl > 0.16 else F[3])))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var M := Px.fit(o.metal, 7)
	var A := Px.fit(o.paint, 5)
	var SM := Px.fit(o.smoke, 7)
	var S: float = o.seed
	var D: float = meta.duration
	var V: float = o.speed
	var fr := floorf(t * 30.0 + 1e-6)
	var bob := func(tt: float) -> float: return Px.round(sin((tt / D) * TAU) * 0.62)
	var by: float = bob.call(t)
	var J := J0 * (0.84 + 0.32 * Px.rand(fr, S, 1))
	var wob := 0.92 + 0.16 * Px.rand(fr, S, 2)
	var fl := J / J0
	var left: float = -meta.origin[0] + 2.0
	var SP := [F[7], F[6], F[4], F[3]]

	# smoke: puffs leave the tail of the flame, stream back, swell and rise, lit by the fire while young
	var list := []
	Lib.beat(t, D, 66, S + 1.0, func(r): return r.range(1.1, 1.45), func(age: float, life: float, r: Px.Rng) -> void:
		var wk := Lib.wake(NOZZLE - J0 * r.range(0.62, 0.8), bob.call(t - age) + r.range(-1.0, 1.0), -r.range(75.0, 105.0), r.range(-20.0, 20.0), age, V, 3.0, 0.0)
		var x: float = wk[0]
		var y: float = wk[1]
		var k := age / life
		var rise := 0.5 * r.range(6.0, 16.0) * age * age
		var sway := sin(age * 2.3 + r.range(0.0, TAU)) * age * 2.0
		var rad := r.range(2.2, 3.0) + ((r.range(14.0, 19.0) if r.chance(0.25) else r.range(8.0, 13.0)) - 2.6) * (1.0 - exp(-2.2 * age))
		if x - rad < left + 1.0:
			return
		var a := minf(1.0, age * 16.0) * pow(1.0 - k, 1.25) * 0.68 * Px.smooth(left, left + 40.0, x - rad)
		list.append({"x": x, "y": y - rise + sway, "r": rad, "a": a, "b": Px.clamp(0.95 - k * 0.75 + r.range(-0.08, 0.08)), "w": exp(-age * r.range(3.5, 6.0))}))
	Lib.cloud(p, list, SM, [Px.mix(F[0], SM[0], 0.5), Px.mix(F[1], SM[1], 0.45), Px.mix(F[2], SM[2], 0.35), F[3], F[4], F[6], F[7]], {"dens": 1.3, "lit": 1.5})
	# the smoke right behind the flame glows from inside
	p.glow(NOZZLE - J0 - 6.0, by, 26.0, F[4], 0.24 * fl)

	# embers carried off in the smoke, cooling and winking out
	Lib.beat(t, D, 9, S + 4.0, func(r): return r.range(0.6, 1.1), func(age: float, life: float, r: Px.Rng) -> void:
		var k := 1.0 - age / life
		var wk := Lib.wake(NOZZLE - J0 * 0.6, bob.call(t - age), -r.range(40.0, 120.0), r.range(-40.0, 30.0), age, V, 2.5, -8.0)
		var x: float = wk[0]
		var y: float = wk[1]
		if x < left + 2.0 or (k < 0.3 and Px.rand(fr, r.int_(0, 999)) < 0.5):
			return
		var c: int = F[6] if k > 0.6 else (F[4] if k > 0.3 else F[2])
		p.px(x, y, c)
		p.glow(x, y, 3.0, c, 0.35 * k))

	# tongues of flame torn off the tip of the jet, cooling and shrinking as they fall behind
	Lib.beat(t, D, 30, S + 3.0, func(r): return r.range(0.08, 0.16), func(age: float, life: float, r: Px.Rng) -> void:
		var k := age / life
		var wk := Lib.wake(NOZZLE - J0 * r.range(0.6, 0.9), bob.call(t - age) + r.range(-1.5, 1.5), -r.range(10.0, 50.0), r.range(-12.0, 12.0), age, V, 4.0, -30.0)
		var x: float = wk[0]
		var y: float = wk[1]
		var idx := 7 - floori(pow(k, 0.7) * 4.0)
		var rad := r.range(1.2, 2.2) * (1.0 - k * 0.6)
		p.circle(x, y, rad, F[idx - 2])
		p.circle(x + rad * 0.25, y - rad * 0.1, rad * 0.65, F[idx])
		p.glow(x, y, rad * 2.4 + 2.0, F[idx], 0.2 * (1.0 - k)))

	# sparks shed behind, streaking back and dropping
	Lib.beat(t, D, 30, S + 2.0, func(r): return r.range(0.18, 0.45), func(age: float, life: float, r: Px.Rng) -> void:
		var wk := Lib.wake(NOZZLE - r.range(2.0, J0 * 0.7), bob.call(t - age) + r.range(-1.5, 1.5), -r.range(20.0, 190.0), r.range(-80.0, 50.0), age, V, 2.6, 160.0)
		var x: float = wk[0]
		if x > left + 10.0:
			Lib.spark(p, x, wk[1], wk[2], wk[3], 1.0 - age / life, SP))
	Lib.beat(t, D, 8, S + 6.0, func(r): return r.range(0.5, 0.8), func(age: float, life: float, r: Px.Rng) -> void:
		var wk := Lib.wake(NOZZLE - r.range(4.0, J0 * 0.8), bob.call(t - age) + r.range(-1.0, 1.0), -r.range(10.0, 80.0), r.range(-60.0, 10.0), age, V, 1.8, 170.0)
		var x: float = wk[0]
		if x > left + 10.0:
			Lib.spark(p, x, wk[1], wk[2], wk[3], 1.0 - age / life, SP, 0.5))

	jet(p, F, NOZZLE, by + 0.5, J, wob, fr + S * 31.0)
	p.sprite(SHIP.rows, {"o": OUTLINE, "1": M[1], "2": M[2], "3": M[3], "4": M[4], "5": M[5], "6": M[6], "a": A[0], "b": A[1], "c": A[2], "d": A[3], "e": A[4], "w": WHITE, "h": F[5], "x": F[8]}, SHIP.x0, SHIP.y0 + by)

	# light: a warm pool round the tail that breathes with the jet, the flame's own glow, a white-hot nozzle
	p.glow(NOZZLE - 10.0, by, 60.0, F[4], 0.28 * fl)
	p.glowLine(NOZZLE - 3.0, by + 0.5, NOZZLE - J * 0.9, by + 0.5, 11.0, F[4], 0.2)
	p.glow(NOZZLE - 1.0, by + 0.5, 8.0, F[7], 0.45)
	p.glow(NOZZLE + 3.0, by + 5.0, 12.0, F[4], 0.22 * fl) # the flame lights the tail from below
