## Plays a pixelfx effect. The node's position is the effect's origin (the feet, the point of impact, the base of a
## torch); its pixels stay crisp at any zoom. Color is drawn normally and light goes on an additive layer on top, so
## glow brightens whatever is behind it.
##
## BAKED (the default) renders each frame once, the first time it's shown, and replays it for free after that; every
## node with the same effect and options shares the frames. LIVE renders every frame on the CPU at the game's own frame
## rate: for effects that must react while they play, or tweaks you want to see as you make them.
##
##     var fx := PixelFx2D.new()
##     fx.effect = "ice/frost-nova"
##     fx.palette_preset = "fire"           # any Px.PAL ramp; or set palette to your own colors
##     fx.position = hero.position
##     add_child(fx)                        # plays on its own; frees itself when done if free_when_done
@tool
class_name PixelFx2D
extends Node2D

signal finished

enum Mode { BAKED, LIVE }
enum Layer { BOTH, BACK, FRONT }

const Px := preload("../core/px.gd")
const Baker := preload("../bake/baker.gd")
const REGISTRY_PATH := "res://addons/pixelfx/fx/registry.gd"

## The effect id, "category/name" (see docs/CATALOG.md). Ignored when effect_script is set.
@export var effect: String = "fire/torch":
	set(v):
		effect = v
		_reload()
## A custom effect script (one you wrote), instead of an id.
@export var effect_script: Script:
	set(v):
		effect_script = v
		_reload()
@export var mode: Mode = Mode.BAKED:
	set(v):
		mode = v
		_reload()
@export var autoplay := true
@export var speed_scale := 1.0
## Mirror it (directional effects face right).
@export var flip := false:
	set(v):
		flip = v
		_reload()
## The effect's seed: another take on the same effect. -1 keeps the effect's own.
@export var seed := -1:
	set(v):
		seed = v
		_reload()
## Recolor: a dark-to-bright ramp. Empty keeps the effect's own colors.
@export var palette := PackedColorArray():
	set(v):
		palette = v
		_reload()
## Recolor with one of the library's ramps (fire, ice, poison, holy, arcane, shadow, ...) when palette is empty.
@export var palette_preset := "":
	set(v):
		palette_preset = v
		_reload()
## Glow strength (the effect's `light` option).
@export_range(0.0, 3.0, 0.05) var light := 1.0:
	set(v):
		light = v
		_reload()
## The effect rotated in pixel space, radians (stays on the pixel grid, unlike rotating the node).
@export var fx_angle := 0.0:
	set(v):
		fx_angle = v
		_reload()
## The effect's own knobs (meta.options: size, count, radius, text, ...).
@export var options := {}:
	set(v):
		options = v
		_reload()
## What to draw: the part behind a character, the part in front, or both.
@export var layer := Layer.BOTH:
	set(v):
		layer = v
		_reload()
## Light as a separate additive layer (true) or baked into the color as alpha, like the sprite sheets (false).
@export var additive_light := true:
	set(v):
		additive_light = v
		_reload()
## Draw the stock character too (for previews of effects that wrap one).
@export var show_actor := false
## queue_free() itself when a one-shot ends (or a stopped loop has faded).
@export var free_when_done := false

static var _cache := {}

var _color: Sprite2D
var _light: Sprite2D
var _mod: Script
var _meta := {}
var _track: Baker.Track
var _inst: Px.Fx.Instance
var _frame: Px.Frame
var _img_c: Image
var _img_l: Image
var _t := 0.0
var _playing := false
var _stop_at := INF
var _shown := -1
var _done := false


func _ready() -> void:
	_reload()
	if autoplay:
		play()


func _validate_property(property: Dictionary) -> void:
	if property.name == "effect" and ResourceLoader.exists(REGISTRY_PATH):
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(load(REGISTRY_PATH).ids())
	elif property.name == "palette_preset":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = "," + ",".join(Px.PAL.keys())


## The effect's options as this node sets them.
func fx_options() -> Dictionary:
	var o := options.duplicate()
	if seed >= 0:
		o.seed = float(seed)
	if not palette.is_empty():
		o.palette = Array(palette).map(func(c): return "#" + c.to_html(false))
	elif palette_preset and Px.PAL.has(palette_preset):
		o.palette = Px.PAL[palette_preset]
	if light != 1.0:
		o.light = light
	if fx_angle != 0.0:
		o.angle = fx_angle
	if flip:
		o.flip = true
	return o


func _layer_name() -> String:
	return ["", "back", "front"][layer]


func _resolve() -> Script:
	if effect_script:
		return effect_script
	if effect.is_empty():
		return null
	var path := "res://addons/pixelfx/fx/%s.gd" % effect
	return load(path) if ResourceLoader.exists(path) else null


