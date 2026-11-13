# port-of: src/fx/moves/fireball-throw.js@d65a6201b1e6ca516865e3cbe47ccfc6e7e9d8e5
extends RefCounted

const Px := preload("../../core/px.gd")
const Charge := preload("../arcane/spell-charge.gd")
const Fireball := preload("../fire/fireball.gd")
const Blast := preload("../explosions/small-explosion.gd")

const THROW := 0.95
const FLY := 0.46
const HIT := THROW + FLY
const SPEED := 340
const TX := 190

static var meta := {
	"name": "Fireball throw",
	"desc": "He gathers fire in his hand, leans back and hurls it: the ball flies, the target takes it in a blast and comes out charred.",
	"tags": ["move", "fire", "spell", "projectile", "explosion", "one-shot"],
	"size": [356, 244],
	"origin": [64, 198],
	"duration": HIT + 5.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"seed": 1},
}

static var HOLD := Px.merge(Px.READY, {"x": -3, "crouch": 4, "lean": 2, "fx": 18, "fy": -22, "bx": 11, "by": -17, "ffx": 10, "fbx": -8})
static var THROWN := Px.merge(Px.READY, {"x": 9, "crouch": 4, "lean": 6, "fx": 19, "fy": -22, "bx": -6, "by": -24, "ffx": 13, "fbx": -10, "toeB": true})
const FLINCH := {"turn": 0.9, "x": 7, "crouch": 5, "lean": -3, "fx": -4, "fy": -36, "bx": 5, "by": -33, "ffx": 4, "fbx": -4}
static var act := {
	"target": {"x": TX},
	"poses": [
		[-0.42, Px.merge(Px.READY, {"x": -3})],
		[0.08, Px.merge(HOLD)],
		[0.5, HOLD],
		[THROW - 0.03, Px.merge(HOLD, {"crouch": 5, "lean": -2, "fx": 17, "bx": 5, "by": -20})],
		[THROW, THROWN, "snap"],
		[HIT - 0.02, Px.merge(THROWN, {"crouch": 3, "lean": 4})],
		[HIT, FLINCH, "snap"],
		[HIT + 0.7, Px.merge(FLINCH, {"crouch": 3, "lean": -2})],
		[HIT + 1.4, Px.merge(Px.READY, {"x": 4})],
		[HIT + 2.1, Px.merge(Px.READY, {"x": -3})],
		[HIT + 5.4, Px.merge(Px.READY, {"x": -3})],
	],
	"hits": [
		{"t": HIT, "stop": 0.18, "shake": 0.38, "amp": 3, "push": 3.4, "straw": 34, "skin": "char"},
		{"t": HIT + 4.8, "push": 0, "straw": 0, "flash": 0, "skin": null},
	],
	"dust": [{"t": THROW, "x": 13, "n": 7, "dir": 1}],
}

static var CHAIN := Px.chain([
	{"fx": Charge, "t": 0.08, "until": THROW, "palette": Px.PAL.fire},
	{"fx": Fireball, "t": THROW, "until": HIT, "x": func(t): return 28 + (t - THROW) * SPEED, "y": -22},
	{"fx": Blast, "t": HIT, "x": TX},
])
static func create(o: Dictionary): return CHAIN.create(o)
