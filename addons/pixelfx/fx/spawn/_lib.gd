# Shared by the spawn and death effects: the actor's own body as a list of pixels to break up, burn, freeze or
# copy, and the cells just outside it for outlines. Files starting with _ are helpers, not effects.
# port-of: src/fx/spawn/_lib.js@2c26ec1dc73b720071c7f0ccb97e27289a7a54a3
extends RefCounted

const Px := preload("../../core/px.gd")


## The body bodyOf returns: { list, w, h, x, y } with on(mx, my) and cell(mx, my) as methods.
class Body extends RefCounted:
	var list: Array = []
	var cells: Array = []
	var w: int
	var h: int
	var x: float
	var y: float
	var data: PackedByteArray

	func on(mx: int, my: int) -> bool:
		return mx >= 0 and my >= 0 and mx < w and my < h and data[my * w + mx] != 0

	func cell(mx: int, my: int) -> Variant:
		return cells[my * w + mx] if on(mx, my) else null


## The actor's body: { list: [{ x, y, mx, my, c, edge }], w, h, x, y, on(mx, my), cell(mx, my) }, local space
## with the feet at (0, 0). c is the character's own color (o.actor.pixels); an actor without pixels is shaded
## from the ramp C (lit at the top, darker toward the feet). edge marks pixels on the silhouette's rim.
static func bodyOf(actor: Dictionary, C: Array) -> Body:
	var m: Dictionary = actor.mask
	var px: Variant = actor.get("pixels")
	var body := Body.new()
	var mw: int = m.w
	var mh: int = m.h
	body.w = mw
	body.h = mh
	body.data = m.data
	body.x = actor.x
	body.y = actor.y
	var list := body.list
	var cells := body.cells
	cells.resize(mw * mh)
	cells.fill(null)
	for my in mh:
		for mx in mw:
			if not body.on(mx, my):
				continue
			var own: Variant = px[my * mw + mx] if px != null else null
			var c: int = Px.hex(own) if own else C[int(maxf(1.0, minf(C.size() - 2, Px.round((C.size() - 2) * (0.85 - (my / float(mh)) * 0.5)))))]
			var b := {"x": body.x + mx, "y": body.y + my, "mx": mx, "my": my, "c": c, "edge": not body.on(mx - 1, my) or not body.on(mx + 1, my) or not body.on(mx, my - 1) or not body.on(mx, my + 1)}
			list.append(b)
			cells[my * mw + mx] = b
	return body


## Cells just outside the body (4-neighbours of its rim), local space: [{ x, y, mx, my }].
static func rimOf(body: Body) -> Array:
	var out := []
	for my in range(-1, body.h + 1):
		for mx in range(-1, body.w + 1):
			if not body.on(mx, my) and (body.on(mx - 1, my) or body.on(mx + 1, my) or body.on(mx, my - 1) or body.on(mx, my + 1)):
				out.append({"x": body.x + mx, "y": body.y + my, "mx": mx, "my": my})
	return out
