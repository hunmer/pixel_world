# The drops that splat where they land are adapted from Sprite Fusion's open-source blood
# (https://www.spritefusion.com/pixel-art-vfx/blood), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/nature/acid-splash.js@7ba1254a8ccb99ff43b8d82266f7c906bf635eca
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Acid splash",
	"desc": "A gob of acid bursts into a crown and spatters; it eats a glowing, smoking pit into the floor and boils down into it, spitting bright beads, pale steam curling off.",
	"tags": ["nature", "acid", "poison", "splash", "liquid", "ground", "one-shot"],
	"size": [184, 116],
	"origin": [92, 100],
	"duration": 2.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#0e140a", "#1c3010", "#2c5214", "#457e18", "#6aae1c", "#a0dc2a", "#dcff6a", "#f8ffd0"], "seed": 6},
}

const HIT := 0.3
const Y0 := -62.0
const V0 := 60.0
const SPREAD := 0.4
const DRY := 0.7
const GONE := 2.2
const W := 30.0
const PIT := 5.0


# a curl of steam: thin, pale, quick, fading as it goes
static func wisp(p: Px.Painter, q: Dictionary, t: float, col: int) -> void:
	var age: float = t - q.t0
	var u: float = age / q.life
	if u < 0.0 or u >= 1.0:
		return
	var head: float = q.rise * age
	var tail := maxf(0.0, head - q.len)
	var fade := Px.smooth(0.0, 0.15, u) * (1.0 - Px.smooth(0.4, 1.0, u))
	var h := tail
	while h <= head:
		var s := (h - tail) / maxf(1.0, head - tail)
		var x: float = q.x + q.amp * sin(h * q.k + q.ph) * (0.2 + s) + q.drift * age
		p.blend(x, q.y - h, col, fade * sin(PI * s) * 0.42)
		h += 0.5


var C: Array
var R: Px.Rng
var SCORCH: int
var BURNT: int
var STEAM: int
var ps: Px.Particles
var drops: Lib.Drops
var lights: Px.Lights
var stains: Array
var wisps: Array
var pops: Array
var spikes: Array
var rag: Array
var t := 0.0
var hit := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	SCORCH = Px.mix(C[0], Px.hex("#140f0c"), 0.6)
	BURNT = Px.mix(C[1], Px.hex("#2a1a10"), 0.6)
	STEAM = Px.mix(C[7], Px.hex("#e8ece6"), 0.75)
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]]})
	drops = Lib.Drops.new(floor_)
	lights = Px.Lights.new()
	stains = []
	wisps = []
	pops = []
	spikes = Px.arr(13, func(i: int) -> Dictionary: return {"a": (i / 13.0) * TAU + R.range(-0.18, 0.18), "h": R.range(4.0, 10.0), "r": R.range(0.85, 1.12), "shed": false})
	var seed: float = o.seed
	rag = Px.arr(80, func(i: int) -> float: return Px.rand(i, seed, 5) - 0.5)
	t = 0.0
	hit = false


# the pit it etches: wider as it spreads, deeper as it eats; the acid's level sinks into it as it boils away
func pw() -> float:
	return W * Px.Ease.outCubic(Px.clamp((t - HIT) / SPREAD)) * 1.02


func pitD() -> float:
	return PIT * Px.Ease.outCubic(Px.clamp((t - HIT) / 1.1))


func depth(x: float) -> float:
	var w := pw()
	var d := absf(x) / maxf(1.0, w)
	return -1.0 if d >= 1.0 else pitD() * sqrt(1.0 - d * d) + rag[(Px.roundi(x) + 200) % 80] * 0.9


func level() -> float:
	return 0.0 if t < HIT else -1.6 + (PIT + 1.6) * Px.Ease.inQuad(Px.smooth(DRY, GONE, t))


func width() -> float:
	var L := level()
	var w := pw()
	return w if L <= 0.0 else w * sqrt(maxf(0.0, 1.0 - pow(L / maxf(0.1, pitD()), 2.0)))


