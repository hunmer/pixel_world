# port-of: src/fx/ui/achievement.js@982a080f01c33b3ad2d543e779f6412e1caa87a1
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Achievement",
	"desc": "A toast slides in on speed lines and settles; a gold medal pops onto it in a burst of sparkles, a shine sweeps the whole toast, then it slides away.",
	"tags": ["ui", "achievement", "toast", "medal", "reward", "text", "one-shot"],
	"size": [220, 72],
	"origin": [110, 36],
	"duration": 2.4,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#2a1405", "#5c3008", "#9a5a0e", "#d48e18", "#f5b92c", "#ffde5e", "#fff4bc", "#ffffff"],
		"ribbon": ["#0c1430", "#1f3a7a", "#2f66c4", "#5aa0f0", "#a6d4ff"],
		"title": "ACHIEVEMENT",
		"text": "UNLOCKED",
		"seed": 9,
	},
}

const PW := 130.0
const PH := 34.0
const PX := -PW / 2.0
const PY := -PH / 2.0
const IN := 0.2
const MEDAL := 0.26
const SHINE := 0.95
const OUT := 1.92
const MX := PX + 17.0
const MY := 2.0
static var INK := {"outline": Px.hex("#0d0a14"), "rim": Px.hex("#5a4f74"), "top": Px.hex("#2a2338"), "body": Px.hex("#211b2d"), "low": Px.hex("#15111c")}
static var K9A94B0 := Px.hex("#9a94b0")
static var KD8D4E6 := Px.hex("#d8d4e6")
static var K6E6886 := Px.hex("#6e6886")


static func _inStar(st: Array, px: float, py: float) -> bool:
	var inside := false
	var j := st.size() - 1
	for i in st.size():
		var xi: float = st[i][0]
		var yi: float = st[i][1]
		var xj: float = st[j][0]
		var yj: float = st[j][1]
		if (yi > py) != (yj > py) and px < ((xj - xi) * (py - yi)) / (yj - yi) + xi:
			inside = not inside
		j = i
	return inside


# the medal: ribbon straps behind it, a scalloped-free gold disc with a lit rim and a raised star
static func medal(p: Px.Painter, G: Array, B: Array, x: float, y: float, s: float, white: bool, shine: Variant) -> void:
	var r := 10.0 * s
	for sd in [-1.0, 1.0]:
		# a strap from the medal up to the toast's top edge
		p.poly([[x + sd * 2.0 * s, y - r + 2.0], [x + sd * 7.0 * s, y - r + 2.0], [x + sd * 9.0 * s, PY + 1.0], [x + sd * 4.0 * s, PY + 1.0]], func(px: float): return B[2] if absf(px - x) < 4.5 * s else B[3])
		p.line(x + sd * 2.0 * s, y - r + 2.0, x + sd * 4.0 * s, PY + 1.0, B[0])
		p.line(x + sd * 7.0 * s, y - r + 2.0, x + sd * 9.0 * s, PY + 1.0, B[0])
	var st := Px.star(x, y + 0.5, 2.8 * s, 6.5 * s, 5)
	p.shade(x - r - 1.0, y - r - 1.0, x + r + 1.0, y + r + 1.0, func(px: float, py: float):
		var dx := px - x
		var dy := py - y
		var d := Px.hypot(dx, dy)
		if d > r:
			return null
		if white:
			return G[6] if r - d < 1.0 else WHITE
		if r - d < 1.0:
			return G[0]
		var l := -(dx * 0.6 + dy * 0.8) / r
		if shine != null and absf(dx - dy * 0.6 - shine) < 1.2:
			return WHITE
		if r - d < 2.5:
			return G[6] if l > 0.2 else (G[4] if l > -0.3 else G[3])
		# the raised star: a dark edge, a lit upper-left face, a shaded lower-right one
		if _inStar(st, px, py):
			return G[2] if (not _inStar(st, px + 1.0, py) or not _inStar(st, px - 1.0, py) or not _inStar(st, px, py + 1.0) or not _inStar(st, px, py - 1.0)) else (G[7] if dx + dy < 0.0 else G[6])
		return G[5] if l > 0.4 else (G[4] if l > -0.2 else G[3]))


var G: Array
var B: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var title: Dictionary
var sub: Dictionary
var TX := PX + 34.0
var t := 0.0
var popped := false
var end: float


func create(o: Dictionary) -> void:
	G = Px.fit(o.palette, 8)
	B = Px.fit(o.ribbon, 5)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [G[7], G[6], G[5], G[3]]})
	lights = Px.Lights.new()
	title = Lib.spell(o.title, "mini")
	sub = Lib.spell(o.text, "mini")
	end = meta.duration - 0.05


