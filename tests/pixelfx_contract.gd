## tests/pixelfx_contract.gd — pixelfx 插件安装契约：注册表完整性、BAKED/LIVE 两条 CPU 渲染管线、节点自动播放与 act 时序 API。
extends SceneTree

const Registry := preload("res://addons/pixelfx/fx/registry.gd")
const Px := preload("res://addons/pixelfx/core/px.gd")
const Baker := preload("res://addons/pixelfx/bake/baker.gd")
const PixelFx2DScript := preload("res://addons/pixelfx/nodes/pixel_fx_2d.gd")
const PixelFxAct2DScript := preload("res://addons/pixelfx/nodes/pixel_fx_act_2d.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok: %s" % message)
	else:
		failures += 1
		printerr("  FAIL: %s" % message)


func _opaque_pixels(img: Image) -> int:
	var count := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				count += 1
	return count


func _run() -> void:
	print("pixelfx_contract: registry")
	var ids: Array = Registry.ids()
	_expect(ids.size() == 244, "特效注册表共 %d 个（期望 244）" % ids.size())
	var missing := 0
	for id in ids:
		var path: String = Registry.EFFECTS[id].path
		if not ResourceLoader.exists(path):
			missing += 1
			printerr("    missing: %s -> %s" % [id, path])
	_expect(missing == 0, "注册表每个 id 的脚本路径都存在（缺失 %d）" % missing)

	print("pixelfx_contract: BAKED 管线（Baker.track 渲染 Image）")
	var campfire := load("res://addons/pixelfx/fx/fire/campfire.gd")
	var track: Baker.Track = Baker.track(campfire, {}, "")
	_expect(track.n > 0 and track.fps > 0.0, "campfire 烘焙轨道 n=%d fps=%s" % [track.n, str(track.fps)])
	var f0: Array = track.get_frame(0)
	_expect(f0[0] is Image and f0[0].get_width() == 128, "首帧 color 图像尺寸 128 宽")
	_expect(_opaque_pixels(f0[2]) > 200, "首帧合成图有 %d 个非透明像素（>200）" % _opaque_pixels(f0[2]))
	var mid: Array = track.get_frame(track.n / 2)
	_expect(_opaque_pixels(mid[2]) > 200, "中段帧合成图仍有内容")

	print("pixelfx_contract: LIVE 管线（Px.createFx 逐帧驱动）")
	var meta := Px.Fx.metaOf(campfire)
	var inst := Px.createFx(campfire, {"x": 64.0, "y": 56.0})
	var frame := Px.createFrame(meta.size[0], meta.size[1])
	var live_nonzero := false
	for i in 30:
		inst.update(1.0 / 12.0)
		frame.clear()
		inst.draw(frame, "")
		for px in frame.color:
			if px & 0xff000000:
				live_nonzero = true
				break
		if live_nonzero:
			break
	_expect(live_nonzero, "LIVE 模式 30 帧内渲染出不透明像素")

	print("pixelfx_contract: PixelFx2D 节点（BAKED 自动播放）")
	var fx: Node2D = PixelFx2DScript.new()
	fx.effect = "fire/campfire"
	root.add_child(fx)
	var tex: Texture2D = fx._color.texture
	_expect(tex != null and tex.get_width() == 128, "add_child 即产出首帧纹理 128 宽")
	var fx2: Node2D = PixelFx2DScript.new()
	fx2.effect = "ice/frost-nova"
	fx2.palette_preset = "fire"
	root.add_child(fx2)
	_expect(fx2._color.texture != null, "palette_preset 重着色路径可用")
	fx.queue_free()
	fx2.queue_free()

	print("pixelfx_contract: PixelFxAct2D 时序 API")
	var timing: Variant = PixelFxAct2DScript.timing("melee/sword-slash")
	_expect(timing is Dictionary and timing.has("windup"), "sword-slash act 时序含 windup")
	if timing is Dictionary and timing.has("hits"):
		_expect(timing.hits.size() > 0, "act 时序含 %d 个 hit" % timing.hits.size())

	_preview_sheet()

	print("pixelfx_contract: %s" % ("ALL OK" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures > 0 else 0)


## 4 个代表特效的中段帧拼成一张预览图，供安装验收直观查看（res://tmp/pixelfx_preview.png）。
func _preview_sheet() -> void:
	var picks := ["fire/campfire", "ice/frost-nova", "explosions/big-explosion", "water/waterfall"]
	var frames: Array = []
	var cell_w := 0
	var cell_h := 0
	for id in picks:
		var mod := load("res://addons/pixelfx/fx/%s.gd" % id)
		var t: Baker.Track = Baker.track(mod, {}, "")
		var f: Array = t.get_frame(t.n / 2)
		frames.append(f[2])
		cell_w = maxi(cell_w, f[2].get_width())
		cell_h = maxi(cell_h, f[2].get_height())
	var sheet := Image.create(cell_w * 2 + 24, cell_h * 2 + 24, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.09, 0.12, 1.0))
	for i in frames.size():
		var gx := (i % 2) * (cell_w + 24) + 12
		var gy := (i / 2) * (cell_h + 24) + 12
		sheet.blit_rect(frames[i], Rect2i(0, 0, frames[i].get_width(), frames[i].get_height()), Vector2i(gx, gy))
	DirAccess.make_dir_recursive_absolute("res://tmp")
	var err := sheet.save_png("res://tmp/pixelfx_preview.png")
	_expect(err == OK and FileAccess.file_exists("res://tmp/pixelfx_preview.png"), "预览拼图已生成 res://tmp/pixelfx_preview.png")
