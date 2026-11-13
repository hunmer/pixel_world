# port-of: src/fx/moves/meteor-call.js@434a9b5e14c9de8ed7ffa8e7f2b7fa7a35c6d7fe
extends RefCounted

const Px := preload("../../core/px.gd")
const Circle := preload("../arcane/magic-circle-cast.gd")
const Meteor := preload("../fire/meteor.gd")

const BOLT := 1.52
const HIT := 2.05
const TX := 170

static var meta := {
	"name": "Meteor call",
	"desc": "A long chant: a circle draws itself round him, it flares, he points, and a burning rock comes down on the target and flattens the scene.",
	"tags": ["move", "fire", "spell", "meteor", "ultimate", "one-shot"],
	"size": [380, 240],
	"origin": [92, 212],
	"duration": HIT - 0.62 + 5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"seed": 1},
}

const CHANT := {"turn": 1.1, "crouch": 1, "fx": -1, "fy": -26, "bx": 2, "by": -26, "armsFront": true, "hy": 1, "ffx": -3, "fbx": 4}
const UP := {"turn": 1.15, "crouch": -1, "fx": -7, "fy": -44, "bx": 8, "by": -44, "ffx": -3, "fbx": 4}
static var POINT := Px.merge(Px.READY, {"crouch": 3, "lean": 5, "fx": 17, "fy": -37, "bx": -6, "by": -24, "ffx": 12, "fbx": -9, "toeB": true})
const FLINCH := {"turn": 0.9, "x": -3, "crouch": 6, "lean": -4, "fx": -4, "fy": -36, "bx": 5, "by": -33, "ffx": 4, "fbx": -4}
static var act := {
	"target": {"x": TX},
	"poses": [
		[-0.34, Px.READY],
		[0, CHANT],
		[0.75, Px.merge(CHANT, {"crouch": 2})],
		[1.4, UP],
		[BOLT - 0.02, Px.merge(UP, {"y": -1})],
		[BOLT, POINT, "snap"],
		[HIT - 0.02, Px.merge(POINT, {"crouch": 3})],
		[HIT, FLINCH, "snap"],
		[HIT + 0.9, Px.merge(FLINCH, {"crouch": 3, "lean": -2})],
		[HIT + 1.7, Px.merge(Px.READY, {"x": 0})],
		[HIT + 4.3, Px.READY],
	],
	"hits": [
		{"t": BOLT, "stop": 0.06, "shake": 0.16, "amp": 2, "target": false},
		{"t": HIT, "stop": 0.22, "shake": 0.55, "amp": 4, "push": 3.8, "straw": 44, "skin": "char"},
		{"t": HIT + 3.9, "push": 0, "straw": 0, "flash": 0, "skin": null},
	],
}

static var CHAIN := Px.chain([
	{"fx": Circle, "t": 0},
	{"fx": Meteor, "t": HIT - 0.62, "x": TX},
])
static func create(o: Dictionary): return CHAIN.create(o)
