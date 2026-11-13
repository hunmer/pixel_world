# The coin's spin (squashed toward its edge), glints and burst of light, and the soft smoke of the poof, follow
# Sprite Fusion's open-source pickup (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/spawn/coin-drop.js@82bdaf0e54c7d35a6f400ce69839830121e82415
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Coin drop",
	"desc": "An enemy goes up in a soft poof and gold coins spin out of it, bounce with a glint on each hit, settle on the floor, twinkle, and wink out one by one.",
	"tags": ["spawn", "death", "loot", "coins", "gold", "drop", "pickup", "ground", "one-shot"],
	"size": [160, 88],
	"origin": [80, 78],
	"duration": 3,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#2a1606", "#5c3208", "#9a5a0c", "#d48c14", "#f5b82a", "#ffe066", "#fff6c4", "#ffffff"],
		"smoke": ["#3a3450", "#6c6688", "#a8a2c0", "#dcd8ea"],
		"coins": 7,
		"seed": 23,
	},
}

const CY := -16.0
# an original coin: a rim, a lit face, a raised mark in the middle
const COIN := ["..oooo..", ".ohhlmo.", "ohlmmmdo", "ohmdhmdo", "olmdhmdo", "olmmmmdo", ".oddddo.", "..oooo.."]
# lying flat on the floor, seen from the side
const FLAT := [".lhhhl.", "olmmmdo", ".odddo."]

var C: Array
var SM: Array
var R: Px.Rng
var PAL: Dictionary
var ps: Px.Particles
var lights: Px.Lights
var coins: Array = []
var balls: Array = []
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	SM = Px.fit(o.smoke, 4)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	PAL = {"o": C[1], "h": C[6], "l": C[5], "m": C[4], "d": C[3]}
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [WHITE, C[6], C[5], C[3]]})
	lights = Px.Lights.new()
	# the poof the enemy goes up in
	for i in 10:
		var a := (i / 10.0) * TAU + R.range(-0.25, 0.25)
		var sp := R.range(60.0, 100.0)
		var life := R.range(0.55, 0.85)
		balls.append({"x": cos(a) * 2.0, "y": CY + sin(a) * 2.0, "vx": cos(a) * sp, "vy": sin(a) * sp * 0.7 - 10.0, "r": R.range(4.0, 6.0), "life": life, "max": life})
	# the coins: thrown up and out, each spinning at its own rate
	var n: float = o.coins
	var i := 0
	while i < n:
		var u := i / (n - 1.0) - 0.5 if n > 1.0 else 0.0
		var a := -PI / 2.0 + u * 1.6 + R.range(-0.1, 0.1)
		var sp := R.range(230.0, 300.0)
		coins.append({"x": R.range(-3.0, 3.0), "y": CY, "vx": cos(a) * sp * 0.4, "vy": sin(a) * sp, "ph": R.range(0.0, TAU), "w": R.range(9.0, 15.0) * R.sign(), "rest": false, "hits": 0, "out": 2.15 + i * 0.07 + R.range(0.0, 0.1), "glint": R.range(1.2, 1.9), "born": R.range(0.04, 0.12)})
		i += 1
	for j in 8:
		var a := R.range(0.0, TAU)
		var sp := R.range(50.0, 120.0)
		ps.spawn(P.STAR, 0.0, CY, cos(a) * sp, sin(a) * sp - 20.0, R.range(0.3, 0.6), R.pick([WHITE, C[6], C[5]]), R.range(0.8, 1.8))
	lights.add(0.0, CY, 44.0, C[4], 0.7, 0.4)
	lights.add(0.0, CY, 20.0, WHITE, 0.7, 0.1)


# a coin turning in the air: its face squashed toward the edge, the rim showing when it's side-on
func drawCoin(p: Px.Painter, x: float, y: float, ph: float) -> void:
	var c := cos(ph)
	var sx := absf(c)
	if sx < 0.28:
		for dy in range(-3, 4):
			p.px(x, y + dy, C[1] if absi(dy) == 3 else (C[6] if dy < 0 else C[5]))
		if sx > 0.12:
			for dy in range(-2, 3):
				p.px(x + (1.0 if c > 0.0 else -1.0), y + dy, C[3])
		return
	var half := 4.0 * sx
	for px in range(floori(x - half), ceili(x + half)):
		var col := floori((px + 0.5 - x) / sx + 4.0)
		if col < 0 or col > 7:
			continue
		if c < 0.0:
			col = 7 - col
		for row in 8:
			var ch: String = COIN[row][col]
			if ch != ".":
				p.px(px, Px.round(y - 4.0 + row), PAL[ch])


