# port-of: src/fx/impacts/impact-frame.js@4cd616d4d3cc442da4ce3cf3c591ca6567e83cb7
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")

static var meta := {
	"name": "Impact frame",
	"desc": "An anime impact: two frames of white with black burst lines rushing at the hit, two frames inverted, then the lines pull out past the edges and vanish.",
	"tags": ["impact", "hit", "anime", "manga", "flash", "speed-lines", "screen", "one-shot"],
	"size": [320, 180],
	"origin": [160, 90],
	"duration": 0.3,
	"loop": false,
	"fps": 30,
	"bg": "black",
	"options": {"palette": ["#000000", "#ffffff"], "lines": 64, "seed": 19},
}

const FRAME := 1.0 / 30.0 # the beats are whole frames: 2 white, 2 inverted, 4 pulling out


# burst lines: wedges aimed at the hit from past the edges, each its own width and reach, in angle order
static func burst(R: Px.Rng, n: float) -> Array:
	return Px.arr(n, func(i: int):
		var thick := R.chance(0.18)
		return {"a": ((i + R.range(0.1, 0.9)) / n) * TAU, "inner": R.range(30.0, 48.0) if thick else R.range(18.0, 70.0), "w": R.range(5.0, 8.0) if thick else R.range(1.2, 3.6)})


# the jagged burst at the middle: a spiky star whose points shift every frame
static func spikes(a: float, ph: float) -> float:
	return 10.0 + 6.0 * absf(sin(a * 5.0 + ph)) + 4.0 * absf(sin(a * 11.0 + ph * 2.7)) + 2.0 * sin(a * 23.0 + ph)


var C: Array
var R: Px.Rng
var INK: int
var PAPER: int
var W: int
var H: int
var x0: int
var y0: int
var masks: Array
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 3)
	R = Px.Rng.new(o.seed)
	INK = C[0]
	PAPER = C[2]
	W = meta.size[0]
	H = meta.size[1]
	var OX: int = meta.origin[0]
	var OY: int = meta.origin[1]
	x0 = -OX
	y0 = -OY
	var sets := [burst(R, o.lines), burst(R, o.lines)]
	var jit := [[Px.round(R.range(-2.0, 2.0)), Px.round(R.range(-1.0, 1.0))], [Px.round(R.range(-2.0, 2.0)), Px.round(R.range(-1.0, 1.0))]]
	var ph := [R.range(0.0, TAU), R.range(0.0, TAU), R.range(0.0, TAU), R.range(0.0, TAU)]
	# every frame is fixed, so work each one out once: which pixels are ink (1) or paper (2), 0 for nothing
	masks = []
	for f in 8:
		var m := PackedByteArray()
		m.resize(W * H)
		var set_: Array = sets[f % 2]
		var n := set_.size()
		var jx: float = jit[f % 2][0] if f < 4 else 0.0
		var jy: float = jit[f % 2][1] if f < 4 else 0.0
		var reach := 0.0 if f < 4 else pow((f - 3) / 4.5, 1.5)
		var thin := 1.0 if f < 4 else 1.0 - (f - 3) / 5.5
		var phf: float = ph[f] if f < 4 else 0.0
		for j in H:
			for i in W:
				var X := x0 + i + 0.5 - jx
				var Y := y0 + j + 0.5 - jy
				var rho := Px.hypot(X, Y * 1.35)
				var ang := atan2(Y * 1.35, X)
				var slot := floori(fmod(fmod(ang, TAU) + TAU, TAU) / (TAU / n))
				var line := false
				var k := -1
				while k <= 1 and not line:
					var l: Dictionary = set_[(slot + k + n) % n]
					var d := fmod(fmod(ang - l.a, TAU) + TAU, TAU)
					if d > PI:
						d = TAU - d
					var inner: float = l.inner + reach * 150.0
					var hw: float = l.w * Px.clamp((rho - inner) / 40.0) * thin
					line = rho > inner and d * rho < maxf(0.5, hw)
					k += 1
				if f < 4:
					var r2 := Px.hypot(X, Y * 1.1)
					var core := spikes(atan2(Y * 1.1, X), phf) * (0.85 if f == 0 else 1.0 + f * 0.08)
					m[j * W + i] = (2 if r2 < 4 + f else 1) if r2 < core else (1 if line else 2)
				else:
					m[j * W + i] = 2 if line else 0
		masks.append(m)


func update(dt: float) -> void:
	t += dt


func draw(p: Px.Painter) -> void:
	var f := floori(t / FRAME + 1e-6)
	if f >= 8:
		return
	# two frames of ink on paper, two inverted, then paper lines pulling out over the scene
	var m: PackedByteArray = masks[f]
	var inv := f == 2 or f == 3
	var ink := PAPER if inv else INK
	var paper := INK if inv else PAPER
	var paper_ := PAPER
	var w := W
	var h := H
	var ox := x0
	var oy := y0
	p.shade(x0, y0, x0 + W, y0 + H, func(x, y):
		var i := floori(x - ox)
		var j := floori(y - oy)
		if i < 0 or j < 0 or i >= w or j >= h:
			return
		var v := m[j * w + i]
		return ink if v == 1 else ((paper if f < 4 else paper_) if v == 2 else 0))
