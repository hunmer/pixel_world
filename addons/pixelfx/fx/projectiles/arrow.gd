# port-of: src/fx/projectiles/arrow.js@943676edad93d3bea42e4d6f1eb2533e590b7ea2
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Arrow",
	"desc": "An arrow in flight: a steel broadhead catching the light, a wooden shaft, fletching fluttering in the wind, streaks of air peeling off its head and swirling off its feathers.",
	"tags": ["projectile", "arrow", "bow", "medieval", "directional", "loop"],
	"size": [112, 32],
	"origin": [92, 16],
	"duration": 0.6,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#7a1f2c", "#b8323c", "#e8e2d6", "#ffffff"],
		"wood": ["#3a2414", "#6e4422", "#a8723c", "#d8a868"],
		"steel": ["#2e3648", "#5a6680", "#9aa6ba", "#dfe7f2"],
		"wind": "#b8c8e8",
		"seed": 3,
	},
}

# the arrow, nose right, tip at (0, 0): fletching (three poses for the flutter), shaft, binding, broadhead
const HEAD := ["..LL....", "..sLLL..", "bbsSSSSW", "..dDDD..", "..DD...."]
const FLETCH := [
	["AAa.........", ".aAAa.......", "..aaAAa.....", "nkkkkkkkkkkk", "..cCCc......", ".cCCc.......", "CCc........."],
	[".AAa........", "..aAAa......", "..aaAAAa....", "nkkkkkkkkkkk", "..cCCCc.....", "..cCCc......", ".CCc........"],
	["AAAa........", "aAAa........", ".aaAAa......", "nkkkkkkkkkkk", "..ccCc......", "cCCc........", "CCc........."],
]


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var PL := Px.fit(o.palette, 4)
	var W := Px.fit(o.wood, 4)
	var ST := Px.fit(o.steel, 4)
	var wind := Px.hex(o.wind)
	var S: float = o.seed
	var D: float = meta.duration
	var fr := floorf(t * 30.0 + 1e-6)
	var ph := t / D
	var left: float = -meta.origin[0] + 2.0
	var LEN := 36.0

	# streaks of air peeling off the head and the fletching, stretching back and thinning
	Lib.beat(t, D, 9, S, func(r): return r.range(0.14, 0.26), func(age: float, life: float, r: Px.Rng) -> void:
		var k := age / life
		var top := -1.0 if r.chance(0.5) else 1.0
		var from := -3.0 if r.chance(0.6) else -LEN + 6.0
		var x0 := from - age * r.range(160.0, 240.0)
		var len := r.range(8.0, 16.0) * (0.5 + k)
		var y := 0.5 + top * (r.range(3.0, 5.0) + k * r.range(1.0, 2.5))
		if x0 - len < left:
			return
		var c := wind if k < 0.4 else Px.mix(wind, Px.hex("#2a2540"), (k - 0.4) * 1.2)
		p.line(x0, y, x0 - len, y, func(u): return Px.mix(wind, WHITE, 0.5) if (u < 0.25 and k < 0.4) else c, func(u): return 1.0 if u < 0.65 else (1.0 - u) / 0.35))
	# little eddies spinning off the feathers
	Lib.beat(t, D, 6, S + 3.0, func(r): return r.range(0.15, 0.25), func(age: float, life: float, r: Px.Rng) -> void:
		var k := age / life
		var cx := -LEN - 2.0 - age * r.range(100.0, 150.0)
		var cy := 0.5 + r.sign() * r.range(2.0, 4.0)
		var a := age * 30.0 + r.range(0.0, TAU)
		var rr := 1.2 + k * 1.5
		if cx < left + 4.0:
			return
		for i in 4:
			p.dot(cx + cos(a + i * 0.5) * rr, cy + sin(a + i * 0.5) * rr, wind, (1.0 - k) * (1.0 - i * 0.2)))

	# the shaft with a lit top line
	p.line(-LEN + 11.0, 0.0, -7.0, 0.0, W[2])
	var x := -LEN + 14.0
	while x < -8.0:
		p.px(x, 0.0, W[3])
		x += 6.0
	# the fletching flutters through its poses, faster than the frame rate can quite catch
	var pose: Array = FLETCH[floori(Px.rand(fr, S) * 3.0)]
	p.sprite(pose, {"a": PL[2], "A": PL[3], "c": PL[0], "C": PL[1], "k": W[1], "n": W[0]}, -LEN, -3.0)
	# the binding and the broadhead: a lit upper bevel, a shaded lower one, a white point
	p.sprite(HEAD, {"L": ST[3], "s": ST[2], "S": ST[2], "d": ST[0], "D": ST[1], "b": W[0], "W": WHITE}, -7.0, -2.0)
	# a glint runs down the blade now and then
	var g := fmod(ph * 2.0, 1.0)
	if g < 0.25:
		Px.sparkle(p, -5.0 + g * 16.0, -1.0, 1.0 + Px.round(2.0 * sin((g / 0.25) * PI)), WHITE, ST[3], 0.25)
