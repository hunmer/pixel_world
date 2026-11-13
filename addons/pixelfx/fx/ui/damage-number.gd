# port-of: src/fx/ui/damage-number.js@3f026840a40959e48e9ca9a8d1da59734157a1f6
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Damage number",
	"desc": "A red -27 punches out of a hit spark, white for a frame, arcs up, lands with a squash and a little hop, then fades as it lifts away.",
	"tags": ["ui", "damage", "number", "combat", "text", "hit", "one-shot"],
	"size": [76, 68],
	"origin": [30, 52],
	"duration": 1.05,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": ["#1a0508", "#4a0b12", "#8c1420", "#d42a2e", "#ff5a4a", "#ff9a86", "#ffd8cc", "#ffffff"], "text": "-27", "seed": 2},
}

const LAND := -8.0
const FADE := 0.84


var C: Array
var R: Px.Rng
var word: Dictionary
var ps: Px.Particles
var lights: Px.Lights
var n: Dictionary
var spikes: Array
var t := 0.0
var hit := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	word = Lib.spell(o.text)
	ps = Px.Particles.new({"rng": R, "sparks": [C[7], C[6], C[4], C[2]]})
	lights = Px.Lights.new()
	# the number is a little body: thrown up and out, it lands, hops once and settles
	n = {"x": 0.0, "y": LAND, "vx": 34.0, "vy": -175.0, "sq": 0.0, "hops": 0}
	spikes = Px.arr(9, func(i): return [(i / 9.0) * TAU + R.range(-0.2, 0.2), R.range(8.0, 14.0)])


func update(dt: float) -> void:
	t += dt
	if not hit:
		hit = true
		lights.add(0.0, -4.0, 30.0, C[5], 0.7, 0.25)
		lights.add(0.0, -4.0, 14.0, WHITE, 0.6, 0.08)
		for i in 9:
			var an := R.range(-PI * 0.95, -0.05) + (PI * 0.08 if i % 2 else 0.0)
			var sp := R.range(90.0, 200.0)
			ps.spawn(P.SPARK, 0.0, -4.0, cos(an) * sp, sin(an) * sp, R.range(0.1, 0.25))
	if n.hops < 2:
		n.vy += 900.0 * dt
		n.vx -= n.vx * 2.0 * dt
		n.x += n.vx * dt
		n.y += n.vy * dt
		if n.y >= LAND and n.vy > 0.0:
			n.y = LAND
			n.sq = 1.0
			n.hops += 1
			n.vy = -n.vy * 0.36 if n.hops < 2 else 0.0
			if n.hops == 1:
				for s in [-1.0, 1.0]:
					ps.spawn(P.STAR, n.x + s * 14.0, LAND + R.range(-2.0, 1.0), s * R.range(15.0, 35.0), -R.range(5.0, 20.0), R.range(0.2, 0.35), C[6], R.range(0.5, 1.2))
	n.sq = maxf(0.0, n.sq - dt / 0.09)
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	# the hit: two frames of a spiky white-hot star, then a glint and a ring where the blow landed
	if t < 0.07:
		var big := t < 0.035
		for i in spikes.size():
			var an: float = spikes[i][0]
			var L: float = spikes[i][1]
			var l := L * (1.0 if big else 1.3)
			var ca := cos(an)
			var sa := sin(an)
			if big:
				# a fat spike: a red rim either side of a white-hot core that narrows to the tip
				p.line(-sa, -4.0 + ca, ca * l * 0.7 - sa, -4.0 + sa * l * 0.7 + ca, C[4])
				p.line(sa, -4.0 - ca, ca * l * 0.7 + sa, -4.0 + sa * l * 0.7 - ca, C[4])
			p.line(ca * (0.0 if big else l * 0.45), -4.0 + sa * (0.0 if big else l * 0.45), ca * l, -4.0 + sa * l, WHITE if big else (C[6] if i % 2 else C[5]))
		if big:
			p.circle(0.0, -4.0, 3.2, WHITE)
	elif t < 0.16:
		Px.sparkle(p, 0.0, -4.0, 5.0 * (1.0 - (t - 0.07) / 0.09), WHITE, C[5], 0.6)
	var rk := t / 0.22
	if rk < 1.0:
		p.ring(0.0, -4.0, 3.0 + 10.0 * Px.Ease.outCubic(rk), maxf(1.0, 2.0 * (1.0 - rk)), WHITE if rk < 0.4 else C[5], 1.2 - rk)
	ps.draw(p)
	# the number: punches out big and white, springs to size, squashes as it lands, then lifts and fades
	var out := Px.seg(t, FADE, meta.duration - 0.04)
	if out < 1.0:
		var s := 2.0 + 1.4 * exp(-t * 22.0) * cos(t * 30.0)
		var sx := s
		var sy := s
		if n.sq > 0.0:
			sx = s * (1.0 + 0.18 * n.sq)
			sy = s * (1.0 - 0.2 * n.sq)
		elif n.hops < 2 and absf(n.vy) > 120.0:
			sx = s * 0.92
			sy = s * 1.1
		var W: float = word.w * sx
		var H := 7.0 * sy
		var x0: float = n.x - W / 2.0
		var y0: float = n.y - H - 6.0 * Px.Ease.inQuad(out)
		var flash := 1.0 if t < 0.035 else (0.4 if t < 0.07 else 0.0)
		var items := []
		for L: Dictionary in word.letters:
			if L.g != null:
				items.append({"g": L.g, "x": x0 + L.x * sx, "y": y0, "sx": sx, "sy": sy, "flash": flash, "a": 1.0 - out})
		Lib.drawWord(p, items, {"fill": [C[3], C[3], C[4], C[5]], "edge": C[6], "under": C[2], "outline": C[0], "shadow": Px.scale(C[0], 0.5)})
		p.glow(n.x, y0 + H / 2.0, 18.0, C[4], 0.3 * (1.0 - out) + (0.4 * (1.0 - t / 0.1) if t < 0.1 else 0.0))
	lights.draw(p)
