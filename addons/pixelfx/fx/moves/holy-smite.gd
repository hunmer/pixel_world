# port-of: src/fx/moves/holy-smite.js@8afbf29ad647f73d7d5c16c59cf9d950c09390f7
extends RefCounted

const Px := preload("../../core/px.gd")
const Smite := preload("../holy/smite.gd")

const BOLT := 0.47
const TX := 118

static var meta := {
	"name": "Holy smite",
	"desc": "Both hands go up and a glint marks the target; he brings them down and a bolt of light drops like a hammer, leaving the target blanched.",
	"tags": ["move", "holy", "spell", "strike", "one-shot"],
	"size": [252, 182],
	"origin": [42, 151],
	"duration": 2.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"seed": 1},
}

const UP := {"turn": 1.15, "crouch": -1, "fx": -7, "fy": -44, "bx": 8, "by": -44, "ffx": -3, "fbx": 4}
static var DOWN := Px.merge(Px.READY, {"crouch": 5, "lean": 5, "fx": 17, "fy": -29, "bx": 13, "by": -25, "ffx": 12, "fbx": -10, "toeB": true})
static var act := {
	"target": {"x": TX},
	"poses": [
		[-0.42, Px.READY],
		[-0.04, UP],
		[BOLT - 0.01, Px.merge(UP, {"y": -1})],
		[BOLT, DOWN, "snap"],
		[1.1, Px.merge(DOWN, {"crouch": 3, "lean": 3})],
		[1.7, Px.READY],
		[2.8, Px.READY],
	],
	"hits": [
		{"t": BOLT, "stop": 0.14, "shake": 0.32, "amp": 3, "push": 2.8, "straw": 24, "skin": "holy", "y": -30},
		{"t": 2.3, "push": 0, "straw": 0, "flash": 0, "skin": null},
	],
	"dust": [{"t": BOLT, "x": 14, "n": 6, "dir": 1}],
}

static var CHAIN := Px.chain([{"fx": Smite, "t": 0, "x": TX}])
static func create(o: Dictionary): return CHAIN.create(o)
