## Editor side of pixelfx: a Project > Tools item that bakes the selected PixelFx2D to a SpriteFrames resource.
@tool
extends EditorPlugin

const Baker := preload("bake/baker.gd")
const MENU := "pixelfx: Bake selected PixelFx2D to SpriteFrames"


func _enter_tree() -> void:
	add_tool_menu_item(MENU, _bake_selected)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU)


func _bake_selected() -> void:
	var sel := get_editor_interface().get_selection().get_selected_nodes()
	var done := 0
	for n in sel:
		if not (n is PixelFx2D):
			continue
		var fx: PixelFx2D = n
		var mod: Script = fx.effect_script if fx.effect_script else load("res://addons/pixelfx/fx/%s.gd" % fx.effect)
		if mod == null:
			continue
		var name := (fx.effect if not fx.effect_script else mod.resource_path.get_file().get_basename()).replace("/", "-")
		var path := "res://pixelfx_baked/%s.res" % name
		DirAccess.make_dir_recursive_absolute("res://pixelfx_baked")
		var err := Baker.save_sprite_frames(Baker.bake(mod, fx.fx_options(), ["", "back", "front"][fx.layer]), path)
		print("pixelfx: baked %s -> %s (%s)" % [name, path, error_string(err)])
		done += 1
	if done == 0:
		push_warning("pixelfx: select one or more PixelFx2D nodes first")
	get_editor_interface().get_resource_filesystem().scan()
