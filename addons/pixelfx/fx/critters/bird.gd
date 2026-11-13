# port-of: src/fx/critters/bird.js@e07fc4063a8a120d0226f0dd9dbce0327ec33d7e
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Bird",
	"desc": "A songbird flies in place: bursts of wingbeats that lift its body on each downstroke, a glide on spread wings, its tail fanning, a loose feather drifting away.",
	"tags": ["critter", "bird", "flying", "animal", "loop"],
	"size": [112, 80],
	"origin": [56, 40],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#0a0e1e", "#18244a", "#24407a", "#3466aa", "#5a94d4", "#9cc8f0", "#eaf6ff"],
		"breast": ["#4a1a0e", "#a8441c", "#e8783a", "#ffb070"],
		"seed": 1,
	},
}

static var D: float = meta.duration
static var GRID := Lib.Grid.new(-26, -26, 52, 46)
static var BEAK := Px.hex("#f0b030")
static var BEAKD := Px.hex("#a86a18")
# the near wing's key poses, points from the shoulder: leading edge to the tip, then the trailing feathers back
const POSE := {
	"up": [[0.0, 0.0], [-1.0, -8.0], [-5.0, -15.0], [-8.0, -13.5], [-10.5, -10.5], [-11.0, -7.0], [-9.0, -3.0], [-6.0, 1.0]],
	"mid": [[0.0, 0.0], [-3.0, -2.5], [-9.0, -2.5], [-10.5, -0.5], [-10.0, 1.2], [-8.5, 2.0], [-7.0, 2.2], [-5.0, 2.0]],
	"down": [[0.0, 0.0], [-1.0, 6.0], [-3.5, 12.0], [-6.0, 11.0], [-7.5, 8.5], [-8.0, 6.0], [-7.0, 3.0], [-5.0, 2.0]],
	"fold": [[0.0, 0.0], [-3.0, -4.0], [-10.0, -5.5], [-11.0, -4.0], [-10.0, -2.5], [-8.5, -1.0], [-7.0, 0.5], [-5.0, 1.5]],
	"glide": [[0.0, 0.0], [-2.0, -5.0], [-7.0, -10.0], [-10.0, -9.0], [-12.0, -6.5], [-11.5, -3.5], [-9.0, -1.0], [-6.0, 1.0]],
}


static func mixPose(a: Array, b: Array, u: float) -> Array:
	var out := []
	for i in a.size():
		out.append([Px.lerp(a[i][0], b[i][0], u), Px.lerp(a[i][1], b[i][1], u)])
	return out


# flapping until GLIDE, then a glide on spread wings
const FLAPS := 4.0
const GLIDE := 1.5


static func wing(t: float) -> Dictionary:
	t = Px.wrap(t, D)
	if t < GLIDE:
		var u := fmod((t / GLIDE) * FLAPS, 1.0)
		# a quick downstroke through the stretched-out middle, a slower upstroke folded close
		if u < 0.4:
			var k := Px.Ease.inOutSine(u / 0.4)
			return {"pts": mixPose(POSE.up, POSE.mid, k * 2.0) if k < 0.5 else mixPose(POSE.mid, POSE.down, k * 2.0 - 1.0), "down": true, "u": u}
		var k := Px.Ease.inOutSine((u - 0.4) / 0.6)
		return {"pts": mixPose(POSE.down, POSE.fold, k * 2.0) if k < 0.5 else mixPose(POSE.fold, POSE.up, k * 2.0 - 1.0), "down": false, "u": u}
	var g := (t - GLIDE) / (D - GLIDE)
	var into := Px.smooth(0.0, 0.15, g)
	var out := Px.smooth(0.85, 1.0, g)
	return {"pts": mixPose(mixPose(POSE.up, POSE.glide, into), POSE.up, out), "down": false, "u": 0.0}


# the body rises as the wings push down, and sinks a touch through the glide
static func lift(t: float) -> float:
	t = Px.wrap(t, D)
	var y := 0.0
	for k in 6:
		if wing(t - k * 0.02).down:
			y -= 0.45
	if t >= GLIDE:
		y += 2.2 * sin(PI * ((t - GLIDE) / (D - GLIDE)))
	return y + 1.2


const SH := [1.0, -2.0]


static func wingPts(w: Dictionary, far: bool) -> Array:
	var out := []
	for q in w.pts:
		var x: float = q[0]
		var y: float = q[1]
		out.append([SH[0] + x - (1.0 if far else 0.0), SH[1] + y * (0.85 if far else 1.0) - (1.0 if far else 0.0)])
	return out


