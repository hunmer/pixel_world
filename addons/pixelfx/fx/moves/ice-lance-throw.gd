# port-of: src/fx/moves/ice-lance-throw.js@08361a8fd7dc4188445161a1cf07b32b01f85825
extends RefCounted

const Px := preload("../../core/px.gd")
const Charge := preload("../arcane/spell-charge.gd")
const Lance := preload("../ice/ice-lance.gd")
const Burst := preload("../ice/snowflake-burst.gd")

const THROW := 0.8
const FLY := 0.34
const HIT := THROW + FLY
const TX := 170
const SPEED := (TX - 34) / FLY

static var meta := {
	"name": "Ice lance throw",
	"desc": "Frost gathers into a spear in his hand, he throws it like a javelin, and the target ices over in a burst of snowflakes and shivers.",
	"tags": ["move", "ice", "spell", "projectile", "one-shot"],
	"size": [310, 136],
	"origin": [86, 134],
	"duration": HIT + 3.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"seed": 1},
}

static var HOLD := Px.merge(Px.READY, {"x": -3, "crouch": 4, "lean": 2, "fx": 18, "fy": -22, "bx": 11, "by": -17, "ffx": 10, "fbx": -8})
static var THROWN := Px.merge(Px.READY, {"x": 9, "crouch": 4, "lean": 6, "fx": 19, "fy": -24, "bx": -6, "by": -24, "ffx": 13, "fbx": -10, "toeB": true})
static var act := {
	"target": {"x": TX},
	"poses": [
		[-0.4, Px.merge(Px.READY, {"x": -3})],
		[0.06, Px.merge(HOLD)],
		[THROW - 0.2, HOLD],
		[THROW - 0.03, Px.merge(HOLD, {"crouch": 5, "lean": -2, "fx": 17, "bx": 5, "by": -20})],
		[THROW, THROWN, "snap"],
		[HIT + 0.3, Px.merge(THROWN, {"crouch": 3, "lean": 4})],
		[HIT + 0.9, Px.merge(Px.READY, {"x": -3})],
		[HIT + 3.2, Px.merge(Px.READY, {"x": -3})],
	],
	"hits": [
		{"t": HIT, "stop": 0.13, "shake": 0.2, "amp": 2, "push": 2.4, "straw": 12, "skin": "ice", "shiver": 1.4, "y": -26},
		{"t": 2.75, "push": 0.3, "straw": 0, "flash": 0, "skin": null},
	],
	"dust": [{"t": THROW, "x": 13, "n": 6, "dir": 1, "c": "#d8f2ff"}],
}

static var CHAIN := Px.chain([
	{"fx": Charge, "t": 0.06, "until": THROW, "palette": Px.PAL.ice},
	{"fx": Lance, "t": THROW, "until": HIT, "x": func(t): return 34 + (t - THROW) * SPEED, "y": -24},
	{"fx": Burst, "t": HIT, "x": TX, "y": -26},
])
static func create(o: Dictionary): return CHAIN.create(o)
