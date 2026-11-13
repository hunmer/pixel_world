# port-of: src/fx/moves/earth-stomp.js@a4353ca12e4f51b6c6f0cb1f1e5978cbe6c0c877
extends RefCounted

const Px := preload("../../core/px.gd")
const Spike := preload("../nature/earth-spike.gd")

const STOMP := 0.06
const RAM := STOMP + 0.43
const TX := 112

static var meta := {
	"name": "Earth stomp",
	"desc": "A knee comes up, the boot slams down, the floor heaves under the target and a stone spike rams up through it.",
	"tags": ["move", "earth", "spell", "stomp", "one-shot"],
	"size": [290, 142],
	"origin": [50, 128],
	"duration": STOMP + 3.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"seed": 1},
}

static var KNEE := Px.merge(Px.READY, {"crouch": 1, "lean": -3, "fx": 3, "fy": -34, "bx": 11, "by": -30, "ffx": 9, "ffy": -15, "fbx": -5})
static var SLAM := Px.merge(Px.READY, {"crouch": 7, "lean": 3, "fx": 14, "fy": -14, "bx": -5, "by": -18, "ffx": 11, "fbx": -9})
static var act := {
	"target": {"x": TX},
	"poses": [
		[-0.5, Px.READY],
		[-0.14, KNEE],
		[STOMP - 0.005, Px.merge(KNEE, {"ffy": -17})],
		[STOMP, SLAM, "snap"],
		[RAM + 0.5, Px.merge(SLAM, {"crouch": 5})],
		[RAM + 1.1, Px.READY],
		[STOMP + 3.4, Px.READY],
	],
	"hits": [
		{"t": STOMP, "stop": 0.1, "shake": 0.2, "amp": 3, "target": false},
		{"t": RAM, "stop": 0.14, "shake": 0.28, "amp": 3, "push": -3.2, "straw": 30, "y": -10},
	],
	"dust": [{"t": STOMP, "x": 11, "n": 9}],
}

static var CHAIN := Px.chain([{"fx": Spike, "t": STOMP, "x": TX}])
static func create(o: Dictionary): return CHAIN.create(o)
