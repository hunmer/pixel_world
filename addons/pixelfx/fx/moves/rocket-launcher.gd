# port-of: src/fx/moves/rocket-launcher.js@2ac031c97efbfeb715d2b796911b3c0e86bcea23
extends RefCounted

const Px := preload("../../core/px.gd")
const Muzzle := preload("../projectiles/muzzle-shotgun.gd")
const Rocket := preload("../projectiles/rocket.gd")
const Blast := preload("../explosions/small-explosion.gd")

const FIRE := 0.6
const FLY := 0.56
const HIT := FIRE + FLY
const TX := 200
const MY := -21
const MX := 34

static var meta := {
	"name": "Rocket launcher",
	"desc": "He drops to one knee, shoulders the tube and fires: the kick shoves him back along the floor, the rocket crawls out on its jet and the target goes up.",
	"tags": ["move", "gun", "rocket", "projectile", "explosion", "one-shot"],
	"size": [480, 244],
	"origin": [178, 198],
	"duration": HIT + 5.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"seed": 1},
}

static var REST_ := Px.merge(Px.READY, {"weapon": "launcher", "two": true, "sa": -1, "fx": 9, "fy": -19})
static var KNEEL := Px.merge(Px.READY, {"weapon": "launcher", "two": true, "sa": 0, "fx": 9, "fy": -17, "crouch": 6, "lean": 2, "ffx": 12, "fbx": -9})
static var KICKED := Px.merge(KNEEL, {"x": -6, "sa": -0.12, "fx": 4, "fy": -19, "lean": -4, "crouch": 5})
static var act := {
	"target": {"x": TX},
	"poses": [
		[-0.52, REST_],
		[-0.18, KNEEL],
		[FIRE - 0.001, Px.merge(KNEEL, {"crouch": 7})],
		[FIRE, KICKED, "snap"],
		[FIRE + 0.36, Px.merge(KNEEL, {"x": -6})],
		[HIT + 0.9, Px.merge(KNEEL, {"x": -6, "crouch": 5, "lean": 1})],
		[HIT + 1.5, Px.merge(REST_, {"x": -3})],
		[HIT + 2.2, Px.merge(REST_, {"x": 0})],
		[HIT + 5.4, REST_],
	],
	"hits": [
		{"t": FIRE, "stop": 0.06, "shake": 0.22, "amp": 2, "target": false},
		{"t": HIT, "stop": 0.2, "shake": 0.45, "amp": 4, "push": 3.8, "straw": 44, "skin": "char"},
		{"t": HIT + 4.8, "push": 0, "straw": 0, "flash": 0, "skin": null},
	],
	"dust": [{"t": FIRE, "x": -16, "n": 10, "dir": -1}],
}

static var CHAIN := Px.chain([
	{"fx": Muzzle, "t": FIRE, "x": MX, "height": -MY},
	{"fx": Rocket, "t": FIRE, "until": HIT, "x": func(t): return MX + 10 + (t - FIRE) ** 1.5 * ((TX - MX - 16) / FLY ** 1.5), "y": MY},
	{"fx": Blast, "t": HIT, "x": TX},
])
static func create(o: Dictionary): return CHAIN.create(o)
