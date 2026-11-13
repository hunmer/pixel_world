# port-of: src/fx/explosions/cartoon-pow.js@69d44c838179847dea45c527d62156cbc682fcbd
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Cartoon POW",
	"desc": "A comic-book hit: a jagged two-tone burst star slams in with a shake and boiling edges, POW! drops in letter by letter, action lines fly, then it all snaps away.",
	"tags": ["cartoon", "comic", "pow", "hit", "impact", "text", "one-shot"],
	"size": [184, 144],
	"origin": [92, 72],
	"duration": 1.05,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": ["#1a0e14", "#6e1a12", "#c8361a", "#f47a24", "#ffc23c", "#fff07a", "#ffffff"], "text": "POW!", "seed": 5},
}

const N := 14
const IN := 0.05
const GO := 0.66
const END := 0.8


var o: Dictionary
var C: Array
var R: Px.Rng
var INK: int
var ps: Px.Particles
var spikes: Array
var lines: Array
var t := 0.0
var popped := false
var burst := false


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 7)
	R = Px.Rng.new(o.seed)
	INK = C[0]
	ps = Px.Particles.new({"rng": R, "sparks": [C[6], C[5], C[4], C[3]]})
	# the star's spikes: long and short in turn, each its own length, boiling a little every few frames
	spikes = []
	for i in N * 2:
		spikes.append({"r": R.range(0.5, 0.6) if i % 2 else R.range(0.85, 1.05), "j": R.next() * 100.0})
	lines = []
	for i in 16:
		lines.append({"a": ((i + R.range(0.2, 0.8)) / 16.0) * TAU, "r": R.range(0.92, 1.08), "L": R.range(10.0, 17.0), "t0": R.range(0.0, 0.06)})


func update(dt: float) -> void:
	t += dt
	if not burst and t >= IN:
		burst = true
		for i in 22:
			var a := R.range(0.0, TAU)
			var sp := R.range(180.0, 360.0)
			ps.spawn(P.SPARK, cos(a) * 14.0, sin(a) * 10.0, cos(a) * sp, sin(a) * sp, R.range(0.12, 0.3))
	# it snaps away into a scatter of little stars
	if not popped and t >= GO:
		popped = true
		for i in 14:
			var a := R.range(0.0, TAU)
			var sp := R.range(60.0, 150.0)
			ps.spawn(P.STAR, cos(a) * 26.0, sin(a) * 18.0, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.42), R.pick([C[6], C[5], C[4]]), R.range(1.2, 2.4))
	ps.update(dt)
	Lib.cull(ps, -meta.origin[0] + 3, -meta.origin[1] + 3, meta.size[0] - meta.origin[0] - 3, meta.size[1] - meta.origin[1] - 3)


