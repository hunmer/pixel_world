# Shared by the projectile effects: a steady emitter for loops, motion in a projectile's own frame, soft smoke
# puffs, speed-stretched sparks, muzzle-flash lobes, brass casings that bounce, and outlined pixel shapes.
# The smoke puff, spark streak, flash lobe and casing recipes are adapted from Sprite Fusion's open-source
# muzzle-flash and explosion (https://www.spritefusion.com/pixel-art-vfx/muzzle-flash),
# MIT License, Copyright (c) 2026 Hugo Duprez. Files starting with _ are helpers, not effects.
# port-of: src/fx/projectiles/_lib.js@eaef81554766de64940d45946d5c07fe59d20ab7
extends RefCounted

const Px := preload("../../core/px.gd")
const Self := preload("_lib.gd")
const WHITE := Px.WHITE


## Like cycle(), but particle i is born exactly at i * period / n: an emitter with a steady beat, so a trail
## has no clumps or gaps. Loops seamlessly over period. fn(age, life, r, i), r the same rng every period.
static func beat(t: float, period: float, n: float, seed: Variant, life: Variant, fn: Callable) -> void:
	var na := fn.get_argument_count()
	var i := 0
	while i < n:
		var L: float = life.call(Px.rng(seed, i, 911)) if life is Callable else life
		var age := Px.wrap(t - (i * period) / n + 1e-7, period)
		while age < L:
			Px.call4(fn, na, age, L, Px.rng(seed, i), i)
			age += period
		i += 1


## Where something is after `age` seconds in the frame of a projectile that flies right at V px/s: launched
## from (x, y) at (vx, vy) relative to the still air, slowed toward the air by drag k (1/s), pulled by g.
## The air streams left at V, so whatever it carries streams left too. Returns [x, y, vx, vy] (screen motion).
static func wake(x: float, y: float, vx: float, vy: float, age: float, V: float, k: float, g: float = 0.0) -> Array:
	var e := exp(-k * age)
	var f := (1.0 - e) / k
	var vt := g / k
	return [x + vx * f - V * age, y + vt * age + (vy - vt) * f, vx * e - V, vt + (vy - vt) * e]


## A soft smoke puff: a body, a denser core sitting low, a lit cap on top while it's young (cap 0..1), and
## light from a fire on one side (warm 0..1 of color wc, coming from angle wa).
static func puff(p: Px.Painter, x: float, y: float, r: float, a: float, c: int, cap: float = 1.0, warm: float = 0.0, wc: int = 0, wa: float = 0.0) -> void:
	if a <= 0.01 or r < 0.5:
		return
	p.disc(x, y, r, c, a * 0.45)
	p.disc(x + r * 0.05, y + r * 0.06, r * 0.74, c, a * 0.62)
	if cap > 0.02:
		p.disc(x - r * 0.22, y - r * 0.3, r * 0.5, Px.mix(c, WHITE, 0.14), a * 0.42 * cap)
	if warm > 0.02:
		p.disc(x + cos(wa) * r * 0.32, y + sin(wa) * r * 0.32, r * 0.55, wc, a * 0.7 * warm)


