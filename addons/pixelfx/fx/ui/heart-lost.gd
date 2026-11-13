# port-of: src/fx/ui/heart-lost.js@dc4ffa2c6ab6c786823cdddf7d4d83752cd66dd3
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Heart lost",
	"desc": "A HUD heart is hit: it flashes white and jolts, a crack runs down it, it splits into two halves that tumble away, leaving an empty socket that fades.",
	"tags": ["ui", "health", "heart", "hud", "damage", "one-shot"],
	"size": [96, 88],
	"origin": [48, 34],
	"duration": 1.5,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": ["#1a0508", "#4a0b12", "#8c1420", "#d42a2e", "#ff5a4a", "#ff9a86", "#ffd8cc", "#ffffff"], "seed": 5},
}

const HIT := 0.14
const CRACK := 0.24
const SPLIT := 0.5
# the heart's shape, 19 x 16, centred on (0, 0)
const MASK := [
	"....xxxx...xxxx....",
	"..xxxxxxx.xxxxxxx..",
	".xxxxxxxxxxxxxxxxx.",
	"xxxxxxxxxxxxxxxxxxx",
	"xxxxxxxxxxxxxxxxxxx",
	"xxxxxxxxxxxxxxxxxxx",
	"xxxxxxxxxxxxxxxxxxx",
	".xxxxxxxxxxxxxxxxx.",
	"..xxxxxxxxxxxxxxx..",
	"...xxxxxxxxxxxxx...",
	"....xxxxxxxxxxx....",
	".....xxxxxxxxx.....",
	"......xxxxxxx......",
	".......xxxxx.......",
	"........xxx........",
	".........x.........",
]
const MW := 19
const MH := 16
const OX := -9.5
const OY := -8.0


static func inMask(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < MW and j < MH and MASK[j][i] == "x"


# the crack: a zigzag from the notch to the tip, as a column per row
const CRACK_X := [9, 9, 10, 9, 8, 8, 9, 10, 10, 9, 8, 9, 9, 10, 9, 9]


# the heart's own color at mask pixel (i, j): a lit left lobe with a white glint, shade down the right
static func shadeAt(C: Array, i: int, j: int) -> int:
	var u := (i - 9) / 9.5
	var v := (j - 7) / 8.0
	if (i == 3 or i == 4) and (j == 2 or j == 3) and not (i == 4 and j == 3):
		return WHITE
	if i >= 2 and i <= 5 and j >= 2 and j <= 5 and u + v < -0.75:
		return C[5]
	var l := -(u * 0.55 + v * 0.65)
	return C[4] if l > 0.25 else (C[3] if l > -0.3 else (C[2] if l > -0.6 else C[1]))


static func _own(side: float, i: int, j: int) -> bool:
	return inMask(i, j) and (side == 0.0 or ((i < CRACK_X[j]) if side < 0.0 else (i >= CRACK_X[j])))


# draw part of the heart (side: -1 left of the crack, 1 right, 0 whole) turned by a about its pivot
static func drawPart(p: Px.Painter, C: Array, side: float, x: float, y: float, a: float, white: bool, crackK: float, alpha: float) -> void:
	var ca := cos(a)
	var sa := sin(a)
	var px0 := -4.5 if side < 0.0 else (4.5 if side > 0.0 else 0.0)
	var py0 := 0.0
	p.shade(x - 13.0, y - 13.0, x + 13.0, y + 13.0, func(sx: float, sy: float, o):
		# back into the heart's own pixels
		var dx := sx - x
		var dy := sy - y
		var lx := dx * ca + dy * sa + px0
		var ly := -dx * sa + dy * ca + py0
		var i := floori(lx - OX)
		var j := floori(ly - OY)
		if not _own(side, i, j):
			return null
		o.a = alpha
		var edge := not _own(side, i - 1, j) or not _own(side, i + 1, j) or not _own(side, i, j - 1) or not _own(side, i, j + 1)
		if white:
			return C[6] if edge else WHITE
		if edge:
			return C[0]
		# the crack opens down the middle, dark with a lit lip
		if side == 0.0 and j / float(MH) < crackK:
			if i == CRACK_X[j]:
				return C[0]
			if i == CRACK_X[j] - 1:
				return C[6]
		return shadeAt(C, i, j))


var o: Dictionary
var C: Array
var R: Px.Rng
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var SOCKET: Array
var halves: Array
var t := 0.0
var hit := false
var split := false
var gone := false
var end: float


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [C[7], C[6], C[5], C[3]]})
	bits = Px.Bits.new()
	lights = Px.Lights.new()
	SOCKET = [Px.hex("#0d0a14"), Px.hex("#2a2338"), Px.hex("#3c3350")]
	halves = [-1.0, 1.0].map(func(s: float): return {"s": s, "x": s * 4.5, "y": 0.0, "vx": s * R.range(55.0, 70.0), "vy": -R.range(60.0, 80.0), "a": 0.0, "va": s * R.range(2.2, 3.2)})
	end = meta.duration - 0.05