func _reload() -> void:
	if not is_inside_tree():
		return
	_mod = _resolve()
	_track = null
	_inst = null
	_shown = -1
	if _mod == null:
		if _color:
			_color.texture = null
		return
	_meta = Px.Fx.metaOf(_mod)
	if _color == null:
		_color = Sprite2D.new()
		_color.centered = false
		_color.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_color, false, Node.INTERNAL_MODE_FRONT)
		_light = Sprite2D.new()
		_light.centered = false
		_light.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_light.material = mat
		add_child(_light, false, Node.INTERNAL_MODE_FRONT)
	var origin := Vector2(_meta.origin[0], _meta.origin[1])
	_color.offset = -origin
	_light.offset = -origin
	_light.visible = additive_light
	var opts := fx_options()
	if mode == Mode.BAKED:
		var key := "%s|%s|%s" % [_mod.resource_path if _mod.resource_path else str(_mod.get_instance_id()), JSON.stringify(opts), _layer_name()]
		_track = _cache.get(key)
		if _track == null:
			_track = Baker.track(_mod, opts, _layer_name())
			_cache[key] = _track
			_hook_cleanup()
	else:
		var o := {"x": origin.x, "y": origin.y}
		o.merge(opts, true)
		_inst = Px.createFx(_mod, o)
		_frame = Px.createFrame(_meta.size[0], _meta.size[1])
	_show()


## Start (or restart) from the first frame.
func play() -> void:
	_t = 0.0
	_stop_at = INF
	_done = false
	_playing = true
	if mode == Mode.LIVE and _mod:
		_reload()
	visible = true
	_show()


## Let it end: a loop fades out over 0.3 s, a one-shot is cut short.
func stop() -> void:
	if _stop_at == INF:
		_stop_at = _t
		if _inst:
			_inst.stop()


func is_playing() -> bool:
	return _playing


## Drop every baked frame (all nodes). Frames are rebuilt the next time they're shown.
static func clear_cache() -> void:
	_cache.clear()


# The cache is static, but what's in it (textures, effect instances) has to go while the engine is still up: when the
# scene tree's root leaves (the game quits), clear it.
static var _hooked := false

static func _hook_cleanup() -> void:
	if _hooked:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_hooked = true
	tree.root.tree_exiting.connect(func():
		_cache.clear()
		_hooked = false, CONNECT_ONE_SHOT)


## Render every frame of an effect now (at load time, say), so the first play costs nothing.
static func prebake(id_or_script: Variant, opts: Dictionary = {}, which_layer: String = "") -> void:
	var mod: Script = id_or_script if id_or_script is Script else load("res://addons/pixelfx/fx/%s.gd" % id_or_script)
	var key := "%s|%s|%s" % [mod.resource_path, JSON.stringify(opts), which_layer]
	var tr: Baker.Track = _cache.get(key)
	if tr == null:
		tr = Baker.track(mod, opts, which_layer)
		_cache[key] = tr
		_hook_cleanup()
	for i in tr.n:
		tr.get_frame(i)


func _process(delta: float) -> void:
	if not _playing or _mod == null:
		return
	var dt := delta * speed_scale
	_t += dt
	var D: float = _meta.duration
	if _inst:
		_inst.update(dt)
	var ended: bool = (_t - _stop_at >= Px.Fx.FADE) or (not _meta.loop and _t >= D)
	if ended and not _done:
		_done = true
		_playing = false
		_color.texture = null
		_light.texture = null
		modulate.a = 1.0
		finished.emit()
		if Engine.is_editor_hint():
			play()
		elif free_when_done:
			queue_free()
		return
	_show()


func _show() -> void:
	if _mod == null or _color == null:
		return
	if _track:
		var fps: float = _track.fps
		var i := floori(_t * fps)
		i = i % _track.n if _meta.loop else mini(i, _track.n - 1)
		if i == _shown:
			_apply_fade()
			return
		_shown = i
		var f := _track.get_textures(i)
		_color.texture = f[0] if additive_light else f[2]
		_light.texture = f[1] if additive_light else null
		_apply_fade()
		return
	if _inst:
		_frame.clear()
		_inst.draw(_frame, _layer_name())
		var cb := _frame.color.to_byte_array()
		var lb := _frame.light.to_byte_array()
		if not additive_light:
			cb = Px.composite(_frame, PackedByteArray(), null)
		if _img_c == null or _img_c.get_width() != _frame.w:
			_img_c = Image.create_from_data(_frame.w, _frame.h, false, Image.FORMAT_RGBA8, cb)
			_img_l = Image.create_from_data(_frame.w, _frame.h, false, Image.FORMAT_RGBA8, lb)
			_color.texture = ImageTexture.create_from_image(_img_c)
			_light.texture = ImageTexture.create_from_image(_img_l)
		else:
			_img_c.set_data(_frame.w, _frame.h, false, Image.FORMAT_RGBA8, cb)
			_img_l.set_data(_frame.w, _frame.h, false, Image.FORMAT_RGBA8, lb)
			(_color.texture as ImageTexture).update(_img_c)
			(_light.texture as ImageTexture).update(_img_l)


# A stopped loop in BAKED mode fades with the node's alpha (LIVE fades in the painter, dithered).
func _apply_fade() -> void:
	if _track and _stop_at != INF:
		modulate.a = Px.clamp(1.0 - (_t - _stop_at) / Px.Fx.FADE)
