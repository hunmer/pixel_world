# 可旋转等距地图：贴图修复交接

- 时间：2026-11-11 20:56（Asia/Shanghai）
- 项目：`E:/pixel_world`
- 引擎：Godot 4.7.2 stable，GL Compatibility
- 下一阶段重点：完成“柱内顶面剔除”的最后修正，重新跑契约，并逐角度截图确认地图不再消失、不错位、不在平地上出现错误侧壁。

## 用户目标与反馈

1. 最初要求为地图加入可旋转等距投影：Q/E 或左右键连续旋转，Z/X 步进 45°，中键拖拽，平滑插值，R 复位。
2. 用户随后反馈连续按三次 Z 后，平地出现错误高度/侧壁。
3. 后续又反馈旋转后地图全黑、只剩动物，以及旋转贴图出现大片暗空隙/带状贴面。
4. 用户已明确许可直接调用运行截图，不需要再次询问。
5. 正确性优先于性能；不能以契约或 FPS 通过代替画面验收。

## 当前架构与关键文件

- `scripts/isometric_view.gd`：投影、反投影、连续/步进/拖拽、平滑插值与复位。
- `main.gd`：把当前基向量传给地形柱；旋转时刷新柱、玩家、动物、排序、相机和裁剪；提供 `cell_stand_level(cell)` 作为邻格高度查询。
- `scripts/isometric_column_batch.gd`：当前主要修改点。包含地形表面重建、ArrayMesh 合批、draw plan 缓存、内部侧面剔除、旋转期间视口裁剪和遮挡懒计算。
- `shaders/isometric_terrain_rotate.gdshader`：GPU 旋转地形顶点。当前共享材质只保存 `view_angle`，不得再添加每列共享的 `screen_y_offset`。
- `tests/isometric_view_contract.gd`：投影/控制器与主场景集成契约。
- `tests/isometric_column_projection_contract.gd`：多角度几何、GPU 顶点、邻格侧面与多层柱可见表面契约。
- `tests/battle_screen_pick_contract.gd`、`tests/battlefield_render_contract.gd`：B1/B2 回归。

完整代码差异请以 Git 为准，不在本文复制实现：

```bash
git diff -- main.gd scripts/isometric_column_batch.gd
git status --short
```

## 已定位并实施的修复

### 1. draw_mesh 的两个必要条件

黑屏不是单纯 shader 角度问题，而是两个 Godot 4.7 GL 细节叠加：

- `ProjectedTerrainBatch.commit()` 必须把像素 UV 除以 `texture.get_size()`，再用 `SurfaceTool.set_uv()` 写入归一化 UV。
- `draw_mesh()` 不继承 `draw_set_transform()`；Y-sort 的视觉偏移必须显式传入：

```gdscript
draw_mesh(mesh, texture, Transform2D(0.0, Vector2(0.0, _screen_y_offset)))
```

普通 `draw_texture()` / `draw_polygon()` 仍使用像素 UV；动态绘制路径仍需要 `draw_set_transform(Vector2(0, _screen_y_offset))`，结束后复原。

### 2. CUSTOM0 数据

- `CUSTOM0.xy`：默认投影下的顶面中心。
- `CUSTOM0.z > 0.5`：该顶点参与旋转。
- `CUSTOM0.w`：侧壁底边保持竖直向下的像素高度，不能用已经归一化的 UV.y 计算。
- `SurfaceTool` 使用 `CUSTOM_RGBA_FLOAT`；读回时 VERTEX 是 `PackedVector3Array`，CUSTOM0 是 `PackedFloat32Array`。

### 3. 邻格内部侧面剔除

`scripts/isometric_column_batch.gd` 已加入：

- `_cell`
- `_neighbor_stand_level_fn: Callable`
- `_is_side_exposed(axis, positive, level)`

`main.gd` 在 `configure()` 最后传入 `cell_stand_level`。当地块 level L 的侧面邻格 `stand_level >= L` 时，该面属于内部面，不绘制。B2 没有 Callable 时保持原行为。

此改动曾在真实主场景连续三次 Z 到 -135° 时消除逐格高墙，但其他角度仍暴露出下一项问题。

### 4. 柱内顶面剔除（当前正在收尾）

主世界每柱包含 level 0..stand_level 的多个完整地形块。此前投影路径给每一层都画顶面；低层顶面本来应被同柱上层遮住，全部画出会造成土壤顶面、暗带和错误层级。

当前源码已开始加入：

- `_terrain_top_level`
- `_is_visible_top(water_part, level)`
- `_draw_projected_terrain(..., level)`
- `configure()` 计算同柱最高实体地形 level
- 投影路径仅画最高实体顶面；水面 surface 仍画，湖床顶保留；外侧壁继续按邻格高度剔除。

这部分尚未完成验证，因为新增契约当前有测试代码自身的解析错误。