func heat() -> float:
	return Px.smooth(HIT, HIT + 0.3, t) * (1.0 - Px.smooth(GONE - 0.3, GONE + 0.25, t))


func gobY() -> float:
	return Y0 + V0 * t + 0.5 * 950.0 * t * t


func crownR() -> float:
	return 4.0 + 11.0 * Px.Ease.outCubic(Px.clamp((t - HIT) / 0.16))


func crownH() -> float:
	return 5.0 * sin(PI * Px.clamp((t - HIT) / 0.26))


func spikeK() -> float:
	var u := Px.clamp((t - HIT - 0.015) / 0.26)
	return sin(PI * pow(u, 0.6))


func tipOf(s: Dictionary) -> Array:
	var r: float = crownR() * s.r
	var h := crownH()
	var sn: float = sin(s.a)
	var sh: float = s.h * spikeK()
	var bx: float = cos(s.a) * r
	var by := sn * r * 0.3 - h * (0.75 + 0.25 * absf(sn))
	return [bx, by, bx + cos(s.a) * sh * 0.55, by - sh]


func steam(x: float, y: float, big: bool) -> void:
	wisps.append({"x": x, "y": y, "t0": t, "life": minf(R.range(0.5, 0.9) * (1.3 if big else 1.0), meta.duration - 0.05 - t), "rise": R.range(22.0, 32.0), "len": R.range(5.0, 10.0) * (1.4 if big else 1.0), "amp": R.range(1.0, 2.5), "k": R.range(0.35, 0.6), "ph": R.range(0.0, TAU), "drift": R.range(-4.0, 4.0)})


# the crown: a thin cup wall rising round the impact, a bright rim, spikes off the rim with beads on their tips
func crown(p: Px.Painter, back: bool) -> void:
	if t < HIT or t > HIT + 0.27:
		return
	var r := crownR()
	var h := crownH()
	var ry := r * 0.3
	for x in range(floori(-r), ceili(r) + 1):
		var c := (x + 0.5) / r
		if absf(c) > 1.0:
			continue
		var e := sqrt(1.0 - c * c)
		var yb := (-ry if back else ry) * e
		var hh := h * (0.75 + 0.25 * e)
		for y in range(floori(yb - hh), Px.roundi(yb) + 1):
			var rim := y == floori(yb - hh)
			if rim:
				p.px(x, y, C[5] if back else (C[7] if c < 0.1 else C[6]))
			else:
				p.blend(x, y, C[(5 if c < -0.25 else (3 if c > 0.45 else 4)) - (1 if back else 0)], 0.55 if back else 0.7)
	for s: Dictionary in spikes:
		if (sin(s.a) < 0.0) != back:
			continue
		var tp := tipOf(s)
		var bx: float = tp[0]
		var by: float = tp[1]
		var tx: float = tp[2]
		var ty: float = tp[3]
		p.line(bx, by, tx, ty, C[4] if back else C[6])
		p.line(bx + 1.0, by, (bx + tx) / 2.0 + 0.5, (by + ty) / 2.0, C[3] if back else C[5])
		if not s.shed:
			p.px(tx, ty - 1.0, C[5] if back else C[7])
			p.px(tx + 1.0, ty - 1.0, C[5])


