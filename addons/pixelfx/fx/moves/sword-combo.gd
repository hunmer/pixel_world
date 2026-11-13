# port-of: src/fx/moves/sword-combo.js@4a0fbb1dad7d3c3fd063370c8cbcc01b84f981a7
extends RefCounted

const Px := preload("../../core/px.gd")
const Slash := preload("../melee/sword-slash.gd")
const Double := preload("../melee/double-slash.gd")
const Cleave := preload("../melee/heavy-cleave.gd")

const A := 0
const B := 0.5
const C := 1.04
const STEP := 10
const FINISH := C + 0.335

static var meta := {
	"name": "Sword combo",
	"desc": "Three strokes walking forward: a slash, a crossing double cut, and a two-handed cleave into the floor that throws the target about.",
	"tags": ["move", "melee", "sword", "combo", "one-shot"],
	"size": [264, 150],
	"origin": [72, 130],
	"duration": FINISH + 1.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"seed": 1},
}

static func until(keys: Array, t: float) -> Array: return keys.filter(func(k): return k[0] <= t)
static var STAND_ := Px.merge(Px.READY, {"weapon": "sword", "fx": 11, "fy": -15, "sa": 0.38})
static var act := {
	"target": {"x": 118},
	"poses": Px.shiftKeys(until(Slash.act.poses, 0.3), A)
		+ Px.shiftKeys(until(Double.act.poses, 0.27).filter(func(k): return k[0] >= -0.14), B, {"dx": STEP})
		+ Px.shiftKeys(Cleave.act.poses.filter(func(k): return k[0] >= -0.3), C, {"dx": STEP * 2, "weapon": "sword"})
		+ [[FINISH + 1.6, Px.merge(STAND_, {"x": STEP * 2 - 4})]],
	"hits": Px.shiftHits(Slash.act.hits, A) + Px.shiftHits(Double.act.hits, B) + Px.shiftHits(Cleave.act.hits, C),
	"dust": Px.shiftHits(Slash.act.dust, A).map(func(d): return Px.merge(d)) + Px.shiftHits(Cleave.act.dust, C).map(func(d): return Px.merge(d, {"x": d.x + STEP * 2})),
}

static var CHAIN := Px.chain([
	{"fx": Slash, "t": A},
	{"fx": Double, "t": B, "x": STEP},
	{"fx": Cleave, "t": C, "x": STEP * 2},
])
static func create(o: Dictionary): return CHAIN.create(o)