static func bird(g: Lib.Grid, C: Array, Br: Array, t: float, w: Dictionary) -> void:
	g.clear()
	# the far wing, behind the body and in shadow
	g.poly(wingPts(w, true), C[1])
	# the tail: three feathers fanning as it brakes and lifts
	var tf := 0.25 + 0.35 * sin((t / D) * TAU * 2.0)
	for i in 3:
		var a := PI + (i - 1) * tf * 0.5 + 0.1
		var L := 9.0 - absf(i - 1)
		g.poly([[-7.0, -2.4], [-7.0 + cos(a) * L, -1.0 + sin(a) * L - 1.2], [-7.0 + cos(a) * L, -1.0 + sin(a) * L + 1.2], [-7.0, 0.6]], C[3] if i == 0 else C[2])
	# body and head: a blue back lit from above, a rust breast, a pale belly
	var inBody := func(x: float, y: float) -> bool:
		return ((x + 1.0) / 8.5) ** 2 + (y / 5.2) ** 2 <= 1.0 or (x - 6.5) ** 2 + (y + 3.0) ** 2 <= 4.6 ** 2
	g.shade(-10.0, -9.0, 12.0, 6.0, func(x, y):
		if not inBody.call(x, y):
			return 0
		var top: bool = not inBody.call(x, y - 2.2)
		var under: bool = not inBody.call(x + 0.5, y + 1.6)
		if y > -0.5 and x > -2.5:
			return Br[1] if under else (Br[3] if (x > 3.0 and y < 2.0) else Br[2])
		if y > 1.5:
			return C[4] if under else C[5]
		return (C[5] if x > 2.0 else C[4]) if top else (C[4] if (y < -3.5 and x > 3.0) else C[3]))
	# beak, eye with a glint, a dark cap stripe
	g.poly([[10.5, -4.5], [14.5, -3.0], [10.5, -2.0]], func(x, y): return BEAK if y < -3.0 else BEAKD)
	g.setc(8, -4, C[0])
	g.setc(8, -5, C[6])
	g.setc(9, -4, C[0])
	g.line(5.0, -7.0, 9.0, -6.5, C[2])
	# the near wing: lit along its leading edge, the flight feathers splayed at the tips
	var wp := wingPts(w, false)
	var edge := func(x: float, y: float) -> float:
		var m := INF
		for i in range(1, 3):
			var ax: float = wp[i - 1][0]
			var ay: float = wp[i - 1][1]
			var bx: float = wp[i][0]
			var by: float = wp[i][1]
			var dx := bx - ax
			var dy := by - ay
			var L2 := dx * dx + dy * dy
			if not L2:
				L2 = 1.0
			var u := Px.clamp(((x - ax) * dx + (y - ay) * dy) / L2)
			m = minf(m, Px.hypot(ax + dx * u - x, ay + dy * u - y))
		return m
	g.poly(wp, func(x, y):
		var d: float = edge.call(x, y)
		return C[5] if d < 1.2 else (C[4] if d < 3.0 else C[3]))
	# the flight feathers: dark lines splaying from the wrist to the trailing edge
	for i in range(3, 7):
		g.line(wp[1][0], wp[1][1], Px.lerp(wp[1][0], wp[i][0], 0.92), Px.lerp(wp[1][1], wp[i][1], 0.92), C[2])
	g.outline(C[0])


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var Br := Px.fit(o.breast, 4)
	var w := wing(t)
	var y := lift(t)
	var g := GRID
	# on the downstroke, a see-through echo of the wing a moment before smears the beat
	if w.down and w.u > 0.1:
		var s := t - 0.05
		var ws := wing(s)
		g.clear()
		g.poly(wingPts(ws, false), C[6])
		g.a.fill(0.42)
		g.draw(p, 1.0, 0.0, Px.round(lift(s)))
	bird(g, C, Br, t, w)
	g.draw(p, 1.0, 0.0, Px.round(y))
	# a loose feather drifts off and rocks down out of sight
	var fa := Px.wrap(t - 0.45, D)
	if fa < 1.8:
		var fx := -6.0 - 14.0 * fa - 3.0 * sin(fa * 5.0)
		var fy := 4.0 + 9.0 * fa + 1.5 * cos(fa * 5.0) * fa
		var rock := sin(fa * 5.0) * 0.8
		var a := minf(1.0, (1.8 - fa) * 2.0)
		for i in range(-2, 3):
			p.dot(fx + i * cos(rock), fy + i * sin(rock) * 0.8, C[5] if i < 0 else C[4], a)
		p.dot(fx + 2.6 * cos(rock), fy + 2.6 * sin(rock) * 0.8, C[3], a)
	# a little moonlight on its back
	p.glow(2.0, y - 6.0, 16.0, C[5], 0.12)