func update(dt: float) -> void:
	t += dt
	if not hit and t >= HIT:
		hit = true
		lights.add(0.0, 0.0, 40.0, C[5], 0.6, 0.3)
		for i in 8:
			var an := R.range(0.0, TAU)
			var sp := R.range(80.0, 170.0)
			ps.spawn(P.SPARK, cos(an) * 9.0, sin(an) * 7.0, cos(an) * sp, sin(an) * sp - 30.0, R.range(0.1, 0.22))
	if not split and t >= SPLIT:
		split = true
		lights.add(0.0, 0.0, 44.0, WHITE, 0.6, 0.12)
		lights.add(0.0, 0.0, 50.0, C[5], 0.5, 0.4)
		# the break throws shards from the crack and a puff of red dust
		for i in 12:
			var j := R.int_(1, 14)
			var an := -PI / 2.0 + R.range(-1.4, 1.4)
			var sp := R.range(40.0, 100.0)
			bits.add({"kind": B.SHARD, "x": CRACK_X[j] + OX, "y": j + OY, "vx": cos(an) * sp, "vy": sin(an) * sp, "g": 0.5, "drag": 1.0, "life": R.range(0.35, 0.55), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.5, 3.0), "c": R.pick([C[6], C[5], C[4], C[3]])})
		for i in 5:
			ps.spawn(P.DUST, R.range(-2.0, 2.0), R.range(-6.0, 6.0), R.range(-25.0, 25.0), R.range(-20.0, 5.0), R.range(0.35, 0.6), C[2], R.range(2.0, 3.5))
		for i in 6:
			var an := R.range(0.0, TAU)
			var sp := R.range(30.0, 70.0)
			ps.spawn(P.STAR, cos(an) * 4.0, sin(an) * 4.0, cos(an) * sp, sin(an) * sp, R.range(0.25, 0.45), R.pick([C[7], C[6]]), 0.6 if i % 2 else 1.4)
	if split and not gone and t >= 0.95:
		gone = true
		for h: Dictionary in halves:
			for i in 5:
				var an := R.range(0.0, TAU)
				var sp := R.range(20.0, 50.0)
				ps.spawn(P.STAR, h.x + cos(an) * 4.0, h.y + sin(an) * 4.0, cos(an) * sp, sin(an) * sp - 10.0, minf(R.range(0.2, 0.35), end - t), R.pick([C[7], C[6], C[5]]), 0.6 if i else 1.3)
	if split:
		for h: Dictionary in halves:
			h.vy += 520.0 * dt
			h.vx -= h.vx * 0.6 * dt
			h.x += h.vx * dt
			h.y += h.vy * dt
			h.a += h.va * dt
			# a shard or two of red trails off each half as it tumbles
			if t < 0.92 and R.chance(0.05):
				ps.spawn(P.EMBER, h.x, h.y, R.range(-10.0, 10.0), R.range(-10.0, 5.0), minf(R.range(0.3, 0.5), end - t), C[4], 1.0)
	bits.update(dt)
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	var jxy := Lib.shake(t, 3.0, HIT, 0.25, o.seed)
	var jx: float = jxy[0]
	var jy: float = jxy[1]
	var tremble := Px.round(sin(t * 90.0)) if (t > CRACK and t < SPLIT) else 0.0
	# the empty socket it leaves behind, which fades away at the end
	var sk := Px.seg(t, SPLIT - 0.05, SPLIT + 0.1) * (1.0 - Px.seg(t, 1.15, 1.4))
	if sk > 0.0:
		p.shade(-12.0, -10.0, 12.0, 10.0, func(sx: float, sy: float, out):
			var i := floori(sx - OX)
			var j := floori(sy - OY)
			if not inMask(i, j):
				return null
			out.a = sk
			var edge := not inMask(i - 1, j) or not inMask(i + 1, j) or not inMask(i, j - 1) or not inMask(i, j + 1)
			return SOCKET[2] if edge else (SOCKET[1] if j < 3 else SOCKET[0]))
	if t < SPLIT:
		# whole: it beats before the hit, flashes white and jolts on it, then trembles as the crack runs down
		var beat := 1.0 + 0.08 * maxf(0.0, sin(t * 22.0)) if t < HIT else 1.0
		var white := t >= HIT and t < HIT + 0.07
		drawPart(p, C, 0.0, jx + tremble, jy, 0.0, white, Px.seg(t, CRACK, SPLIT - 0.06), 1.0)
		p.glow(0.0, 0.0, 18.0 * beat, C[4], 0.3 + (0.5 if white else 0.0))
		if t < HIT:
			Px.sparkle(p, -6.0, -5.0, 2.5 * maxf(0.0, sin(t * 22.0)), C[7], C[6], 0.3)
	else:
		# the halves tumble away, flashing white on the break, and fade
		var fade := 1.0 - Px.seg(t, 0.9, 1.0)
		var white := t < SPLIT + 0.05
		if fade > 0.0:
			for h: Dictionary in halves:
				drawPart(p, C, h.s, h.x, h.y, h.a, white, 0.0, fade)
		var rk := (t - SPLIT) / 0.3
		if rk < 1.0:
			p.ring(0.0, 0.0, 8.0 + 16.0 * Px.Ease.outCubic(rk), maxf(1.0, 2.0 * (1.0 - rk)), WHITE if rk < 0.3 else C[5], 1.2 - rk)
	bits.draw(p)
	ps.draw(p)
	lights.draw(p)