func draw(p: Px.Painter) -> void:
	var k := Px.clamp(t / IN)
	# the slam: it punches in past full size, shudders and settles; then it squeezes and snaps away
	var s := (0.25 + 0.95 * Px.Ease.outCubic(k)) if t < IN else ((1.0 + 0.18 * exp(-(t - IN) * 18.0) * cos((t - IN) * 40.0)) if t < GO else 1.0 - Px.Ease.inBack(Px.clamp((t - GO) / (END - GO)), 2.0))
	var shake := (1.0 - t / 0.3) * 2.2 if t < 0.3 else 0.0
	var sx := Px.round(sin(t * 97.0) * shake)
	var sy := Px.round(cos(t * 83.0) * shake)
	if s > 0.02:
		# the burst star, in one pass: its edge at each angle runs straight from spike tip to notch. An inked edge, a
		# yellow body with halftone dots on its shaded side, an inked orange heart and a yellow core
		var boil := floorf(t * 12.0)
		var outer := 50.0 * s
		var rot := -0.1 + ((t - GO) * 3.0 if t > GO else 0.0)
		var M := N * 2
		var rad := []
		for i in spikes.size():
			rad.append(spikes[i].r * (1.0 + (Px.rand(i, boil, 7) - 0.5) * 0.08))
		p.shade(sx - outer - 4.0, sy - outer - 4.0, sx + outer + 4.0, sy + outer + 4.0, func(x: float, y: float):
			var dx := x - sx
			var dy := (y - sy) / 0.82
			var d := Px.hypot(dx, dy)
			var u := fmod(fmod((atan2(dy, dx) - rot) / TAU, 1.0) + 1.0, 1.0) * M
			var i := floori(u) % M
			var f := u - floorf(u)
			var r: float = rad[i] + (rad[(i + 1) % M] - rad[i]) * f
			var e := d / r
			if e > outer + 2.5:
				return null
			if e > outer:
				return INK
			if e > outer * 0.66 + 2.0:
				return C[4] if (dx * 0.6 + dy * 0.8 > outer * 0.25 and (floori(x) + floori(y) * 2) % 4 == 0 and floori(y) % 2 == 0) else C[5]
			if e > outer * 0.66:
				return INK
			return C[3] if e > outer * 0.44 else C[4])
		p.glow(sx, sy, outer * 1.3, C[5], 0.3 * minf(1.0, s))
	# action lines flying out, and a ring of impact
	for q in lines:
		var u: float = (t - IN - q.t0) / 0.32
		if u <= 0.0 or u >= 1.0:
			continue
		var r0: float = (46.0 + 22.0 * Px.Ease.outCubic(u)) * q.r
		var L: float = q.L * 0.7 * (1.0 - u)
		var ca: float = cos(q.a)
		var sa: float = sin(q.a) * 0.82
		p.line(ca * r0, sa * r0, ca * (r0 + L), sa * (r0 + L), func(v: float): return WHITE if v < 0.5 else C[5])
	var ru := (t - IN) / 0.24
	if ru > 0.0 and ru < 1.0:
		p.ring(0.0, 0.0, 30.0 + 34.0 * Px.Ease.outCubic(ru), maxf(1.0, 2.5 * (1.0 - ru)), WHITE if ru < 0.4 else C[5], 1.1 - ru)
	# the word: letters dropping in one after another, inked, with a deep red extrusion, then a squash as it goes
	var word := str(o.text if o.get("text") != null else "POW!")
	var scale := 3.0
	var widths := []
	for ch in word:
		widths.append(p.measure(ch, {"font": "big", "scale": scale})[0])
	var x: float = -(widths.reduce(func(a, w): return a + w + scale, -scale)) / 2.0
	for i in word.length():
		var ch := word[i]
		var u := (t - IN - 0.04 - i * 0.05) / 0.12
		var away := Px.clamp((t - GO) / (END - GO - 0.04))
		if u > 0.0 and away < 1.0:
			var drop := (1.0 - Px.Ease.outBack(Px.clamp(u), 2.4)) * -14.0
			var y := Px.round(-11.0 + drop - i * 1.5 + sy + away * 6.0)
			var lx := Px.round(x + sx)
			var a := 1.0 - away
			# a thick ink edge, a deep red extrusion, a white face going warm toward its foot
			var d := 4
			while d >= 1:
				p.text(ch, lx + d, y + d, INK if d >= 3 else C[1], {"font": "big", "scale": scale, "a": a, "outline": INK if d == 4 else null})
				d -= 1
			for oo in [[-2, 0], [2, 0], [0, -2], [0, 2], [-1, -1], [1, -1], [-1, 1], [1, 1]]:
				p.text(ch, lx + oo[0], y + oo[1], INK, {"font": "big", "scale": scale, "a": a})
			p.text(ch, lx, y, func(gx, gy): return C[6] if gy < 4 else (C[5] if gy < 6 else C[4]), {"font": "big", "scale": scale, "a": a})
		x += widths[i] + scale
	ps.draw(p)
	if t > IN and t < IN + 0.12:
		Px.sparkle(p, sx + 34.0, sy - 22.0, 6.0 * (1.0 - (t - IN) / 0.12), C[6], C[5], 0.6)
