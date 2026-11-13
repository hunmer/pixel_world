## An effect performed: the stock character winds up, lets go and recovers, a straw target takes the hit, and the
## whole thing freezes for a moment on contact and shakes. The node's position is the character's feet.
##
## To act an effect out with your own character instead, read its timing with PixelFxAct2D.timing("melee/sword-slash")
## (windup, recovery, hits with t and freeze) and play your attack animation `windup` seconds before a PixelFx2D;
## at each hit, stop updating everything for `freeze` seconds.
@tool
class_name PixelFxAct2D
extends Node2D

## A hit landed: { t, stop (freeze s), shake, amp, push, skin, ... } as the effect's act describes it.
signal hit(info: Dictionary)
signal finished

const Px := preload("../core/px.gd")
const REGISTRY_PATH := "res://addons/pixelfx/fx/registry.gd"

## An effect with an act (see docs/CATALOG.md: every effect with a character has one, and so does every move).
@export var effect: String = "melee/sword-slash":
	set(v):
		effect = v
		_reload()
@export var autoplay := true
@export var speed_scale := 1.0
@export var flip := false:
	set(v):
		flip = v
		_reload()
@export var seed := -1:
	set(v):
		seed = v
		_reload()
@export var palette_preset := "":
	set(v):
		palette_preset = v
		_reload()
@export var options := {}
## Draw the stock character (false: the effect and the target only).
@export var show_body := true
## Draw the target.
@export var show_target := true
## Shake this node instead of the act itself (a Camera2D, or your level's root).
@export var shake_node: NodePath
## Replay when it ends (for previews).
@export var loop_act := false

var _act: Px.Act.ActInstance
var _frame: Px.Frame
var _img: Image
var _tex: ImageTexture
var _sprite: Sprite2D
var _playing := false
var _pivot := Vector2.ZERO
var _base_offset := Vector2.ZERO


## An act's timing as plain data, for a game with its own character (see Px.Act.actTiming).
static func timing(id: String) -> Variant:
	return Px.Act.actTiming(load("res://addons/pixelfx/fx/%s.gd" % id))


func _ready() -> void:
	_reload()
	if autoplay:
		play()


func _validate_property(property: Dictionary) -> void:
	if property.name == "effect" and ResourceLoader.exists(REGISTRY_PATH):
		var reg: Script = load(REGISTRY_PATH)
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(Array(reg.ids()).filter(func(id): return reg.EFFECTS[id].act))
	elif property.name == "palette_preset":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = "," + ",".join(Px.PAL.keys())


func _reload() -> void:
	if not is_inside_tree():
		return
	var path := "res://addons/pixelfx/fx/%s.gd" % effect
	if not ResourceLoader.exists(path):
		_act = null
		return
	var mod: Script = load(path)
	var b := Px.Act.actBounds(mod)
	var w := int(b.x1 - b.x0) + 12
	var h := int(b.y1 - b.y0) + 12
	_pivot = Vector2(6.0 - b.x0, 6.0 - b.y0)
	var o := options.duplicate()
	o.merge({"x": _pivot.x, "y": _pivot.y}, true)
	if seed >= 0:
		o.seed = float(seed)
	if palette_preset and Px.PAL.has(palette_preset):
		o.palette = Px.PAL[palette_preset]
	if flip:
		o.flip = true
	_act = Px.Act.createAct(mod, o)
	_act.onHit = func(h): hit.emit(h)
	_frame = Px.createFrame(w, h)
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite, false, Node.INTERNAL_MODE_FRONT)
	_sprite.offset = -_pivot
	_img = null
	_draw_frame()


func play() -> void:
	_reload()
	_playing = true


## Let a looping effect end (one-shots end on their own).
func stop() -> void:
	if _act:
		_act.stop()


func is_frozen() -> bool:
	return _act != null and _act.frozen()


func _process(delta: float) -> void:
	if not _playing or _act == null:
		return
	_act.update(delta * speed_scale)
	if _act.done():
		_playing = false
		_apply_shake(Vector2.ZERO)
		finished.emit()
		if loop_act or Engine.is_editor_hint():
			play()
		return
	var s := _act.shake()
	_apply_shake(Vector2(s[0], s[1]))
	_draw_frame()


func _apply_shake(v: Vector2) -> void:
	var target: Node = get_node_or_null(shake_node) if shake_node else null
	if target is Camera2D:
		(target as Camera2D).offset = v
	elif target is Node2D:
		(target as Node2D).position = (target as Node2D).position - _base_offset + v
		_base_offset = v
	elif _sprite:
		_sprite.position = v


func _draw_frame() -> void:
	if _act == null:
		return
	_frame.clear()
	_act.draw(_frame, {"body": show_body, "target": show_target})
	var bytes := Px.composite(_frame, PackedByteArray(), null)
	if _img == null:
		_img = Image.create_from_data(_frame.w, _frame.h, false, Image.FORMAT_RGBA8, bytes)
		_tex = ImageTexture.create_from_image(_img)
		_sprite.texture = _tex
	else:
		_img.set_data(_frame.w, _frame.h, false, Image.FORMAT_RGBA8, bytes)
		_tex.update(_img)
