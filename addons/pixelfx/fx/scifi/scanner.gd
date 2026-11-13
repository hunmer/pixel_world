# port-of: src/fx/scifi/scanner.js@84d1d0e2cd5ca81e15025dcea84db441cadab3cc
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Scanner",
	"desc": "Brackets snap onto the hero, a scan line sweeps head to toe leaving a cooling outline, and a readout counts up to OK before it all lets go.",
	"tags": ["scifi", "scan", "target", "hud", "tech", "status", "ui", "loop"],
	"size": [112, 78],
	"origin": [42, 58],
	"duration": 3.2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#03140a", "#06301a", "#0c5a2c", "#16893e", "#2cc256", "#7cf08c", "#d0ffd4", "#ffffff"], "seed": 22},
}

static var STIFF := {"turn": 0.9, "crouch": -1, "fx": -7, "fy": -14, "bx": 8, "by": -14, "ffx": -3, "fbx": 4}
static var OK_ := {"turn": 0.9, "fx": -9, "fy": -37, "bx": 8, "by": -15, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"poses": [
		[0, {}],
		[0.3, STIFF, "snap"],
		[1.75, STIFF],
		[1.85, OK_, "snap"],
		[2.5, OK_],
		[2.8, {}],
		[3.2, {}],
	],
}

static var D: float = meta.duration
const LOCK := 0.3
const SCAN0 := 0.42
const SCAN1 := 1.6
const DONE := 1.75
const LET := 2.5

# the body: its outline pixels by row, and each row's extent, worked out once per actor
static var bodies := {}


static func _actorKey(A: Dictionary) -> String:
	return "%s:%d:%d" % [A.mask.id, A.x, A.y]


static func body(A: Dictionary) -> Dictionary:
	var key := _actorKey(A)
	if bodies.has(key):
		return bodies[key]
	var m: Dictionary = A.mask
	var mw: int = m.w
	var mh: int = m.h
	var data: PackedByteArray = m.data
	var Ax: int = A.x
	var Ay: int = A.y
	var on := func(x: int, y: int) -> bool: return x >= 0 and y >= 0 and x < mw and y < mh and data[y * mw + x] != 0
	var edge := []
	var rows := {}
	for y in range(-1, mh + 1):
		for x in range(-1, mw + 1):
			if on.call(x, y):
				var r: Array = rows.get(Ay + y, [Ax + x, Ax + x])
				rows[Ay + y] = [mini(r[0], Ax + x), maxi(r[1], Ax + x)]
			elif on.call(x - 1, y) or on.call(x + 1, y) or on.call(x, y - 1) or on.call(x, y + 1):
				edge.append([Ax + x, Ay + y])
	var b := {"edge": edge, "rows": rows}
	bodies[key] = b
	return b


static func scanY(t: float, A: Dictionary) -> float:
	return Px.lerp(A.y - 3.0, 1.0, Px.Ease.inOutSine(Px.clamp((t - SCAN0) / (SCAN1 - SCAN0))))


static func scanT(y: float, A: Dictionary) -> float:
	return SCAN0 + ((SCAN1 - SCAN0) * acos(1.0 - 2.0 * Px.clamp((y + 0.5 - (A.y - 3.0)) / (4.0 - A.y)))) / PI


# an L-shaped bracket: two arms from a corner, a hot pixel at the corner
static func bracket(p: Px.Painter, x: float, y: float, sx: float, sy: float, L: float, c: int, hot: int, a: float) -> void:
	p.line(x, y, x + sx * L, y, c, a)
	p.line(x, y, x, y + sy * L, c, a)
	p.line(x + sx, y + sy, x + sx * 3.0, y + sy, c, a * 0.6)
	p.dot(x, y, hot, a)


static var ghostCache := {}