## Puffs [{ x, y, r, a, b (brightness 0..1), w (fire light 0..1) }] merged into one translucent volume: each
## puff is lit on top and shaded underneath, densities add up, and tone and density come out in clean steps, so
## a trail reads as one billowing cloud with lit crowns instead of a string of beads. R: smoke ramp, dark to
## bright; WR: the same smoke lit by fire (a ramp as long as R), which young puffs (w) lean to. clip(x, y) can
## keep it off part of the canvas.
## opts: { dens = 1.5, max = 0.86, clip, lit = 1 }
static func cloud(p: Px.Painter, list: Array, R: Array, WR: Array, opts: Dictionary = {}) -> void:
	var dens: float = opts.get("dens", 1.5)
	var max_: float = opts.get("max", 0.86)
	var clip: Variant = opts.get("clip")
	var lit: float = opts.get("lit", 1.0)
	if not list.size():
		return
	var X0 := 0x7fffffffffff
	var Y0 := 0x7fffffffffff
	var X1 := -0x7fffffffffff
	var Y1 := -0x7fffffffffff
	for q: Dictionary in list:
		X0 = mini(X0, floori(q.x - q.r))
		X1 = maxi(X1, ceili(q.x + q.r))
		Y0 = mini(Y0, floori(q.y - q.r))
		Y1 = maxi(Y1, ceili(q.y + q.r))
	var W := X1 - X0 + 3
	var H := Y1 - Y0 + 3
	var D := PackedFloat32Array()
	D.resize(W * H)
	var L := PackedFloat32Array()
	L.resize(W * H)
	var F := PackedFloat32Array()
	F.resize(W * H)
	X0 -= 1
	Y0 -= 1
	for q: Dictionary in list:
		var r: float = q.r
		var r2 := r * r
		# (q's fields read once into typed locals: the same numbers, a lot faster than a lookup per pixel)
		var qx: float = q.x
		var qy: float = q.y
		var qa: float = q.a
		var qb: float = q.b
		var qw: float = q.w
		for y in range(floori(qy - r), ceili(qy + r) + 1):
			var dy := y + 0.5 - qy
			for x in range(floori(qx - r), ceili(qx + r) + 1):
				var dx := x + 0.5 - qx
				var d2 := (dx * dx + dy * dy) / r2
				if d2 >= 1.0:
					continue
				# a ball's thickness: flat in the middle, steep at the rim, so every lump keeps its own crown
				var k := sqrt(1.0 - d2) * qa
				var i := (y - Y0) * W + (x - X0)
				D[i] += k
				L[i] += k * qb
				F[i] += k * qw * (0.5 + 0.5 * Px.clamp(0.5 + dx / r))
	# light the merged surface: where density climbs downward the cloud faces up and catches the light. The
	# gradient comes off a blurred copy, so only lump-sized features catch it, never the crossing rims
	var B := blur(blur(D, W, H, 1, 2), W, H, W, 2)
	var n := R.size()
	var has_clip := clip is Callable
	# mix(R[j], WR[j], m) only ever takes n * 9 values: each is worked out once, on first use (same colors, far fewer calls)
	var mixed := []
	mixed.resize(n * 10)
	p.each(X0 + 1, Y0 + 1, X1 + 1, Y1 + 1, func(lx: float, ly: float, sx: int, sy: int) -> void:
		var cx := floori(lx) - X0
		var cy := floori(ly) - Y0
		if cx < 1 or cy < 1 or cx >= W - 1 or cy >= H - 1:
			return
		var i := cy * W + cx
		var d := D[i]
		if d < 0.05 or (has_clip and not clip.call(lx, ly)):
			return
		var a := minf(max_, ceilf((1.0 - exp(-d * dens)) * 6.0) / 6.0)
		if a < 0.15:
			return
		var gy := B[i + W] - B[i - W]
		var gx := B[i + 1] - B[i - 1]
		var up := Px.clamp(0.5 + atan((gy * 0.9 + gx * 0.35) / (B[i] * 0.16 + 0.03)) * 0.42 * lit)
		var w := F[i] / d
		var j := int(Px.clamp(Px.round((L[i] / d) * (0.3 + 0.7 * up) * (n - 1) + 0.25 + w * 1.5), 0.0, n - 1))
		var c: Variant = R[j]
		if w > 0.03:
			var m := j * 10 + mini(9, int(ceilf(w * 10.0)))
			c = mixed[m]
			if c == null:
				c = Px.mix(R[j], WR[j], minf(0.9, ceilf(w * 10.0) / 10.0))
				mixed[m] = c
		p.blendPx(sx, sy, c, a))