# the toast slides in from the right, overshoots and settles; at the end it eases back and slides off
static func xAt(tt: float) -> float:
	if tt < IN:
		return 30.0 * pow(1.0 - tt / IN, 3.0)
	if tt < OUT:
		return -3.0 * exp(-(tt - IN) * 12.0) * sin((tt - IN) * 30.0)
	if Px.seg(tt, OUT, OUT + 0.06) < 1.0:
		return -3.0 * Px.seg(tt, OUT, OUT + 0.06)
	return -3.0 + 33.0 * Px.Ease.inQuad(Px.seg(tt, OUT + 0.06, OUT + 0.24))


func update(dt: float) -> void:
	t += dt
	if not popped and t >= MEDAL + 0.06:
		popped = true
		lights.add(MX, MY, 36.0, G[5], 0.7, 0.4)
		for i in 12:
			var an := (i / 12.0) * TAU + R.range(-0.2, 0.2)
			var sp := R.range(40.0, 90.0)
			ps.spawn(P.STAR, MX + cos(an) * 9.0, MY + sin(an) * 9.0, cos(an) * sp, sin(an) * sp * 0.6, R.range(0.25, 0.45), R.pick([G[7], G[6], G[5]]), 0.6 if i % 3 else R.range(1.2, 1.8))
	if t > 0.5 and t < OUT and R.chance(0.05):
		ps.spawn(P.STAR, MX + R.range(-11.0, 11.0), MY + R.range(-11.0, 9.0), 0.0, -R.range(4.0, 10.0), minf(R.range(0.3, 0.5), end - t), G[6], 1.4 if R.chance(0.3) else 0.6)
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	var x := xAt(t)
	var out := t > OUT + 0.06
	var a := 0.5 if t < 0.05 else (1.0 - Px.seg(t, OUT + 0.12, OUT + 0.24) if out else 1.0)
	if a <= 0.0:
		return
	# speed lines trail it while it moves
	var moving := t < IN * 0.8 or out
	if moving:
		for i in 8:
			var y := PY + 3.0 + Px.rand(floorf(t * 30.0), i, 1) * (PH - 6.0)
			var L := 10.0 + Px.rand(floorf(t * 30.0), i, 2) * 26.0
			var x0 := x + PW / 2.0 + 2.0 + Px.rand(i, 3) * 6.0
			p.line(x0, y, minf(106.0, x0 + L), y, func(u: float): return WHITE if u < 0.3 else (G[6] if u < 0.6 else G[4]), func(u: float): return a * (1.1 - u))
	# the plate and its gold edge; a shine sweeps the whole toast
	var sh := Px.seg(t, SHINE, SHINE + 0.36)
	var shine: Variant = PX - 12.0 + (PW + 30.0) * Px.Ease.inOutSine(sh) if (sh > 0.0 and sh < 1.0) else null
	Lib.panel(p, PX + x, PY, PW, PH, INK, {"r": 4.0, "a": a, "shine": null if shine == null else shine + x})
	p.line(PX + x + 4.0, PY + 1.0, PX + x + PW - 5.0, PY + 1.0, G[4], a)
	p.px(PX + x + 3.0, PY + 1.0, G[2])
	# the words: a gold title, a white line under it
	var ti := []
	for L: Dictionary in title.letters:
		if L.g != null:
			ti.append({"g": L.g, "x": TX + x + L.x * 2.0, "y": PY + 5.0, "sx": 2.0, "sy": 2.0, "a": a})
	Lib.drawWord(p, ti, {"fill": [G[4], G[5], G[6]], "edge": G[7], "under": G[3], "outline": INK.outline, "shadow": 0, "shine": null if shine == null else shine + x, "shineY": PY, "glint": G[7]})
	var si := []
	for L: Dictionary in sub.letters:
		if L.g != null:
			si.append({"g": L.g, "x": TX + x + L.x * 2.0, "y": PY + 19.0, "sx": 2.0, "sy": 2.0, "a": a})
	Lib.drawWord(p, si, {"fill": [K9A94B0, KD8D4E6, WHITE], "edge": WHITE, "under": K6E6886, "outline": INK.outline, "shadow": 0, "shine": null if shine == null else shine + x, "shineY": PY})
	# the medal pops onto it: big and white for a frame, then springs to size
	var mk := t - MEDAL
	if mk > 0.0:
		var s := 1.5 if mk < 0.035 else 1.0 + 0.35 * exp(-mk * 16.0) * cos(mk * 28.0)
		medal(p, G, B, MX + x, MY, s, mk < 0.07, null if shine == null else shine - MX + 4.0)
		p.glow(MX + x, MY, 20.0, G[5], 0.3 * a + (0.5 * (1.0 - mk / 0.15) if mk < 0.15 else 0.0))
		var g := fmod(t - 1.5, 0.9) / 0.9
		if t > 1.5 and g < 0.25:
			Px.sparkle(p, MX + x - 4.0, MY - 4.0, 4.0 * sin((g / 0.25) * PI), G[7], G[6], 0.5)
	ps.draw(p)
	lights.draw(p)
