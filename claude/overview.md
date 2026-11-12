# 架构总览

## 一句话定位

Pixel World 是一个 **Godot 4.7.2（GL Compatibility 渲染 + 3D 正交相机）** 单体游戏：按固定种子实时、确定性、流式地生成一个"无限"像素生态世界（地形 / 生物群系 / 植物群落 / 动物 / 天气 / 昼夜与阳光阴影）。世界自 2026-11-12 起以 **3D 正交(dimetric 2:1)渲染**呈现并支持 4 个离散视角旋转；其中嵌入**回合制战棋**子系统（按 P 就地战斗 B1 / 独立场景 B2）、**JSON 战场加载**（O）、**战场地图编辑器**（E）与 **Panku 运行时调试控制台**（~）。

## 关键技术栈

- **引擎**：Godot 4.7.2 stable，`renderer/rendering_method = "gl_compatibility"`；3D 物理引擎 Jolt Physics（3D 迁移后真实使用）。
- **渲染（双层形态）**：
  - **主世界**：Node2D 场景树 + `Camera3D` 正交 dimetric 相机（`scripts/iso/isometric_camera_3d.gd`——旋转只动相机、不重建地形）+ chunk 化真实 3D 柱地形（`scripts/iso/isometric_terrain_3d.gd`）+ `DirectionalLight3D` 阳光与地形阴影（`scripts/sunlight_system.gd`，时钟来自 DayNightSystem）。动物为 `AnimatedSprite3D`。
  - **战棋 B2 / 编辑器画布**：像素 Minecraft 式等距方块柱渲染（`scripts/iso/battlefield_renderer.gd`，复用世界管线 `isometric_column_batch` + `TerrainMaterialRegistry` 贴图 + 程序化水面）；旧平面色块 fallback 已删除。
  - 自写 `.gdshader`（仓库自有 5 个：水下动物 / 水深 / 景深 / 昼夜叠加 / 旋转地形）。
- **数据格式**：JSON 驱动（`config/` 与 `data/`），运行时懒加载、零硬编码策略原则。
- **测试**：GDScript headless 自测脚本（`extends SceneTree` 契约 37 个 / `extends Node` 战棋自测 2 个），无第三方测试框架。
- **调试**：`addons/breakpoint_mcp`（loopback JSON 桥，编辑器 9080 / 运行时 9081，MCP host 配合）+ `addons/panku_console`（游戏内 `~` 表达式 REPL，`dbg.*` 命令集）。

## 运行时形态与边界

```text
启动 project.godot (main_scene = res://main.tscn)
        │
        ▼
main.tscn (Node2D "Main" + "DebugConsoleCommands" 子节点)
        │
        ▼
main.gd (4099 行 / 174 函数)  ← 世界引擎中枢
   │  ├─ 流式生成：stream_extent 窗口内按需 _spawn_cell / _free_cell（网格坐标不变，渲染走 3D）
   │  ├─ 生态：TerrainSampler → CellContext → EcologyResolver → CellState → 渲染
   │  ├─ 动物：CommunitySpawner + WanderingAnimal（AnimatedSprite3D，行为栈）
   │  ├─ 3D 表现：IsometricCamera3D(旋转/缩放) + IsometricTerrain3D(chunk 柱地形)
   │  │           + SunlightSystem(DirectionalLight3D) + weather / day_night / dof / audio / fireflies
   │  ├─ HUD / 小地图 / 大地图(world_map_overlay + map_snapshot_renderer)
   │  └─ 入口键：P→B1/B2 战斗 │ O→JSON 战场列表(固定 B2) │ E→地图编辑器
        │
        ├─ P 且 inline_mode=true  → battle.gd 挂 main 场景树下（B1 就地，相机归 main.gd）
        ├─ P 且 inline_mode=false → change_scene_to_file(Battle.tscn)（B2 世界地形）
        ├─ O 选 JSON 战场         → _enter_battlefield(path)（固定 B2，地形与世界无关）
        └─ E                      → MapEditor.tscn（种子生成/地形编辑/阵营角色放置/保存 JSON）
```