## 当前阻塞：先修测试解析错误

最近执行：

```bash
D:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/isometric_column_projection_contract.gd
```

失败原因在测试新增段，不是已证实的渲染算法错误：

- `DEFAULT_BASIS_X` / `DEFAULT_BASIS_Y` 未在测试作用域声明：改为 `ColumnBatchScript.DEFAULT_BASIS_X` / `ColumnBatchScript.DEFAULT_BASIS_Y`。
- `_projected_sector` 是 int 属性，不是函数：把 `_projected_sector()` 改为 `_projected_sector`。

修完先重新跑该契约。多层平地柱应只有 6 个顶面顶点；低邻格用例当前预期 18 个顶点（最高块两个外侧壁 + 最上顶面）。

## 逐角度画面验收

修正契约后重启主场景，依次检查 0°、-45°、-90°、-135°，以及 R 复位。Z 是逆时针，因此三次 Z 的目标角是 -135°，不是 +135°。

```text
godot_run_managed(scene="res://main.tscn")
runtime_inject_input(confirm=true, event={kind="key", keycode=90, pressed=true})
runtime_call_method(confirm=true, path=".:_iso_view", method="get_view_degrees")
runtime_screenshot()
```

必须每张截图实际检查：

- 地形是否完全消失或只剩植被/动物。
- 平面是否连续铺满，无背景大洞。
- 同高度平地是否无内部侧壁/高墙。
- 顶面 UV 是否仍对应正确材质，无棕色带状内部顶面。
- 柱子的 Y-sort 偏移是否正确，无整体竖直错位。

曾经有效的对照：共享 view_angle + 归一化 UV + 显式 draw_mesh Transform2D + 邻格侧面剔除，在 godot-13 的 -135° 截图中画面连续；但仍需在当前“柱内顶面剔除”版本重新验证所有角度。

## 性能现状

- 最初逐面 `draw_polygon`：约 1 FPS，约 8 万 draw calls，不可用。
- ArrayMesh/draw plan 缓存后性能改善，但持续 Q 曾只有 18–24 FPS。
- 实例 uniform 方案在 4225 柱上失败，出现实例缓冲区限制和 GL 错误；该路线已放弃，不要把 `project.godot` 的实例缓冲区试验加回。
- 每列独立 ShaderMaterial + shader `screen_y_offset` 的实验曾造成严重错位，也已放弃。
- 当前应保留：共享 view_angle、缓存网格/绘制命令、显式 draw_mesh 偏移、旋转视口裁剪。
- 最新柱内顶面剔除会减少大量内部面，可能改善性能，但尚未实测。

## 测试命令

按顺序运行，避免并行 Godot 进程争用调试端口：

```bash
D:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/isometric_column_projection_contract.gd
D:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/isometric_view_contract.gd
D:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/battle_screen_pick_contract.gd
D:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/battlefield_render_contract.gd
D:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/streaming_input_latency_contract.gd
```

历史上这些契约曾分别通过；最新未提交改动后必须全部重跑。部分既有测试退出时会打印 ObjectDB/RID 资源泄漏警告，但退出码为 0，需与本次 shader/script 错误区分。

## 临时探针与清理

以下文件只是定位工具，不应作为最终交付保留：

- `tests/mesh_draw_probe.gd`（及 `.uid`）：验证归一化 UV 与 draw_mesh transform。
- `tests/flat_rotation_probe.gd`、`.tscn`（及 `.uid`）：17×17 完全平地、每柱 8 层的隔离探针；曾证明单独平面在 ±45° 能连续铺满。

完成主场景验收后删除这些探针及其 `.uid`。保留正式契约 `tests/isometric_column_projection_contract.gd`。

当前没有可由本代理继续管理的运行中 Godot 进程；最后启动的 `godot-21` 已不在 managed process 列表中。不要操作用户自行启动的窗口。

## 工作区注意事项

- 当前 `git status --short` 显示 `main.gd`、`scripts/isometric_column_batch.gd` 已修改，并有上述 shader/测试/探针新文件。
- 早前可能由 Godot 4.7 自动修改的 `main.tscn`、插件主题等序列化变化不属于本功能，不要顺手回滚用户或其他进程的改动。
- 不修改世界采样、生态 RNG、种子或生成顺序；旋转只属于表现层。
- 不破坏 B2 `IsoCoords` 路径和默认角绘制。
- 完成后执行 `git diff --check`。

## Suggested skills

- 首先调用项目技能 `godot`（`.claude/skills/godot/SKILL.md`），按项目的 Godot 调试与验证流程继续。
- 下一轮完成或再次需要交接时调用 `handoff`。
- 遵循 `AGENTS.md`、`CLAUDE.md`、`rules/mcp-debugging.md` 和 `knowledges/project-debug-and-auto-verification.md`；截图许可本轮用户已明确给出。
