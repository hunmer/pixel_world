# port-of: src/fx/ui/health-bar-hit.js@14c43a3c6f6b7f46b0827798ccb27c8aed5e23ce
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Health bar hit",
	"desc": "A segmented health bar takes a hit: it jolts and dips, the lost chunk flashes white and sheds chips, holds, then drains away behind a sparking edge.",
	"tags": ["ui", "health", "hud", "damage", "bar", "one-shot"],
	"size": [160, 64],
	"origin": [80, 30],
	"duration": 2.0,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": ["#1a0508", "#4a0b12", "#8c1420", "#d42a2e", "#ff5a4a", "#ff9a86", "#ffd8cc", "#ffffff"], "from": 0.8, "to": 0.45, "seed": 3},
}

const HIT := 0.2
const DRAIN := 0.62
const DRAINED := 1.05
const FOLD := 1.62
const BX := -48.0
const BW := 104.0
const BY := -4.0
const BH := 8.0
const CELLS := 10
static var INK := {"outline": Px.hex("#0d0a14"), "rim": Px.hex("#4a4060"), "top": Px.hex("#2a2338"), "body": Px.hex("#1e1929"), "low": Px.hex("#141019")}
static var K0D0A14 := Px.hex("#0d0a14")
static var K2A2338 := Px.hex("#2a2338")
static var K191424 := Px.hex("#191424")


var o: Dictionary
var C: Array
var R: Px.Rng
var from: float
var to: float
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var PALE: int
var pal: Dictionary
var t := 0.0
var hit := false
var end: float


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	from = Px.clamp(o.from)
	to = Px.clamp(minf(o.to, from))
	ps = Px.Particles.new({"rng": R, "sparks": [C[7], C[6], C[5], C[3]]})
	bits = Px.Bits.new()
	lights = Px.Lights.new()
	PALE = Px.mix(C[6], Px.hex("#ffe9a8"), 0.5)
	pal = Lib.heartPal(C)
	end = meta.duration - 0.05


# the white chunk's right end: holds, then drains down to the new value
func ghostAt(tt: float) -> float:
	return from if tt < DRAIN else from - (from - to) * Px.Ease.inOutQuad(Px.seg(tt, DRAIN, DRAINED))


func update(dt: float) -> void:
	t += dt
	if not hit and t >= HIT:
		hit = true
		lights.add(BX + BW * (to + from) / 2.0, BY + 4.0, 50.0, C[5], 0.7, 0.3)
		lights.add(BX + BW * (to + from) / 2.0, BY + 4.0, 24.0, WHITE, 0.6, 0.08)
		# chips break off the lost chunk
		for i in 12:
			var x := BX + BW * R.range(to, from)
			var an := -PI / 2.0 + R.range(-1.2, 1.2)
			var sp := R.range(50.0, 130.0)
			bits.add({"kind": B.SHARD, "x": x, "y": BY + R.range(1.0, 7.0), "vx": cos(an) * sp, "vy": sin(an) * sp, "g": 0.45, "drag": 1.2, "life": R.range(0.35, 0.6), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.5, 3.0), "c": R.pick([C[7], C[6], C[5], C[4]])})
		for i in 10:
			var an := R.range(0.0, TAU)
			var sp := R.range(60.0, 160.0)
			ps.spawn(P.SPARK, BX + BW * R.range(to, from), BY + 4.0, cos(an) * sp, sin(an) * sp * 0.6 - 30.0, R.range(0.12, 0.26))
	# the draining edge sparks as it runs back
	if t > DRAIN and t < DRAINED and R.chance(0.5):
		var x := BX + BW * ghostAt(t)
		ps.spawn(P.SPARK, x, BY + R.range(1.0, 7.0), R.range(-20.0, 60.0), -R.range(20.0, 70.0), R.range(0.1, 0.22))
	bits.update(dt)
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	var j := Lib.shake(t, 3.0, HIT, 0.28, o.seed)
	var jx: float = j[0]
	var jy: float = j[1]
	var dip := Px.round(3.0 * exp(-(t - HIT) * 10.0) * cos((t - HIT) * 24.0)) if t > HIT else 0.0
	var open := Px.Ease.outBack(Px.seg(t, 0.0, 0.14), 2.0) * (1.0 - Px.Ease.inBack(Px.seg(t, FOLD, FOLD + 0.18), 2.0))
	if open > 0.04:
		var ox := jx
		var oy := jy + dip
		var h := 18.0 * open
		var y0 := -9.0 + (18.0 - h) / 2.0
		# the frame flashes red on the hit
		var red := t >= HIT and t < HIT + 0.07
		Lib.panel(p, BX - 22.0 + ox, y0 + oy, BW + 26.0, h, Px.merge(INK, {"outline": C[4], "rim": C[6]}) if red else INK, {"r": minf(5.0, h / 2.0)})
		if open > 0.75:
			# the track, then the fill (red, lit on top, dark below), the white chunk, and the cell dividers
			var val := from if t < HIT else to
			var ghost := from if t < HIT else ghostAt(t)
			var white := t >= HIT and t < HIT + 0.07
			p.rect(BX + ox, BY + oy, BW, BH, K0D0A14)
			p.shade(BX + ox, BY + oy, BX + BW + ox, BY + BH + oy, func(x: float, y: float):
				var u := (x - BX - ox) / BW
				var v := y - BY - oy
				if u < val:
					return C[6] if v < 1.0 else (C[5] if v < 2.0 else (C[4] if v < 5.0 else (C[3] if v < 7.0 else C[2])))
				if u < ghost:
					return WHITE if white else (WHITE if v < 1.0 else (PALE if v < 6.0 else C[5]))
				return K2A2338 if v < 1.0 else K191424)
			for i in range(1, CELLS):
				p.rect(BX + ox + Px.round((BW * i) / CELLS), BY + oy, 1.0, BH, K0D0A14)
			# the new edge of the health glints, and a hot spark rides the draining edge
			if t > HIT:
				p.rect(BX + ox + Px.round(BW * val) - 1.0, BY + oy, 1.0, BH, C[7])
			if t > DRAIN and t < DRAINED:
				var gx := BX + ox + BW * ghost
				p.rect(gx - 1.0, BY + oy - 1.0, 2.0, BH + 2.0, WHITE)
				p.glow(gx, BY + oy + 4.0, 10.0, C[5], 0.6)
			p.glow(BX + ox + BW * val * 0.5, BY + oy + 4.0, BW * 0.4, C[3], 0.12)
			# the heart: jumps and flashes white on the hit, glints before it
			var hk := t - HIT
			var hop := Px.round(-3.0 * exp(-hk * 12.0) * absf(cos(hk * 22.0))) if hk > 0.0 else 0.0
			p.sprite(Lib.HEART, pal, BX - 17.0 + ox, oy - 6.0 + hop)
			if hk > 0.0 and hk < 0.07:
				p.sprite(Lib.HEART, Px.merge(pal, {"k": 0, "w": WHITE, "h": WHITE, "o": WHITE, "m": WHITE, "d": C[6]}), BX - 17.0 + ox, oy - 6.0 + hop)
			p.glow(BX - 11.0 + ox, oy, 10.0, C[4], 0.25 + (0.4 if (hk > 0.0 and hk < 0.2) else 0.0))
			if t < HIT and fmod(t * 2.5, 1.0) < 0.3:
				Px.sparkle(p, BX - 14.0 + ox, oy - 3.0, 2.0, C[7], C[6], 0.3)
	bits.draw(p)
	ps.draw(p)
	lights.draw(p)
