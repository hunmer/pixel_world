# 人物移动测试场景

`scenes/CharacterMovementTest.tscn` 是独立的角色图集与生态网格移动测试入口。它继承 `main.tscn` / `main.gd`，继续使用真实地形、流式生态、相机、插值和 `_cell_states[].blocks_movement()` 阻挡；不是另写一个 2D 平面移动 Demo，也不改变默认游戏入口。

## 运行

1. 在 Godot 4.7 编辑器中打开 `scenes/CharacterMovementTest.tscn`。
2. 按 **F6** 运行当前场景。
3. 默认角色为稳定 ID `002`，初始种子为 `20261119`。

`project.godot` 的主入口仍为 `res://scenes/Campaign.tscn`；本场景不需要也不应修改 `config/startup.cfg`。

## 键位

| 输入 | 行为 |
| --- | --- |
| WASD / 方向键 | 按生态世界规则移动一格，保留移动插值和地形/植物阻挡 |
| 同时按两个移动轴 | 采用最后按下的轴，不斜穿格子、不产生对角速度 |
| Q / X | 视角逆时针 / 顺时针旋转 90° |
| R | 继承父场景的相机复位 |
| Space + 拖动 | 继承父场景的抓取平移 |
| M | 打开 / 关闭世界地图；地图模态期间禁止移动和动作操作 |
| K / L | 上一个 / 下一个角色（002～021 循环） |
| U / I | 上一个 / 下一个编号动作 |
| J | 播放当前编号动作；移动中、持续按方向或动作播放中不会重入 |
| H | 停止并复位当前编号动作到 idle |
| P / O / E（含 Ctrl+E） | 本测试场景已隔离，不进入战斗、JSON 战场或地图编辑器 |

移动动作使用场景动态注册的 `character_test_left/right/up/down`，同时映射 WASD 与方向键。左右方向键不再旋转相机。退出场景时只移除本场景添加的 InputEvent / InputAction，保留预先存在的同名外部动作与事件。

以下状态禁止新的移动、切角色和动作操作：世界地图打开、SceneTree 暂停、窗口失焦、Control 持有键盘焦点。失焦会释放本场景移动动作并取消抓取状态；单次动作播放期间禁止网格移动。

## 素材来源与迁移

- 来源：用户提供的 `/Users/Zhuanz/Downloads/free-character-pack`（迁移完成后该源目录已按授权清理）。
- 工程位置：`assets/characters/free_character_pack/`。
- 内容：编号 002～021 的 20 张透明 PNG，以及原包 `README-Godot示例.md`、`免费包说明.txt`。
- 迁移方式：先复制全部 27 个源文件，逐文件核对 SHA-256，再复核目标字节；校验通过后才清理源文件。没有覆盖既有用户文件。
- 原始上游 `main.gd`、`player.gd`、两个 `.tscn` 与 `project.godot` 仅归档在 `upstream_example/`，该目录含 `.gdignore`，不会被本工程导入或执行。
- `manifest.json` 记录稳定角色 ID、文件名、逐张 SHA-256、帧规格、有效帧、循环、fps、方向和脚点。素材来源及“免费赠送”说明以随包原文为准，本测试不附加其他授权声明。

## 图集、方向与脚点

- 每张图为 **384 × 832**，6 列 × 13 行；单帧 **64 × 64**，最近邻过滤。
- 零基行 7 / 8 / 9 分别为 down / left / up；right 复用 left 行并水平镜像。四个正交相机角度都重新解析屏幕方向，停止移动后保留朝向。
- run 为 6 帧、8 fps 循环；idle 使用同一 run 行的第 0 帧。
- 其余行动作只命名为 `preview_00` 等编号，不推断攻击、施法或伤害语义，也不连接战斗结算。
- alpha 扫描确认：第 4、6 行只有帧 0～2 有效；其余编号行动作和 run 行均为帧 0～5。播放清单显式排除空白尾帧，所有编号动作均为单次播放，结束后回 idle。
- 脚点为帧内 **bottom-center `[32, 63]`**。Sprite3D 保持 `centered=true`，对应 `offset = (0, 31)`；世界像素比例为 `1/36`。注意 **Sprite3D 局部 Y 向上**，所以脚点位于帧中心下方时需要正 Y 偏移，不能沿用 2D 屏幕坐标的负 Y 直觉。这些定义属于新 `FreeCharacterSheet`，不复用旧 `CharacterSheet` 的 2304×288 单帧图和 140px 脚点。
- `pixel_size=1/36` 是本轮测试的初始世界尺度，不代表已经过最终美术尺寸验收。
- 用户反馈“可移动但看不到人”的最终根因是 `foot_offset()` 的 Y 符号：`offset.y=-31` 时 64×64 绘制矩形为 `(-32,-63,64,64)`，源帧不透明像素全部低于地形支撑面；改为 `+31` 后绘制矩形为 `(-32,-1,64,64)`，角色从脚底向上绘制。真实 Compatibility 同实例 A/B 已确认这一根因，因此不需要 `no_depth_test`、放大角色或修改地形遮挡。
- 当前仍使用完整 sheet + `Sprite3D.region_rect` 指定 64×64 源帧，并固定 `hframes=vframes=1`、`frame=0`；这是独立的帧状态约束，不再把早先的 AtlasTexture 绑定调整当作本次不可见问题的根因。方向由 animator 的行号/镜像决定，世界位置复用父场景。