## Simulated smoke for one-shots, drawn with cloud(): add({ x, y, vx, vy, r0, r1, life, a, b, warm, drag, rise,
## grow, curl, delay }). Puffs push out, slow (drag, 1/s), lift (rise, px/s²), sway, swell from r0 to r1, thin away
## and darken as they age; warm (fire light) fades fast; curl (rad/s) keeps turning a puff's heading, so a chain of
## them hooks round into a curl. puffs() gives the live list for cloud().
class Smoke extends RefCounted:
	var R: Px.Rng
	var list: Array = []
	var t := 0.0
	var count: int:
		get: return list.size()

	func _init(rng: Px.Rng) -> void:
		R = rng
		list = []
		t = 0.0

	func add(q: Dictionary) -> void:
		var o := {"vx": 0.0, "vy": 0.0, "drag": 2.5, "rise": 12.0, "grow": 2.0, "curl": 0.0, "a": 0.6, "b": 0.85, "warm": 0.0, "delay": 0.0, "age": 0.0, "seed": R.next() * 100.0}
		o.merge(q, true)
		list.append(o)

	func update(dt: float) -> void:
		t += dt
		var i := list.size() - 1
		while i >= 0:
			var q: Dictionary = list[i]
			if q.delay > 0.0:
				q.delay -= dt
				i -= 1
				continue
			q.age += dt
			if q.age >= q.life:
				list.remove_at(i)
				i -= 1
				continue
			if q.curl:
				var c: float = cos(q.curl * dt)
				var s: float = sin(q.curl * dt)
				var vx: float = q.vx
				q.vx = vx * c - q.vy * s
				q.vy = vx * s + q.vy * c
			q.vy -= q.rise * dt
			q.vx += sin(t * 1.3 + q.seed) * 8.0 * dt
			q.vx -= q.vx * q.drag * dt
			q.vy -= q.vy * q.drag * dt
			q.x += q.vx * dt
			q.y += q.vy * dt
			i -= 1

	func puffs() -> Array:
		var out := []
		for q: Dictionary in list:
			if q.delay > 0.0:
				continue
			var k: float = q.age / q.life
			out.append({"x": q.x, "y": q.y, "r": q.r0 + (q.r1 - q.r0) * (1.0 - exp(-q.grow * q.age)), "a": q.a * minf(1.0, q.age * 30.0) * pow(1.0 - k, 1.3), "b": q.b * (1.0 - k * 0.5), "w": q.warm * exp(-q.age * 5.0)})
		return out


