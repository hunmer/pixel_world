# port-of: src/fx/moves/dash-strike.js@9d2c7d8aeb053fd4afc94a78bae03725912b3580
extends RefCounted

const Px := preload("../../core/px.gd")
const Slash := preload("../melee/sword-slash.gd")
const Crit := preload("../impacts/crit-hit.gd")

const CUT := 0.16
const HIT := CUT + 0.06
const AT := 116
const TX := 176

static var meta := {
	"name": "Dash strike",
	"desc": "A crouch, then he's across the floor in a blur of after-images and already cutting: a critical hit, a beat, and he hops back to where he started.",
	"tags": ["move", "melee", "sword", "dash", "crit", "one-shot"],
	"size": [372, 156],
	"origin": [66, 136],
	"duration": 2.3,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"seed": 1},
}

static var GUARD := Px.merge(Px.READY, {"weapon": "sword", "fx": 12, "fy": -21, "sa": -0.85})
static var LOW := Px.merge(GUARD, {"crouch": 6, "lean": 6, "fx": -3, "fy": -17, "sa": 3.05, "bx": 9, "by": -23, "ffx": 11, "fbx": -10})
static var COCK := Px.merge(GUARD, {"x": AT - 4, "crouch": 3, "lean": -2, "fx": -7, "fy": -35, "sa": -2.65, "bx": 9, "by": -25, "armsFront": true, "ffx": 9, "fbx": -7})
static var CUT_ := Px.merge(GUARD, {"x": AT, "crouch": 2, "lean": 3, "fx": 16, "fy": -37, "sa": -1.45, "bx": -7, "by": -24, "ffx": 11, "fbx": -10})
static var DOWN := Px.merge(GUARD, {"x": AT + 2, "crouch": 5, "lean": 5, "fx": 20, "fy": -21, "sa": 0.62, "bx": -9, "by": -24, "ffx": 13, "fbx": -10, "toeB": true})
static var HOP := Px.merge(GUARD, {"y": -14, "crouch": 0, "lean": -3, "fx": 13, "fy": -31, "sa": -0.9, "bx": -8, "by": -28, "ffx": 6, "ffy": -8, "fbx": -6, "fby": -6, "ghost": 1})
static var act := {
	"target": {"x": TX},
	"poses": [
		[-0.5, Px.merge(GUARD, {"x": 0})],
		[-0.16, Px.merge(LOW, {"x": -2})],
		[-0.01, Px.merge(LOW, {"x": -3, "crouch": 6})],
		[0, Px.merge(LOW, {"x": 8, "ghost": 1}), "snap"],
		[0.14, Px.merge(LOW, {"x": AT - 6, "ghost": 1}), "line"],
		[0.145, COCK, "snap"],
		[CUT, CUT_, "snap"],
		[HIT, DOWN, "snap"],
		[0.75, Px.merge(DOWN, {"crouch": 4, "lean": 4})],
		[1.25, Px.merge(GUARD, {"x": AT + 2})],
		[1.32, Px.merge(GUARD, {"x": AT + 2, "crouch": 5, "lean": -2}), "snap"],
		[1.4, Px.merge(HOP, {"x": AT - 28}), "snap"],
		[1.6, Px.merge(HOP, {"x": 22, "y": -18}), "line"],
		[1.74, Px.merge(GUARD, {"x": 0, "y": 0, "crouch": 5}), "line"],
		[2.2, Px.merge(GUARD, {"x": 0})],
	],
	"hits": [{"t": HIT, "stop": 0.17, "shake": 0.26, "amp": 3, "push": 3.4, "straw": 32}],
	"dust": [{"t": 0, "x": 0, "n": 8, "dir": -1}, {"t": 0.14, "x": AT - 6, "n": 7}, {"t": 1.74, "x": 0, "n": 6}],
}

static var CHAIN := Px.chain([
	{"fx": Slash, "t": CUT, "x": AT},
	{"fx": Crit, "t": HIT, "x": TX - 10, "height": 28},
])
static func create(o: Dictionary): return CHAIN.create(o)
