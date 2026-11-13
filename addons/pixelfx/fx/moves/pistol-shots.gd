# port-of: src/fx/moves/pistol-shots.js@c735d9726d214b98a0e209652823d290d52c4f22
extends RefCounted

const Px := preload("../../core/px.gd")
const Muzzle := preload("../projectiles/muzzle-pistol.gd")
const Tracer := preload("../projectiles/bullet-tracer.gd")
const Spark := preload("../impacts/hit-spark.gd")

const SHOTS := [0.14, 0.42, 0.7]
const FLY := 0.12
const TX := 180
const BY := -32
const MX := 28

static var meta := {
	"name": "Pistol shots",
	"desc": "Three aimed shots: the gun kicks up each time and settles, tracers cross the floor, and the target staggers under each hit.",
	"tags": ["move", "gun", "pistol", "projectile", "ranged", "one-shot"],
	"size": [378, 76],
	"origin": [111, 72],
	"duration": 2.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"seed": 1},
}

static var REST_ := Px.merge(Px.READY, {"weapon": "pistol", "sa": 0.9, "fx": 10, "fy": -17, "bx": 7, "by": -16})
static var AIM := Px.merge(REST_, {"crouch": 3, "lean": 2, "fx": 18, "fy": -28, "sa": 0, "bx": 12, "by": -25, "ffx": 11, "fbx": -9})
static var KICK := Px.merge(AIM, {"lean": 0, "fx": 16, "fy": -33, "sa": -0.45, "by": -28})
static var keys: Array = SHOTS.reduce(func(acc, t): return acc + [[t, AIM], [t + 0.001, KICK, "snap"], [t + 0.14, AIM]], [])
static var act := {
	"target": {"x": TX},
	"poses": [[-0.36, REST_], [-0.06, AIM]] + keys + [[1.2, Px.merge(AIM, {"crouch": 1})], [1.7, REST_], [2.6, REST_]],
	"hits": Px.arr(SHOTS.size(), func(i): return {"t": SHOTS[i] + FLY, "stop": 0.08 if i == 2 else 0.04, "shake": 0.1, "amp": 1 + (1 if i == 2 else 0), "push": -1.8 if i % 2 else 2, "straw": 10, "y": -30, "kick": 1}),
}

static var CHAIN := Px.chain(
	SHOTS.reduce(func(acc, t): return acc + [
		{"fx": Muzzle, "t": t, "x": MX, "height": -BY},
		{"fx": Tracer, "t": t, "until": t + FLY, "x": func(u): return MX + 4 + (u - t) * ((TX - MX - 14) / FLY), "y": BY},
		{"fx": Spark, "t": t + FLY, "x": TX - 10, "height": 28},
	], []),
)
static func create(o: Dictionary): return CHAIN.create(o)