func update(dt: float) -> void:
	t += dt
	var i := balls.size() - 1
	while i >= 0:
		var b: Dictionary = balls[i]
		b.life -= dt
		if b.life <= 0.0:
			balls.remove_at(i)
			i -= 1
			continue
		b.vx -= b.vx * 7.0 * dt
		b.vy -= b.vy * 7.0 * dt + 26.0 * dt
		b.x += b.vx * dt
		b.y += b.vy * dt
		i -= 1
	for c in coins:
		# a coin winks out with a little burst of gold
		if not c.get("gone", false) and t >= c.out:
			c.gone = true
			for j in 5:
				var a := R.range(-PI, 0.0)
				var sp := R.range(25.0, 60.0)
				ps.spawn(P.STAR, c.x, -3.0, cos(a) * sp, sin(a) * sp, R.range(0.3, 0.55), R.pick([WHITE, C[6], C[5]]), R.range(0.7, 1.4))
			lights.add(c.x, -3.0, 14.0, C[5], 0.6, 0.2)
		if t < c.born or t > c.out or c.rest:
			continue
		c.vy += 820.0 * dt
		c.vx -= c.vx * 0.4 * dt
		c.x += c.vx * dt
		c.y += c.vy * dt
		c.ph += c.w * dt
		if c.y >= -1.5 and c.vy > 0.0:
			c.y = -1.5
			c.hits += 1
			# a tink of light and a puff of dust at each hit
			ps.spawn(P.STAR, c.x, -3.0, 0.0, -8.0, 0.25, WHITE, 2.2 if c.hits == 1 else 1.4)
			for j in 2:
				ps.spawn(P.DUST, c.x + R.range(-1.0, 1.0), -0.5, R.sign() * R.range(8.0, 24.0), -R.range(2.0, 8.0), R.range(0.25, 0.45), SM[1], R.range(1.0, 1.8))
			lights.add(c.x, -3.0, 12.0, C[5], 0.5, 0.15)
			if c.vy > 110.0:
				c.vy *= -0.45
				c.vx *= 0.7
				c.w = c.w * 0.8 + R.range(-2.0, 2.0)
			else:
				c.rest = true
				c.vy = 0.0
				c.vx = 0.0
				c.restAt = t
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# a warm gleam on the floor where the coins lie
	for c in coins:
		if c.rest and t < c.out:
			p.glow(c.x, -1.0, 7.0, C[4], 0.18)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	# the poof: soft, top-lit balls, a pop of light in the middle
	for layer in [0, 1, 2]:
		for b in balls:
			var age: float = b.max - b.life
			var k: float = b.life / b.max
			var r: float = b.r * (0.6 + 0.6 * Px.Ease.outCubic(Px.clamp(age / 0.2))) * (k / 0.35 if k < 0.35 else 1.0)
			if r < 0.6:
				continue
			if layer == 0:
				p.disc(b.x + r * 0.15, b.y + r * 0.2, r, SM[1], 0.8)
			elif layer == 1:
				p.disc(b.x - r * 0.06, b.y - r * 0.08, r * 0.86, SM[1] if b.y > CY + 2.0 else SM[2], 0.85)
			elif b.y < CY + 2.0:
				p.disc(b.x - r * 0.28, b.y - r * 0.34, r * 0.4, SM[3], 0.85)
	if t < 0.07:
		var k := t / 0.07
		p.circle(0.0, CY, 8.0 + 2.0 * k, C[6])
		p.circle(0.0, CY, 6.0 + 2.0 * k, WHITE)
		Px.flare(p, 0.0, CY, 16.0 * (1.0 - k * 0.5), 1.0 - k, C)
	for c in coins:
		if t < c.born or t > c.out + 0.12:
			continue
		if t > c.out:
			# a coin winks out with a last flash and a ring
			var k: float = (t - c.out) / 0.12
			Px.sparkle(p, c.x, -2.0, Px.round(5.0 * (1.0 - k)), WHITE, C[5], 0.5)
			p.ring(c.x, -3.0, 2.0 + 5.0 * Px.Ease.outCubic(k), 1.0, C[6], 1.1 - k)
			continue
		if c.rest:
			# flat on the floor; now and then a glint runs over it
			p.sprite(FLAT, PAL, Px.round(c.x) - 3.0, -3.0)
			p.glow(c.x, -2.0, 6.0, C[5], 0.25)
			var g: float = fmod(t - c.restAt + c.glint, 0.95) / 0.95
			if g < 0.2:
				Px.sparkle(p, c.x - 1.0, -3.0, Px.round(3.0 * sin((g / 0.2) * PI)), WHITE, C[5], 0.4)
		else:
			drawCoin(p, c.x, c.y, c.ph)
			p.glow(c.x, c.y, 8.0, C[4], 0.3)
			# a glint catches the face as it turns toward us
			if absf(cos(c.ph)) > 0.96:
				p.px(c.x - 1.0, c.y - 2.0, WHITE)
	ps.draw(p, "front")
	lights.draw(p)