# a box blur of radius r along one axis of a w x h field (step 1 for rows, w for columns)
static func blur(src: PackedFloat32Array, w: int, h: int, step: int, r: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	var n := w if step == 1 else h
	var lines := h if step == 1 else w
	var k := 1.0 / (2 * r + 1)
	for l in lines:
		var base := l * w if step == 1 else l
		var acc := 0.0
		for j in range(-r, r + 1):
			acc += src[base + j * step] if (j >= 0 and j < n) else 0.0
		for j in n:
			out[base + j * step] = acc * k
			var a := j - r
			var b := j + r + 1
			if a >= 0:
				acc -= src[base + a * step]
			if b < n:
				acc += src[base + b * step]
	return out


## A spark: a two-tone streak stretched along its screen velocity, its head cooling down S (hot, warm, cool,
## tail colors) as k (life left, 1..0) falls, with a point of light.
static func spark(p: Px.Painter, x: float, y: float, vx: float, vy: float, k: float, S: Array, glow: float = 0.45, stretch: float = 0.022, max_: float = 9.0) -> void:
	var sp := Px.hypot(vx, vy)
	if not sp:
		sp = 1.0
	var ux := vx / sp
	var uy := vy / sp
	var len := minf(max_, 1.0 + sp * stretch)
	var head: int = S[0] if k > 0.6 else (S[1] if k > 0.3 else S[2])
	p.line(x - ux * len, y - uy * len, x - ux * len * 0.4, y - uy * len * 0.4, head if k > 0.5 else S[3])
	p.line(x - ux * len * 0.45, y - uy * len * 0.45, x, y, head)
	p.glow(x, y, 3.0, head, glow * k)


## The lobes of one muzzle flash, drawn from rng r: a fat fireball at the muzzle, a spike forward, and a burst of
## rays round it, longest forward, shortest blown back, each side on its own (diagonals, crossways, back),
## so every shot is a different spiky star. Frame f 2 is the same shape cooled, shorter and thinner; the same r
## sequence gives the same shape, so a shot keeps its shape across its frames.
## opts: { size = 1, spike = [12, 20], diag = [5, 10], cross = [3, 6], back = [2, 4.5], core = 0.7 }
static func flashShape(r: Px.Rng, f: float, opts: Dictionary = {}) -> Array:
	var size: float = opts.get("size", 1.0)
	var spike: Array = opts.get("spike", [12.0, 20.0])
	var diag: Array = opts.get("diag", [5.0, 10.0])
	var cross: Array = opts.get("cross", [3.0, 6.0])
	var back: Array = opts.get("back", [2.0, 4.5])
	var core: float = opts.get("core", 0.7)
	var k := 1.0 if f == 1 else 0.6
	var w := 1.0 if f == 1 else 0.72
	var S := size
	var L := [
		{"off": 0.5, "a": r.range(-0.08, 0.08), "len": r.range(5.5, 8.0) * S * k, "wid": r.range(2.1, 2.6) * S * w, "core": 0.5 * core},
		{"off": 2.0, "a": r.range(-0.07, 0.07), "len": r.range(spike[0], spike[1]) * S * k, "wid": r.range(1.0, 1.3) * S * w, "core": 0.35 * core},
	]
	var ray := func(a: float, len: float, wid: float, on: bool) -> void:
		if on:
			L.append({"off": r.range(0.5, 2.0), "a": a, "len": len * S * k, "wid": wid * S * w, "core": 0.25 * core})
	for s in [-1.0, 1.0]:
		ray.call(s * r.range(0.3, 0.8), r.range(diag[0], diag[1]), r.range(1.1, 1.5), r.chance(0.85))
		ray.call(s * r.range(1.15, 1.7), r.range(cross[0], cross[1]), r.range(1.0, 1.3), r.chance(0.6))
		ray.call(s * r.range(2.0, 2.7), r.range(back[0], back[1]), 1.0, r.chance(0.7) and f == 1)
	return L


static func profile(l: Dictionary, u: float) -> float:
	var k: float = u / l.len
	return l.wid * pow(maxf(0.0, 1.0 - k), 0.8) * minf(1.0, 0.45 + k * 3.0)


## Draw flash lobes L at (x, y) pointing along angle a: a white (or hot) core, a hot inner flame, a body and
## a ragged rim, chosen by how deep a pixel sits inside its lobe. C: [core, inner, body, rim]. seed varies the
## ragged edge. Returns the flash's reach.
static func flash(p: Px.Painter, x: float, y: float, a: float, L: Array, C: Array, seed: Variant) -> float:
	var c := cos(a)
	var s := sin(a)
	var ext := 2.0
	for l: Dictionary in L:
		ext = maxf(ext, l.off + l.len + 2.0)
	p.shade(x - ext, y - ext, x + ext, y + ext, func(px: float, py: float) -> Variant:
		var dx := px - x
		var dy := py - y
		var along := dx * c + dy * s
		var across := -dx * s + dy * c
		var m := -9.0
		var hot := false
		var warm := false
		for l: Dictionary in L:
			var ca: float = cos(l.a)
			var sa: float = sin(l.a)
			var lu: float = (along - l.off) * ca + across * sa
			var lv: float = -(along - l.off) * sa + across * ca
			if lu < -1.5 or lu > l.len + 1.0:
				continue
			var r := Self.profile(l, maxf(0.0, lu))
			var mm := r - absf(lv)
			if mm > m:
				m = mm
			if lu < l.len * l.core and absf(lv) <= r * 0.5:
				hot = true
			if mm > r * 0.4:
				warm = true
		var dm := 1.6 - Px.hypot(along - 0.5, across)
		if dm > m:
			m = dm
		if dm > 0.6:
			hot = true
		m += (Px.rand(floorf(px) * 73.0 + floorf(py) * 151.0, seed) - 0.5) * 0.5 * minf(1.0, ext / 14.0)
		if m < -0.85:
			return null
		return C[3] if m < 0.0 else (C[0] if hot else (C[1] if warm else C[2])))
	return ext


## A brass casing thrown from (x, y) at (vx, vy) with spin va, falling under g onto a floor at y = floor:
## it bounces (keeping `bounce` of its speed) until it's too slow, then slides to a stop. Closed form, so a
## loop can draw it at any age. Returns { x, y, a (angle), rest, hit (seconds since the last bounce, or -1) }.
static func casing(x: float, y: float, vx: float, vy: float, va: float, age: float, g: float, floor_: float, bounce: float = 0.42, a0: float = 0.0) -> Dictionary:
	var t0 := 0.0
	var a := a0
	var hit := -1.0
	for n in 6:
		# time to reach the floor from (x, y) moving (vx, vy)
		var d := floor_ - y
		var T := (-vy + sqrt(maxf(0.0, vy * vy + 2.0 * g * d))) / g
		if age - t0 < T:
			var u := age - t0
			return {"x": x + vx * u, "y": y + vy * u + 0.5 * g * u * u, "a": a + va * u, "rest": false, "hit": hit}
		x += vx * T
		a += va * T
		t0 += T
		hit = age - t0
		var vin := vy + g * T
		y = floor_
		if vin * bounce < 45.0:
			# too slow to hop again: slide to a stop, settling flat
			var u := age - t0
			var k := 7.0
			var s := (1.0 - exp(-k * u)) / k
			return {"x": x + vx * 0.6 * s, "y": floor_, "a": Px.round(a / PI) * PI, "rest": true, "hit": hit}
		vy = -vin * bounce
		vx *= 0.55
		va *= 0.6
	return {"x": x, "y": floor_, "a": Px.round(a / PI) * PI, "rest": true, "hit": hit}


## Draw a casing: a 3 px brass slug turned by its angle, lit on one end; a glint when it has just hit.
static func drawCasing(p: Px.Painter, k: Dictionary, B: Array, fade: float = 1.0) -> void:
	var ca: float = cos(k.a)
	var sa: float = sin(k.a)
	var x: float = k.x
	var y: float = k.y - 0.5
	p.dot(x - ca, y - sa, B[1], fade)
	p.dot(x, y, B[2], fade)
	p.dot(x + ca, y + sa, B[3], fade)
	if k.hit >= 0.0 and k.hit < 0.07:
		p.px(x + ca * 0.5, y - 1.0, WHITE)
		p.glow(x, y, 5.0, B[3], 0.55 * (1.0 - k.hit / 0.07))


## A little sprite (rows of characters, pal mapping them to colors, "." empty) turned by ang about its pivot
## (px, py in sprite pixels) placed at (x, y), sampled nearest-pixel so it stays hard-edged at any angle.
static func turnSprite(p: Px.Painter, rows: Array, pal: Dictionary, x: float, y: float, ang: float, px: float, py: float, a: float = 1.0) -> void:
	var H := rows.size()
	var W: int = String(rows[0]).length()
	var cs := cos(ang)
	var sn := sin(ang)
	var R := Px.hypot(maxf(px, W - px), maxf(py, H - py)) + 1.0
	p.shade(x - R, y - R, x + R, y + R, func(lx: float, ly: float, out: Variant) -> void:
		var dx := lx - x
		var dy := ly - y
		var i := floori(dx * cs + dy * sn + px)
		var j := floori(-dx * sn + dy * cs + py)
		if i < 0 or j < 0 or i >= W or j >= H:
			return
		var c: Variant = pal.get(String(rows[j])[i])
		if not c:
			return
		out.c = c
		out.a = a)


## A pixel shape from a builder: build(set) calls set(px, py, ch) for every interior pixel; an outline ('o')
## is added round it. Returns { rows, x0, y0 } ready for p.sprite at (x0, y0).
static func pixelShape(x0: int, y0: int, w: int, h: int, build: Callable) -> Dictionary:
	var g := []
	for _j in h:
		var row := []
		row.resize(w)
		row.fill(".")
		g.append(row)
	var set_ := func(px: int, py: int, ch: String) -> void:
		var i := px - x0
		var j := py - y0
		if i >= 0 and j >= 0 and i < w and j < h:
			g[j][i] = ch
	build.call(set_)
	var solid := func(i: int, j: int) -> bool:
		return i >= 0 and j >= 0 and i < w and j < h and g[j][i] != "." and g[j][i] != "o"
	for j in h:
		for i in w:
			if g[j][i] == "." and (solid.call(i - 1, j) or solid.call(i + 1, j) or solid.call(i, j - 1) or solid.call(i, j + 1)):
				g[j][i] = "o"
	return {"rows": g.map(func(r: Array) -> String: return "".join(PackedStringArray(r))), "x0": x0, "y0": y0}