func update(dt: float) -> void:
	t += dt
	var f := minf(1.0, dt * 120.0)
	var w := width()
	if not hit and t >= HIT:
		hit = true
		lights.add(0.0, -4.0, 28.0, WHITE, 0.6, 0.08)
		lights.add(0.0, -10.0, 56.0, C[5], 0.5, 0.6)
		for i in 26:
			var a := -PI / 2.0 + R.range(-1.35, 1.35)
			var sp := R.range(60.0, 250.0)
			drops.add(R.range(-3.0, 3.0), -2.0, cos(a) * sp, sin(a) * sp, 2.0 if R.chance(0.3) else 1.0)
		for i in 10:
			var a := -PI / 2.0 + R.range(-1.2, 1.2)
			var sp := R.range(120.0, 260.0)
			ps.spawn(P.SPARK, 0.0, -2.0, cos(a) * sp, sin(a) * sp, R.range(0.12, 0.3))
		for i in 5:
			steam(R.range(-10.0, 10.0), -R.range(2.0, 6.0), true)
	# beads break off the crown's spikes as they peak
	if hit:
		for s: Dictionary in spikes:
			if not s.shed and t > HIT + 0.09:
				s.shed = true
				var tp := tipOf(s)
				var tx: float = tp[2]
				var ty: float = tp[3]
				drops.add(tx, ty - 1.0, cos(s.a) * R.range(30.0, 80.0), -R.range(50.0, 130.0), 2.0 if R.chance(0.4) else 1.0)
	drops.update(dt, func(d: Dictionary) -> void:
		# a drop that lands eats a little spot into the floor and hisses
		if absf(d.x) > pw():
			stains.append({"x": d.x, "t0": t, "w": d.s * 0.8 + R.range(0.3, 1.2)})
		if t < GONE:
			steam(d.x, -1.0, false))
	# the acid sizzles: tiny bright beads spit off it, pops flash on its surface, steam curls off it and the pit
	var lv := level()
	var w2 := width()
	if t > HIT + 0.15 and t < GONE and w2 > 2.0:
		if R.chance(0.3 * f):
			var x := R.range(-0.85, 0.85) * w2
			var y := minf(lv, depth(x)) - 1.0
			pops.append({"x": x, "y": y, "t0": t})
			var j := 0
			while j < R.int_(1, 3):
				drops.add(x, minf(y - 1.0, -1.0), R.range(-40.0, 40.0), -R.range(50.0, 110.0), 1.0)
				j += 1
		if R.chance(0.14 * f):
			steam(R.range(-0.9, 0.9) * w2, minf(lv, 0.0) - 1.0, R.chance(0.25))
	# the pit keeps smoking a while after the acid is gone
	if t > GONE - 0.2 and t < meta.duration - 0.5 and R.chance(0.08 * f):
		steam(R.range(-0.7, 0.7) * pw(), 0.0, false)
	var i := pops.size() - 1
	while i >= 0:
		if t - pops[i].t0 > 0.1:
			pops.remove_at(i)
		i -= 1
	i = wisps.size() - 1
	while i >= 0:
		if t - wisps[i].t0 > wisps[i].life:
			wisps.remove_at(i)
		i -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var fade: float = 1.0 - Px.smooth(meta.duration - 0.6, meta.duration - 0.08, t)
	var hk := heat()
	var w := pw()
	var lv := level()
	# spatter spots etched round it
	for s: Dictionary in stains:
		var age: float = t - s.t0
		var k := 1.0 - Px.smooth(1.0, 1.8, age)
		var c: int = C[7] if age < 0.15 else (C[6] if age < 0.5 else (C[4] if age < 0.9 else BURNT))
		for x in range(floori(s.x - s.w), ceili(s.x + s.w) + 1):
			p.dot(x, 0.0, SCORCH if absf(x - s.x) < s.w * 0.5 else c, k * fade)
		if age < 0.5:
			p.glow(s.x, -1.0, 5.0, C[5], 0.3 * (1.0 - age / 0.5))
	crown(p, true)
	if t > HIT and w > 1.0:
		# the pit: an etched bowl in the floor, its edge glowing where the acid is still eating, cooling to a burnt lip
		for x in range(floori(-w) - 1, ceili(w) + 2):
			var dp := depth(x + 0.5)
			if dp < 0.0:
				continue
			var bottom := maxi(0, Px.roundi(dp))
			var edge := absf(x + 0.5) / w > 0.88
			for y in bottom + 1:
				p.dot(x, y, ((C[6] if hk > 0.5 else (C[4] if hk > 0.15 else BURNT)) if y == bottom else SCORCH), fade)
			p.dot(x, bottom + 1, C[5] if hk > 0.5 else (C[3] if hk > 0.15 else SCORCH), fade * 0.8)
			if edge:
				p.dot(x, -1.0, C[7] if hk > 0.4 else (C[5] if hk > 0.1 else BURNT), fade)
		for sd in [-1, 1]:
			p.glow(sd * w, -1.0, 8.0, C[6], 0.45 * hk)
		# the acid in it: a bright skin shimmering on top, darker as it deepens, sinking as it boils off
		if t < GONE:
			for x in range(floori(-w), ceili(w) + 1):
				var dp := depth(x + 0.5)
				if dp < 0.0:
					continue
				var d := absf(x + 0.5) / w
				var dome := Px.roundi(lv * sqrt(maxf(0.0, 1.0 - d * d))) if lv < 0.0 else Px.roundi(lv)
				var bottom := Px.roundi(dp)
				if dome > bottom:
					continue
				var n := Px.noise(x * 0.25 - t * 2.4, 3) + Px.noise(x * 0.1 + t * 1.4, 5) * 0.6
				for y in range(dome, bottom + 1):
					p.px(x, y, (C[7] if n > 0.7 else C[6]) if y == dome else ((C[5] if n > 0.2 else C[4]) if y == dome + 1 else (C[3] if y >= bottom else C[4])))
		p.glow(0.0, -6.0, w * 1.4 + 10.0, C[4], 0.3 * hk * (0.85 + 0.15 * sin(t * 9.0)))
		p.glow(0.0, 1.0, w * 0.9, C[6], 0.2 * hk)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	# the gob: a teardrop stretched by its fall, lit on its upper left, a trail of droplets above it
	if t < HIT:
		var y := gobY()
		var v := V0 + 950.0 * t
		var st := 1.0 + v * 0.0022
		var rx := 2.6 / sqrt(st)
		var ry := 2.8 * st
		p.shade(-rx - 1.0, y - ry - 4.0, rx + 1.0, y + ry + 1.0, func(x: float, yy: float, out):
			var dx := x / rx
			var dy := (yy - y) / ry
			var tail := dy < 0.0 and absf(x) < rx * (1.0 + dy * 0.9) + 0.4 and dy > -1.7
			var d := dx * dx + dy * dy
			if d > 1.25 and not tail:
				return
			out.c = C[2] if (d > 1.0 and not tail) else (C[7] if (dx < -0.2 and dy < -0.1) else (C[4] if dy > 0.45 else C[5])))
		p.px(-1.0, y - ry * 0.3, WHITE)
		for i in range(1, 4):
			p.dot(0.0, y - ry - 2.0 - i * 4, C[5], 1.0 - i * 0.25)
		p.glow(0.0, y, 10.0, C[5], 0.45)
	crown(p, false)
	# the hero frame: a white burst where it lands
	var e := t - HIT
	if e >= 0.0 and e < 0.07:
		var k := 1.0 - e / 0.07
		p.ellipse(0.0, -2.0, 6.0 + 6.0 * (1.0 - k), 2.5, WHITE if k > 0.5 else C[7])
		Px.sparkle(p, 0.0, -4.0, 8.0 * k, C[7], C[6], 0.6)
	# sizzle: tiny star flashes where beads spit off the surface
	for q: Dictionary in pops:
		var k: float = (t - q.t0) / 0.1
		p.px(q.x, q.y, WHITE)
		for dd: Array in [[1, 0], [-1, 0], [0, -1]]:
			p.dot(q.x + dd[0] * (1.0 + k * 2.0), q.y + dd[1] * (1.0 + k * 2.0), C[7], 1.0 - k)
		p.glow(q.x, q.y, 4.0, C[6], 0.4 * (1.0 - k))
	for q: Dictionary in wisps:
		wisp(p, q, t, STEAM)
	drops.draw(p, C)
	ps.draw(p, "front")
	lights.draw(p)
