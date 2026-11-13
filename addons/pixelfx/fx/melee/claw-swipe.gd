# The shaded smear, its light and the dotted trace follow Sprite Fusion's open-source slash
# (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/claw-swipe.js@5db5500b64e9e83c7d4f24f6bd886692f620261f
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B

static var meta := {
	"name": "Claw swipe",
	"desc": "Three claw marks rake down one after another, white-hot, cooling through orange to red, then close up from both ends and leave a dotted scar, with hot flecks and drips.",
	"tags": ["melee", "claw", "swipe", "beast", "scratch", "combat", "directional", "one-shot"],
	"size": [128, 96],
	"origin": [36, 84],
	"duration": 0.9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#2a0808", "#5c0f12", "#a51d1d", "#e2401f", "#ff8a2a", "#ffd166", "#fff3c4", "#ffffff"],
		"sparks": ["#fff3c4", "#ffd166", "#ff8a2a", "#c42a1a"],
		"seed": 8,
	},
}

static var READY_ := Px.merge(Px.READY, {"weapon": "claw", "offWeapon": "claw", "sa": -0.4, "sb": -0.9, "crouch": 5, "lean": 3, "fx": 14, "fy": -21, "bx": 8, "by": -25, "ffx": 9, "fbx": -8})
static var HIGH := Px.merge(READY_, {"x": -6, "crouch": 4, "lean": -3, "fx": 3, "fy": -41, "sa": -1.4, "bx": 7, "by": -18, "sb": -0.3, "ffx": 10})
static var act := {
	"target": {"x": 58},
	"poses": [
		[-0.46, Px.merge(READY_, {"x": -6})],
		[-0.2, HIGH],
		[-0.05, Px.merge(HIGH, {"crouch": 5})],
		[0, Px.merge(READY_, {"x": 0, "crouch": 3, "lean": 4, "fx": 19, "fy": -36, "sa": -0.9, "bx": -7, "by": -24, "ghost": 1}), "snap"],
		[0.05, Px.merge(READY_, {"x": 2, "crouch": 5, "lean": 6, "fx": 23, "fy": -24, "sa": 0.5, "bx": -7, "by": -24, "ffx": 13, "fbx": -10, "toeB": true}), "snap"],
		[0.1, Px.merge(READY_, {"x": 3, "crouch": 7, "lean": 7, "fx": 22, "fy": -12, "sa": 1.2, "bx": -7, "by": -24, "ffx": 13, "fbx": -10, "toeB": true}), "snap"],
		[0.42, Px.merge(READY_, {"x": 3, "crouch": 6, "lean": 5, "fx": 21, "fy": -13, "sa": 1.1, "bx": -6, "by": -22, "ffx": 13, "fbx": -10})],
		[0.9, Px.merge(READY_, {"x": -6})],
	],
	"hits": [
		{"t": 0.04, "stop": 0.03, "push": 0.9, "straw": 5, "y": -30, "flash": 0.03},
		{"t": 0.08, "stop": 0.03, "push": 0.9, "straw": 5, "y": -26, "flash": 0.03},
		{"t": 0.12, "stop": 0.08, "shake": 0.14, "amp": 2, "push": 1.4, "straw": 9, "y": -18},
	],
	"dust": [{"t": 0.1, "x": 12, "n": 6, "dir": 1}],
}

const RAKE := 0.05  # each mark tears open
const STAGGER := 0.04
const CLOSE0 := 0.16  # then closes up from both ends
const CLOSE := 0.3


var C: Array
var n: int
var Rg: Px.Rng
var ps: Px.Particles
var drips: Px.Bits
var lights: Px.Lights
var marks: Array
var t := 0.0


func heatAt(m: Dictionary) -> float:
	return Px.clamp(1.0 - (t - m.t0) / 0.42)


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	n = C.size()
	Rg = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": Rg, "ground": floor_, "sparks": o.sparks})
	drips = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	# three marks raking down and back, each a little lower and further out than the last
	marks = [0, 1, 2].map(func(i):
		var s := Lib.through(31.0 + i * 8, -23.0 + i * 2, 1.84, 1.0, 40.0, 0.84 - i * 0.05, 0.5)
		return {"s": s, "t0": i * STAGGER, "W": 4.2 - i * 0.4, "open": false, "end": Lib.travel(s, s.span)})


