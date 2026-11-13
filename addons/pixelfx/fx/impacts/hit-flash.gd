# port-of: src/fx/impacts/hit-flash.js@60531d91ee66d5bafa9d0850a62c7244fde7628f
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Hit flash",
	"desc": "The character takes damage: a white frame, then their own colors flushed red and blinking white, cooling off, while comic hit lines jab in at them.",
	"tags": ["impact", "hit", "damage", "hurt", "flash", "blink", "actor", "comic", "one-shot"],
	"size": [80, 64],
	"origin": [40, 54],
	"duration": 0.5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#14040a", "#3a0a14", "#6a101c", "#a01824", "#d42a30", "#ff5a50", "#ff9a8a"], "lines": 7, "side": 1, "seed": 17},
}

static var BLOWN := {"x": -5, "crouch": 4, "lean": -5, "hx": -1, "fx": 8, "fy": -33, "bx": -11, "by": -27, "ffx": 9, "ffy": -7, "fbx": -6}
static var act := {
	"onBody": true,
	"poses": [
		[-0.26, Px.merge(Px.READY, {"x": 0})],
		[0, BLOWN, "snap"],
		[0.16, Px.merge(BLOWN, {"x": -8, "crouch": 5})],
		[0.42, Px.merge(BLOWN, {"x": -8, "crouch": 5, "lean": -2, "fx": 9, "fy": -22, "bx": 6, "by": -20, "ffy": -4})],
		[0.86, Px.merge(Px.READY, {"x": 0})],
	],
	"hits": [{"t": 0, "stop": 0.07, "shake": 0.14, "amp": 2}],
}

# the beats, by frame at 30 fps: white, white, red, red, white rim, red cooling off
const BEATS := [[0.025, "white"], [0.058, "white2"], [0.125, "red"], [0.158, "rim"], [0.36, "cool"]]


var C: Array
var R: Px.Rng
var A: Dictionary
var M: Dictionary
var PX: PackedInt32Array
var S: float
var cx: float
var cy: float
var hx: float
var hy: float
var lights: Px.Lights
var reds := PackedInt32Array()
var tints := PackedInt32Array()
var lines: Array
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	R = Px.Rng.new(o.seed)
	A = o.actor
	M = A.mask
	PX = A.pixels
	S = o.side
	cx = A.chest[0]
	cy = A.chest[1]
	hx = cx + S * 12.0 # where the blow lands: the character's front, chest high
	hy = cy - 5.0
	lights = Px.Lights.new()
	lights.add(hx, hy, 34.0, WHITE, 0.6, 0.1)
	lights.add(cx, cy, 30.0, C[4], 0.5, 0.35)
	# the hurt colors: each pixel's own light and shade carried into the red ramp
	reds.resize(PX.size())
	tints.resize(PX.size())
	for i in PX.size():
		if not PX[i]:
			continue
		var l := Px.luma(PX[i] | 0xff000000)
		reds[i] = C[int(Px.clamp(Px.round(2.0 + l * 5.0), 2.0, 6.0))]
		tints[i] = Px.mix(PX[i] | 0xff000000, C[4], 0.55)
	# hit lines all round the top and sides, jabbing in at the body
	var n: float = o.lines
	lines = Px.arr(n, func(i: int):
		var a := -PI - 0.3 + ((i + R.range(0.25, 0.75)) / n) * (PI + 0.6)
		return {"a": a, "d": R.range(15.0, 19.0), "len": R.range(6.0, 9.0), "t0": R.range(0.0, 0.04)})


func beat() -> Variant:
	for bt: Array in BEATS:
		if t < bt[0]:
			return bt[1]
	return null


func body(p: Px.Painter, color: Callable) -> void:
	var mw: int = M.w
	p.mask(M, A.x, A.y, func(mx, my): return color.call(my * mw + mx))


func update(dt: float) -> void:
	t += dt
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	var b: Variant = beat()
	if b == "white" or b == "white2":
		body(p, func(_i): return WHITE)
		p.outline(M, A.x, A.y, C[6] if b == "white" else C[5])
	elif b == "red":
		body(p, func(i): return reds[i])
		p.outline(M, A.x, A.y, C[5])
	elif b == "rim":
		p.outline(M, A.x, A.y, WHITE)
	elif b == "cool":
		var k := 1.0 - (t - 0.158) / (0.36 - 0.158)
		body(p, func(i): return Px.mix(PX[i] | 0xff000000, tints[i], k))
		if k > 0.5:
			p.outline(M, A.x, A.y, C[4], (k - 0.5) * 2.0)
	# the blow: a small hot burst on the side it came from
	if t < 0.07:
		var big := 1.0 if t < 0.035 else 1.3
		var k := 0.0 if t < 0.035 else 1.0
		for i in 8:
			var a := (i / 8.0) * TAU + 0.2
			var L := (4.0 if i % 2 else 9.0) * big
			p.line(hx + cos(a) * L * 0.45 * k, hy + sin(a) * L * 0.45 * k, hx + cos(a) * L, hy + sin(a) * L, func(u): return WHITE if (u < 0.45 and not k) else (C[6] if u < 0.75 else C[4]))
		if not k:
			for dd: Array in [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]:
				p.px(hx + dd[0], hy + dd[1], WHITE)
		p.glow(hx, hy, 14.0, C[6], 0.5 * (1.0 - t / 0.07))
	# comic hit lines jab in toward the body, then are gone
	for l: Dictionary in lines:
		var u: float = (t - l.t0) / 0.16
		if u < 0.0 or u >= 1.0:
			continue
		var d0: float = l.d - 6.0 * Px.Ease.outCubic(u)
		var L: float = l.len * (1.0 - u)
		var ca := cos(l.a)
		var sa: float = sin(l.a) * 1.15
		if L < 1.0:
			continue
		# a wedge, its point at the body and its fat end out, white with a red edge
		var w := (2.8 - 1.6 * u) / 2.0
		var nx := -sa * w
		var ny := ca * w
		var ex := cx + ca * (d0 + L)
		var ey := cy + sa * (d0 + L)
		var px0 := cx + ca * d0
		var py0 := cy + sa * d0
		p.poly([[px0 - ca, py0 - sa], [ex + nx * 1.5 + ca, ey + ny * 1.5 + sa], [ex - nx * 1.5 + ca, ey - ny * 1.5 + sa]], C[3])
		p.poly([[px0, py0], [ex + nx, ey + ny], [ex - nx, ey - ny]], WHITE if u < 0.5 else C[6])
	var k := exp(-t / 0.08)
	if k > 0.02:
		p.glow(cx, cy, 26.0, WHITE if (b == "white" or b == "white2") else C[5], 0.35 * k)
	lights.draw(p)
