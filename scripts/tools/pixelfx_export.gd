## pixelfx_export.gd — 离线把全部 pixelfx 特效烘焙导出为缩略图 png（每个特效取中间帧）
## 产物：assets/pixelfx_export/<id 中 / 换 _>/thumb.png
## 画廊运行时直读缩略图零烘焙、跨会话秒开；预览播放仍走运行时烘焙（画廊已做分帧预热）。
## 已导出的特效重跑自动跳过（幂等增量）。运行：godot --headless --path . --script res://scripts/tools/pixelfx_export.gd
extends SceneTree

const OUT_ROOT := "res://assets/pixelfx_export"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var Registry = load("res://addons/pixelfx/fx/registry.gd")
	var Baker = load("res://addons/pixelfx/bake/baker.gd")
	var ids: Array = Registry.EFFECTS.keys()
	ids.sort()
	var t_start := Time.get_ticks_msec()
	var exported := 0
	var skipped := 0
	var slow_log := ""
	for idx in ids.size():
		var id: String = ids[idx]
		var dir := "%s/%s" % [OUT_ROOT, id.replace("/", "_")]
		var thumb_path := dir + "/thumb.png"
		if FileAccess.file_exists(thumb_path):
			skipped += 1
			continue
		var t0 := Time.get_ticks_msec()
		var meta: Dictionary = Registry.EFFECTS[id]
		var mod: Resource = load(meta.get("path"))
		var track = Baker.track(mod, {})
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var mid: int = track.n / 2
		track.get_frame(mid)[2].save_png(thumb_path)
		exported += 1
		var dt := Time.get_ticks_msec() - t0
		if dt > 1000:
			slow_log += "  %5dms %s (frame %d/%d)\n" % [dt, id, mid, track.n]
		if exported % 40 == 0:
			print("… %d/%d done (%s)" % [idx + 1, ids.size(), id])
		await process_frame
	print("exported=%d skipped=%d in %.0fs" % [exported, skipped, (Time.get_ticks_msec() - t_start) / 1000.0])
	if slow_log != "":
		print("slow (>1s):")
		print(slow_log)
	quit(0)