static func ghosts(o: Dictionary, A: Dictionary, C: Array) -> Lib.Ghosts:
	var key := "%s:%s" % [o.seed, o.palette]
	var akey := _actorKey(A)
	var byActor: Dictionary = ghostCache.get(akey, {})
	ghostCache[akey] = byActor
	if byActor.has(key):
		return byActor[key]
	var rows: Dictionary = body(A).rows
	var g := Lib.Ghosts.new(D, {"ground": func(): return 0.0, "box": [-40.0, -58.0, 68.0, 9.0]})
	# data bits flicked off the body's edges as the line crosses them
	var y: int = A.y
	while y < 0:
		var r: Variant = rows.get(y)
		if not r:
			y += 3
			continue
		for xs: Array in [[r[0] - 1, -1], [r[1] + 1, 1]]:
			var x: int = xs[0]
			var s: int = xs[1]
			if Px.rand(o.seed, y, s) < 0.6:
				g.add(scanT(y, A), P.MOTE, x, y, s * (30.0 + 50.0 * Px.rand(y, s, 3)), -10.0 + 20.0 * Px.rand(y, s, 4), 0.2 + 0.15 * Px.rand(y, s, 5), WHITE if Px.rand(y, s, 6) < 0.4 else C[5], 0.6)
		y += 3
	byActor[key] = g
	return g


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var A: Dictionary = o.actor
	var bd := body(A)
	var edge: Array = bd.edge
	var rows: Dictionary = bd.rows
	var Ax: int = A.x
	var Ay: int = A.y
	var Aw: int = A.w
	var data: PackedByteArray = A.mask.data
	# the box the brackets lock to, and how far out they are: closing in with a snap, letting go at the end
	var bx0 := Ax - 4.0
	var bx1 := Ax + Aw + 3.0
	var by0 := Ay - 4.0
	var by1 := 3.0
	var lock := Px.Ease.outBack(Px.clamp(t / LOCK), 2.2)
	var out := Px.Ease.inCubic(Px.clamp((t - LET) / 0.45))
	var spread := (1.0 - lock) * 14.0 + out * 12.0
	var gone := t > LET + 0.45 or (t > LET + 0.25 and floori((t - LET) * 20.0) % 2 == 1)
	var vis := 0.0 if gone else 1.0
	var flash := (t > LOCK and t < LOCK + 0.07) or (t > DONE and t < DONE + 0.05) or (t > DONE + 0.12 and t < DONE + 0.17)
	var bc: int = WHITE if flash else C[5]
	var L := 7.0
	if vis > 0.0:
		for br: Array in [[bx0 - spread, by0 - spread, 1.0, 1.0], [bx1 + spread, by0 - spread, -1.0, 1.0], [bx0 - spread, by1 + spread, 1.0, -1.0], [bx1 + spread, by1 + spread, -1.0, -1.0]]:
			bracket(p, br[0], br[1], br[2], br[3], L, bc, WHITE, vis)
			p.glow(br[0], br[1], 6.0, C[4], 0.35 * vis)
	# on lock: a box flashes out from the brackets
	var lk := (t - LOCK) / 0.3
	if lk >= 0.0 and lk < 1.0:
		var e := 3.0 + 10.0 * Px.Ease.outCubic(lk)
		var c: int = WHITE if lk < 0.25 else (C[6] if lk < 0.5 else (C[5] if lk < 0.75 else C[3]))
		p.line(bx0 - e, by0 - e, bx1 + e, by0 - e, c)
		p.line(bx0 - e, by1 + e, bx1 + e, by1 + e, c)
		p.line(bx0 - e, by0 - e, bx0 - e, by1 + e, c)
		p.line(bx1 + e, by0 - e, bx1 + e, by1 + e, c)
	# the outline, lit row by row as the line passes and cooling behind it
	var pulse := 1.0 - Lib.since(t, DONE, D) / 0.3 if Lib.since(t, DONE, D) < 0.3 else 0.0
	var offY := Px.lerp(Ay - 2.0, 2.0, Px.clamp((t - LET) / 0.4))
	if t > SCAN0:
		for xy: Array in edge:
			var x: int = xy[0]
			var y: int = xy[1]
			var a := t - scanT(y, A)
			if a < 0.0 or (t > LET and y < offY):
				continue
			var c: int = WHITE if pulse > 0.4 else (WHITE if a < 0.07 else (C[6] if a < 0.25 else (C[5] if a < 0.6 else (C[3] if t > LET - 0.3 else C[4]))))
			p.px(x, y, c)
	# the scan line and the slice of light just above it
	if t > SCAN0 and t < SCAN1:
		var y := floori(scanY(t, A))
		for k in range(1, 6):
			var r: Variant = rows.get(y - k)
			if r:
				for x in range(r[0], r[1] + 1):
					if data[(y - k - Ay) * Aw + x - Ax]:
						p.blend(x + 0.5, y - k + 0.5, C[6] if k < 2 else C[5], 0.55 - k * 0.09)
		var x := bx0 - 2.0
		while x <= bx1 + 2.0:
			var r: Variant = rows.get(y)
			var inside: bool = r != null and x >= r[0] and x <= r[1]
			p.px(x, y, WHITE if inside else C[6])
			p.blend(x + 0.5, y - 0.5, C[5], 0.35)
			x += 1.0
		p.glowLine(bx0, y, bx1, y, 6.0, C[5], 0.45)
		var r: Variant = rows.get(y)
		if r:
			for sx: float in [r[0] - 0.5, r[1] + 1.5]:
				Px.sparkle(p, sx, y + 0.5, 2.0, C[6], C[5], 0.3)
	# the readout: a leader from the top-right bracket to a panel, a count, a bar filling, then OK
	var lead := Px.clamp((t - LOCK) / 0.1)
	if vis > 0.0 and lead > 0.0:
		var px := bx1 + spread + 6.0
		var py := by0 - spread + 2.0
		var k := Px.clamp((t - SCAN0) / (SCAN1 - SCAN0))
		var ok := t > DONE
		p.line(bx1 + spread, by0 - spread, Px.lerp(bx1 + spread, px - 1.0, lead), Px.lerp(by0 - spread, py + 4.0, lead), C[3])
		if lead < 1.0:
			ghosts(o, A, C).at(t).draw(p)
			return
		p.line(px - 1.0, py + 4.0, px + 1.0, py + 4.0, C[3])
		var del := Px.clamp((t - LET) / 0.25)
		var full := "OK" if ok else "%d%%" % floori(k * 100.0)
		var label := full.substr(0, ceili(full.length() * (1.0 - del)))
		var blinkOk := ok and floori((t - DONE) * 8.0) % 2 == 0 and t < DONE + 0.5
		if label:
			p.text(label, px + 2.0, py, WHITE if blinkOk else C[6], {"font": "mini", "scale": 2, "shadow": C[1]})
		# the bar: ten cells filling as it goes, emptying from the right as it lets go
		for i in 10:
			if i >= 10.0 * (1.0 - del):
				break
			var on := (i + 1) / 10.0 <= k + 1e-6 or ok
			p.rect(px + 2.0 + i * 3, py + 13.0, 2.0, 3.0, (C[6] if ok else C[5]) if on else C[2])
		p.glow(px + 16.0, py + 6.0, 18.0, C[4], 0.2 * vis)
	ghosts(o, A, C).at(t).draw(p)