func update(dt: float) -> void:
	t += dt
	for m: Dictionary in marks:
		if not m.open and t >= m.t0 + RAKE * 0.7:
			m.open = true
			lights.add(m.end.x, m.end.y - 6.0, 34.0, C[4], 0.45, 0.3)
			# hot flecks thrown on along the rake, and drips running off the wound
			for i in 7:
				var a: float = atan2(m.end.dy, m.end.dx) + Rg.range(-0.5, 0.5)
				var sp := Rg.range(110.0, 260.0)
				ps.spawn(P.SPARK, m.end.x, m.end.y, cos(a) * sp, sin(a) * sp, Rg.range(0.12, 0.32))
			for i in 5:
				var xy := Lib.onSwing(m.s, m.s.R, m.s.span * Rg.range(0.15, 0.9))
				ps.spawn(P.MOTE, xy[0], xy[1], Rg.range(-60.0, -10.0), Rg.range(-30.0, 30.0), Rg.range(0.2, 0.4), C[5] if Rg.chance(0.5) else C[4], 0.5)
			for i in 2:
				var xy := Lib.onSwing(m.s, m.s.R - 1.0, m.s.span * Rg.range(0.35, 0.75))
				drips.add({"kind": B.DRIP, "x": xy[0], "y": xy[1], "vx": Rg.range(-8.0, 8.0), "vy": Rg.range(10.0, 40.0), "g": 0.55, "life": 1.2, "c": C[3]})
	drips.update(dt)
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	for m: Dictionary in marks:
		var u: float = t - m.t0
		if u < 0.0:
			continue
		var S: float = m.s.span
		var head := S * Px.Ease.outExpo(Px.clamp(u / RAKE))
		var c := Px.smooth(CLOSE0, CLOSE0 + CLOSE, u)
		var lo := (S / 2.0) * c
		var hi := minf(head, S - (S / 2.0) * c)
		var heat := heatAt(m)
		if hi - lo > 0.02:
			# a lens: sharp at both ends, thickest in the middle; white-hot at the core, cooling outward and with time
			var CC := C
			var nn := n
			Lib.smear(p, m.s, lo, hi, m.W, func(uu, r, out):
				var v: float = uu / S
				var w: float = m.W * pow(sin(PI * v), 1.15) * (1.0 - 0.55 * c)
				var off: float = absf(r - (m.s.R - m.W / 2.0)) / (w / 2.0 + 0.01)
				if w < 0.5 or off > 1.0:
					return
				var ci := Px.round((1.0 - heat) * 5.2 + off * 1.6 + ((S - uu) / S if head < S else 0.0) * 0.5)
				out.c = CC[nn - 1 - int(Px.clamp(ci, 0.0, nn - 2))], 0.0, 2.0)
			Lib.glowAlong(p, m.s, m.s.R - m.W / 2.0, lo, hi, 11.0, C[4], 0.42 * heat * heat, 0.0, 0.2)
		# where it has closed, a dotted red scar lingers and fades
		var k := 0.8 * (1.0 - Px.clamp((u - CLOSE0 - CLOSE * 0.5) / 0.4))
		if c > 0.05 and k > 0.0:
			Lib.trace(p, m.s, m.s.R - m.W / 2.0, 0.04 * S, lo, C[2], k)
			Lib.trace(p, m.s, m.s.R - m.W / 2.0, S - lo, 0.96 * S, C[2], k)
		# the claw tip glints as it tears in
		var g := u - RAKE * 0.4
		if g > 0.0 and g < 0.16:
			Px.sparkle(p, m.end.x, m.end.y, 5.0 * Px.Ease.outBack(minf(1.0, g / 0.04)) * (1.0 - g / 0.16), C[6], C[4], 0.4)
	drips.draw(p)
	ps.draw(p)
	lights.draw(p)
