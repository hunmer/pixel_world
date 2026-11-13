# port-of: src/fx/moves/arrow-shot.js@e1c4ae18c7e9234709f936ed31a8790c47f35100
extends RefCounted

const Px := preload("../../core/px.gd")
const Arrow := preload("../projectiles/arrow.gd")
const Spark := preload("../impacts/hit-spark.gd")

const LOOSE := 0.56
const FLY := 0.24
const HIT := LOOSE + FLY
const TX := 180
const SPEED := (TX - 30) / FLY

static var meta := {
	"name": "Arrow shot",
	"desc": "He raises the bow, draws to his cheek, holds his breath and looses: the string snaps forward, the arrow crosses the floor and thuds home.",
	"tags": ["move", "bow", "arrow", "projectile", "ranged", "one-shot"],
	"size": [300, 74],
	"origin": [38, 66],
	"duration": 1.9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"seed": 1},
}

static var REST_ := Px.merge(Px.READY, {"weapon": "bow", "sa": -0.4, "fx": 12, "fy": -20, "bx": 6, "by": -17})
static var AIM := Px.merge(REST_, {"crouch": 3, "lean": 1, "fx": 18, "fy": -28, "sa": 0, "bx": 10, "by": -27, "nocked": true, "ffx": 11, "fbx": -9})
static var DRAWN := Px.merge(AIM, {"crouch": 4, "lean": -2, "fx": 18, "bx": -3, "by": -29, "pull": true})
static var LOOSED := Px.merge(AIM, {"crouch": 3, "lean": 2, "fx": 19, "fy": -28, "bx": -9, "by": -32, "nocked": false, "pull": false})
static var act := {
	"target": {"x": TX},
	"poses": [
		[-0.44, REST_],
		[-0.14, AIM],
		[0.16, DRAWN],
		[LOOSE, Px.merge(DRAWN, {"crouch": 4})],
		[LOOSE + 0.002, LOOSED, "snap"],
		[1.1, Px.merge(LOOSED, {"bx": -6, "by": -25})],
		[1.6, REST_],
		[1.9, REST_],
	],
	"hits": [{"t": HIT, "stop": 0.07, "shake": 0.12, "amp": 2, "push": 2.2, "straw": 14, "y": -28}],
}

static var CHAIN := Px.chain([
	{"fx": Arrow, "t": LOOSE, "until": HIT, "x": func(t): return 30 + (t - LOOSE) * SPEED, "y": -28},
	{"fx": Spark, "t": HIT, "x": TX - 10, "height": 30},
])
static func create(o: Dictionary): return CHAIN.create(o)