### 两条并行子系统 + 一份设计 bible

1. **世界 / 生态子系统（原 pixel_world）**：`main.gd` 是事实中枢；`scripts/world/`、`scripts/ecology/`、`scripts/animals/` 是它调用的能力模块。设计原则是"**新增内容走配置/模块，不要往 main.gd 里加分支**"（见 `config/ecology/README.md`）。
2. **战棋战斗子系统（从 phaserjs 迁移）**：`scripts/core/`（纯逻辑）+ `scripts/systems/`（战斗结算）+ `scripts/iso/`（等距/3D 渲染层）+ `scripts/battle/`（场景编排助手）+ `scripts/editor/`（战场编辑器模型与画布）。与世界的唯一耦合点是 `scripts/core/world_to_chapter.gd`。
3. **`story/`（19 个 .md）**：完整的"古代魔法 + 多国争霸"战旗**设计 bible**（世界観/4 国/13 职业/8 角色/15 章/27 技能/25 道具/UI/音频/成就/新手引导）。注意它是**目标态设计**——当前 `data/` 只实现 8 职业/8 技能/8 物品，扩张时以 story 文档为准绳。

## 重要设计取舍

- **坐标级确定性**：相同 seed + 相同 cell 永远产出相同结果。`DeterministicRng`、`_cell_rand`、`_quantize` 等是确定性契约核心，**改这些会挂固化 SHA-256 快照测试**（`tests/terrain_generation_contract.gd`）。
- **"新增不修改，分支注入"**：B1 就地战斗对 `main.gd` 的改动全是 `if _battle_active:` 前置短路；B2 路径不动。战场入口（O/E）同样以独立方法注入（`_enter_battlefield` / `_open_map_editor`），不侵入既有流程。
- **渲染演进（2026-11-11 → 11-12）**：先尝试 2D 可旋转投影（`isometric_view.gd` + `isometric_column_batch.gd` + `shaders/isometric_terrain_rotate.gdshader`，任意角度连续旋转），因素材只在 4 个正交视角下能通过拼缝验收，最终收敛为 **`SUPPORTED_ANGLES = [0°, 90°, 180°, 270°]` 离散视角**，随后整体迁移到 **3D 正交渲染**（commit `33b7028` + `3189caf`）：角度变化只旋转 Camera3D，地形、生态状态与连续网格坐标全部保持不变。2D 旋转期的踩坑记录（draw_mesh UV / y-sort offset / CUSTOM0 / 柱内顶面剔除）见 `handoff/2026-11-11-isometric-rotation.md`。
- **配置分层（双轨）**：`config/ecosystems.json`（旧版，运行时实际读取入口）与 `config/ecology/manifest.json` + 模块化 biome/species/communities（新版，逐步迁移）并存，由 `_compile_ecosystem_config` 编译。`legacy_bundles.json` 仅为旧布局兼容，**新内容禁止使用**。
- **战场渲染统一**：B2 战场与编辑器画布共用 `BattlefieldRenderer`（等距方块柱），地形高度规则：water h1 / plain・forest・village h2 / fort h3 / wall h4 / mountain h5。
- **批量绘制优先**：水、岸浪、天气、飞鸟等高密度元素走批量绘制/受限呈现槽位，避免每格一个 `_process` 节点。

## 仓库边界

- **项目位置**：`E:/pixel_world`（**已从 G:/ 迁移**）。Godot 可执行文件 `D:/Godot/Godot_v4.7.2-stable_win64.exe`（不在 PATH）。
- **源项目引用**：战棋代码迁移自外部 phaserjs 项目（不在本仓库）；编辑器 UI 扩展参考 `D:/phaserjs/godot/scripts/scenes/map_editor.gd`。
- **handoff/ 与 HANDOFF.md**：`HANDOFF.md` 是"需求 → 入口"快速索引（2026-11-11）；`handoff/` 按日期归档专题交接文档。
- **不属于本仓库的内容**：`.godot/`（引擎生成物）、`/builds/`、`/exports/`、`/android/`。
