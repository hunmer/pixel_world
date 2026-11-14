extends SceneTree

const ServiceScript := preload("res://scripts/assets/user_asset_service.gd")
const AdapterScript := preload("res://scripts/assets/user_asset_visual_adapter.gd")
const TMP_ROOT := "user://zz_probe2_tmp"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_remove_recursive(TMP_ROOT)
	var svc: Node = ServiceScript.new(TMP_ROOT)
	root.add_child(svc)
	var png := _make_png(4, 4, Color.RED)
	var src := TMP_ROOT + "/src/red_block.png"
	DirAccess.make_dir_recursive_absolute(TMP_ROOT + "/src")
	var f := FileAccess.open(src, FileAccess.WRITE)
	f.store_buffer(png)
	f.close()
	var res: Dictionary = svc.import_local_file(src)
	print("import: ", res)
	var d: Variant = svc.find_by_id("red_block")
	print("descriptor: ", d)
	var adapter := AdapterScript.new(TMP_ROOT)
	var v: Dictionary = adapter.resolve("red_block")
	print("resolve missing=", v.get("missing"), " canvas=", v.get("canvas_size"))
	print("resolve_many=", adapter.resolve_many(["red_block"]).get("red_block", {}).get("missing"))
	svc.save_library()
	root.remove_child(svc)
	svc.queue_free()
	_remove_recursive(TMP_ROOT)
	quit(0)

func _make_png(w: int, h: int, c: Color) -> PackedByteArray:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img.save_png_to_buffer()

func _remove_recursive(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	var d := DirAccess.open(p)
	d.list_dir_begin()
	var n := d.get_next()
	while not n.is_empty():
		var cp := p + "/" + n
		if d.current_is_dir():
			_remove_recursive(cp)
		else:
			DirAccess.remove_absolute(cp)
		n = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(p)
