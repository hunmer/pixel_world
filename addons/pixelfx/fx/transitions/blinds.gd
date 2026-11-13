# The dust drifting in the light and the light squeezing through follow Sprite Fusion's open-source holy light
# (https://www.spritefusion.com/pixel-art-vfx/holy-light), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/blinds.js@44a8b6d24b636bf1ace8fd91b584a2987aa41de7
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE
const W := Lib.W
const H := Lib.H

static var meta := Lib.screenMeta({
	"name": "Blinds",
	"desc": "Slats catch the light edge-on, then tilt shut top to bottom, lit rims glinting as warm light squeezes through the closing gaps with dust in it; then they tilt open and fade.",
	"tags": ["blinds", "slats", "light", "wipe"],
	"duration": 2.0,
	"options": {"palette": ["#1a120c", "#33241a", "#5a4030", "#8a6848", "#c09a6a", "#e8cc98", "#fff0cc", "#ffffff"], "seed": 1},
})

const N := 12
const SH := H / float(N)
const SHUT0 := 0.08
const OPEN0 := 1.02
const STEP := 0.038
const TURN := 0.42
const OSTEP := 0.03
const OTURN := 0.4
const FADE0 := 1.72
const FADE1 := 1.94
const NB := [[1, 0], [-1, 0], [0, 1], [0, -1]]


# how far slat i has turned: 0 edge-on, π/2 flat and shut (a little past while it settles)
static func angle(i: int, t: float) -> float:
	if t < OPEN0:
		return (PI / 2.0) * Px.Ease.outBack(Px.clamp((t - SHUT0 - i * STEP) / TURN), 1.6)
	return (PI / 2.0) * (1.0 - Px.Ease.inOutCubic(Px.clamp((t - OPEN0 - i * OSTEP) / OTURN)))


var C: Array
var ink: int
var R: Px.Rng
var ps: Px.Particles
var t := 0.0
var end := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	ink = Px.hex(o.color)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [WHITE, C[6], C[5], C[4]]})
	t = 0.0
	end = meta.duration - 0.05


func update(dt: float) -> void:
	t += dt
	# dust drifts in the light coming through
	if t < FADE0 and R.chance(0.8):
		var i := R.int_(0, N - 1)
		var th := angle(i, t)
		if th > 0.2 and th < 1.45:
			ps.spawn(P.EMBER, R.range(0, W), (i + 1) * SH + R.range(-2, 2), R.range(-8, 8), -R.range(2, 8), minf(R.range(0.5, 1), end - t), 0, 1)
	ps.update(dt)


func draw(p0: Px.Painter) -> void:
	var p := Lib.clipTo(p0)
	var open := PackedByteArray()
	open.resize(H)
	open.fill(1)
	for i in N:
		var h := maxf(1.0, (SH + 1.0) * absf(sin(angle(i, t))))
		var yc := (i + 0.5) * SH
		for y in range(int(maxf(0.0, ceilf(yc - h / 2.0 - 0.5))), int(minf(H - 1.0, floorf(yc + h / 2.0 - 0.5))) + 1):
			open[y] = 0
	# the dust is behind the slats: it only shows (and only shines) in the gaps
	for q: Dictionary in ps.list:
		var y := floori(q.y)
		var k: float = q.life / q.max
		if q.delay > 0.0 or y < 0 or y >= H or not open[y] or q.x < 0.0 or q.x >= W:
			continue
		# some catch the light as little twinkling crosses
		var tw: bool = fmod(q.seed, 1.0) < 0.3 and sin(t * 14.0 + q.seed) > 0.0
		p0.px(q.x, y, WHITE if tw or k > 0.5 else C[5])
		if tw:
			for dd in NB:
				var yy: int = y + dd[1]
				if yy >= 0 and yy < H and open[yy]:
					p.px(q.x + dd[0], yy, C[6])
		p0.light(q.x, y, C[6], (0.7 if tw else 0.4) * k)
	var fade := 1.0 - Px.clamp((t - FADE0) / (FADE1 - FADE0))
	var appear := Px.clamp(t / SHUT0)
	for i in N:
		var th := angle(i, t)
		var s := sin(th)
		var c := cos(th)
		var yc := (i + 0.5) * SH
		var h := maxf(1.0, (SH + 1.0) * absf(s))
		var y0 := int(maxf(0.0, ceilf(yc - h / 2.0 - 0.5)))
		var y1 := int(minf(H - 1.0, floorf(yc + h / 2.0 - 0.5)))
		var under := th > PI / 2.0  # turned past flat: the shadowed underside shows
		# edge-on, the slat is just its lit edge: it brightens in at the start and fades out at the end
		if h < 2.5:
			var k := minf(appear, fade)
			if k <= 0.0:
				continue
			var yy := Px.round(yc - 0.5)
			Lib.rect(p0, 0.0, yy, W, 1.0, C[6] if k > 0.66 else (C[4] if k > 0.33 else C[2]))
			if h >= 1.5 and yy + 1.0 < H:
				Lib.rect(p0, 0.0, yy + 1.0, W, 1.0, C[3] if k > 0.5 else C[1])
			var x := 0
			while x < W:
				p0.light(x, yy, C[5], 0.18 * k)
				x += 2
			continue
		# tilted: a lit top rim, a sheen, a face that darkens as it turns flat to us, a shadowed underside
		var lit := 0.0 if under else c
		for y in range(y0, y1 + 1):
			# the face is lit from above: brightest just under the rim, falling away down it
			var r := y - y0
			var last := y == y1
			var v := r / float(maxi(1, y1 - y0))
			var f := lit * (1.0 - v * 0.8)
			var col: int
			if r == 0:
				col = WHITE if lit > 0.55 else (C[6] if lit > 0.3 else (C[4] if lit > 0.12 else ink))
			elif r == 1:
				col = C[5] if lit > 0.45 else (C[3] if lit > 0.2 else ink)
			elif last:
				col = ink
			else:
				col = C[3] if f > 0.55 else (C[2] if f > 0.35 else (C[1] if f > 0.15 else ink))
			Lib.rect(p0, 0.0, y, W, 1.0, col)
			if r == 0 and lit > 0.12:
				var x := 0
				while x < W:
					p0.light(x, y, C[5], 0.35 * lit)
					x += 2
		# light squeezes through the gap under the slat, brighter as the gap narrows
		var gap := SH - h
		if gap > 0.5 and th > 0.12 and not under:
			var k := (0.2 + 0.45 * (1.0 - gap / SH) ** 1.5) * minf(1.0, th / 0.4)
			var gy := y1 + 1
			for y in range(gy, int(minf(H, gy + ceilf(gap)))):
				var v := (y - gy + 0.5) / gap
				var kk := k * (1.0 - absf(v - 0.5) * 1.2)
				if kk > 0.01:
					for x in W:
						p0.light(x, y, C[6], kk)
						p0.light(x, y, C[4], kk * 0.5)
		# a glint runs along the lit rim as the slat turns
		var u := Px.clamp((t - SHUT0 - i * STEP) / TURN) if t < OPEN0 else Px.clamp((t - OPEN0 - i * OSTEP) / OTURN)
		if lit > 0.3 and u > 0.05 and u < 0.95:
			Lib.glint(p, W * (u if t < OPEN0 else 1.0 - u), y0, 6.0 * sin(PI * u), u * 3.0, C[6], C[5])