## 实现边界

- `scripts/characters/free_character_sheet.gd`：manifest 读取、图集裁剪、有效帧、四向解析与独立缓存。
- `scripts/characters/free_character_animator.gd`：idle / run / preview 状态、8fps 时间推进、单次动作结束与防重入。
- `scripts/scenes/character_movement_test.gd`：继承父世界，覆盖角色绘制、输入路由和测试提示；移动仍调用父类 `_try_move`，每帧仍执行 `super._process(delta)`。
- 提示层使用 `PixelMargin`、`PixelVBox`、`PixelPanel` 与 `ComponentTheme` / `UITheme` token。
- 未修改 `main.gd`、`scripts/iso/character_sheet.gd`、`project.godot`、默认入口、启动配置或存档。

## 自动验收

统一 runner 最终验收命令（`--test` 后接多个名称，并显式 `--out`）：

```bash
python3 tools/run_contracts.py \
  --godot /Applications/Godot.app/Contents/MacOS/Godot \
  --test free_character_sheet character_movement_test character_sheet world_camera_navigation terrain_generation ui ui_components \
  --out .tmp/character_movement/runner_offset_all --no-warmup
```

结果：**pass 7 / 7**，汇总见 `.tmp/character_movement/runner_offset_all/summary.json`。

- `free_character_sheet`：`FREE_CHARACTER_SHEET_CONTRACT_OK checks=1677`，覆盖 20 张原字节哈希、全部行有效/空白帧、缓存隔离、四向与镜像、run 循环、单次动作和角色切换。
- `character_movement_test`：`CHARACTER_MOVEMENT_TEST_CONTRACT_OK checks=169`，覆盖真实世界冒烟、单格移动、真实占用阻挡、四角动画、动作不位移、切换、地图/焦点/暂停/失焦守卫、旧入口隔离、默认入口不变及 InputMap 精确清理。
- 可见性回归直接读取实际 `Sprite3D.region_rect`、`get_item_rect()` 和源帧不透明区域：除检查完整 sheet、64×64 源帧、无残留帧状态和相机投影外，还把图像向下的像素 Y 换算为 Sprite3D 向上的局部/世界 Y，断言不透明像素从脚底支撑面向上绘制，而不是埋入地形。待机、跑动、四个相机角、002↔003 切换和编号动作都执行这些断言。
- 同一最终版契约对旧 `offset=(0,-31)` 先运行，结果为 `checks=169 failures=19` / exit 1；仅修正新 `FreeCharacterSheet.foot_offset()` 符号后为 `checks=169` / exit 0。证据保存在 `.tmp/character_movement/offset_before_contract.log` 与 `.tmp/character_movement/offset_after_contract.log`。
- 相邻回归 `character_sheet`、`world_camera_navigation`、`terrain_generation`、`ui`、`ui_components` 也在上述同一轮中全部通过。

另有未登记在 manifest 的旧测试直接运行：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tests/world_key_input_contract.gd
```

结果：`WORLD_KEY_INPUT_CONTRACT_OK checks=4`。日志中若编辑器已占用调试端口，可能出现既有 `BreakpointRuntimeBridge ... 9081` 端口错误；它不属于上述断言失败。

## 图形验收与后续人工检查

本轮已取得用户授权并完成真实 **Godot 4.7.1 Compatibility** 画面对照：

- `.tmp/character_movement/offset_before_live.png`：运行实例保持 `offset=(0,-31)`，地形正常但角色不可见。
- `.tmp/character_movement/offset_positive_live.png`：同一实例只临时改为 `offset=(0,31)`，角色立即显示；随后恢复临时参数。
- 修改磁盘代码后，普通 `dbg_restart` 仍加载编辑器旧脚本；在授权内关闭并重新 `dbg_launch` 当前测试场景后，实测偏移已为 `+31`，`runtime_assert_node_state` 的 offset / pixel_size / region / frame / visible / transparency 共 8 项全部通过。
- `.tmp/character_movement/offset_fixed_final_live.png`：重新加载最终代码后的实际画面，002 角色清楚可见，脚底位于柱顶支撑面。

这证明本次“人物可移动但看不到人”的直接原因和最小修复有效。尚未逐帧人工审美验收全部 20 个角色、所有编号动作和每一种地形遮挡；动画观感、最终美术尺度、水面接触和三档分辨率布局仍可继续按 F6 人工检查，但不影响本次不可见根因的结论。
