# 架构总览

## 一句话定位

Pixel World 是一个 **Godot 4.7（GL Compatibility 渲染）/ Node2D** 单体 2D 游戏：在等距(isometric)视口下，按固定种子实时、确定性、流式地生成一个"无限"像素生态世界（地形 / 生物群系 / 植物群落 / 动物 / 天气 / 昼夜 / 音乐），并在其中嵌入了从另一个项目迁移来的**回合制战棋战斗**系统，可在真实世界地形上"就地战斗"。

## 关键技术栈

- **引擎**：Godot 4.7，`renderer/rendering_method = "gl_compatibility"`（桌面端覆盖最广），3D 物理引擎选用 Jolt Physics（项目实际为 2D，此项基本不影响玩法）。
- **渲染**：Node2D + 程序化批量绘制（`MultiMesh` / 自绘 `_draw`）+ 自写 `.gdshader`（水下动物、水深、景深等）。
- **数据格式**：JSON 驱动（`config/` 与 `data/`），运行时懒加载、零硬编码策略原则。
- **测试**：GDScript headless 自测脚本（`extends SceneTree` / `extends Node`），无第三方测试框架。
- **调试桥**：`addons/breakpoint_mcp`（vendored 第三方插件，loopback JSON 桥接编辑器与运行时）。

## 运行时形态与边界

```text
启动 project.godot (main_scene = res://main.tscn)
        │
        ▼
Title.tscn (标题，"进入世界" → change_scene main.tscn)
        │
        ▼
main.gd (Node2D, root)  ← 世界引擎，3886 行，约 90 个函数
   │  ├─ 流式生成：stream_extent 窗口内按需 _spawn_cell / _free_cell
   │  ├─ 生态：TerrainSampler → CellContext → EcologyResolver → CellState → 渲染
   │  ├─ 动物：CommunitySpawner + WanderingAnimal（含逃跑/群体/水域行为）
   │  ├─ 表现层系统：weather / day_night / depth_of_field / world_audio / fireflies
   │  ├─ HUD / 小地图 / 大地图(world_map_overlay)
   │  └─ 按 P → _enter_battle()  ──┐
                                   │ Settings.battle_inline_mode
                  ┌────────────────┴───────────────┐
                  ▼ true (B1 就地)                 ▼ false (B2 切场景)
   battle.gd 挂在 main 场景树下            change_scene_to_file(Battle.tscn)
   战场坐标 = 世界 origin + 局部 cell        battle.gd 作为独立场景
                  │                                   │
                  └───────────── battle_finished ─────┴── _exit_battle 恢复
```

### 两条并行子系统

1. **世界 / 生态子系统（原 pixel_world）**：`main.gd` 是事实中枢，几乎所有世界逻辑都集中在此单文件；`scripts/world/`、`scripts/ecology/`、`scripts/animals/` 是它调用的能力模块。设计原则是"**新增内容走配置/模块，不要往 main.gd 里加分支**"（见 `config/ecology/README.md` 的"No biome ID / noise ID / surface ID ... should be added to main.gd"）。
2. **战棋战斗子系统（从 phaserjs 迁移）**：`scripts/core/`（纯逻辑，零 Godot 依赖概念上对应 TS 源）+ `scripts/systems/`（战斗系统）+ `scripts/iso/`（2D 等距渲染层，从 3D 重写）+ `scripts/battle/`（场景编排助手）。与世界的唯一耦合点是 `scripts/core/world_to_chapter.gd`（把世界 cell 翻译成战棋 chapter）和 `main.gd` 里的 7 个侵入点。

## 重要设计取舍

- **坐标级确定性**：相同 seed + 相同 cell 永远产出相同结果，任意方向探索都稳定且唯一。`DeterministicRng`、`_cell_rand`、`_quantize` 等是确定性契约的核心。**改这些会破坏测试里固化的 SHA-256 快照**（见 `tests/terrain_generation_contract.gd`）。
- **"新增不修改，分支注入"**：B1 就地战斗对 `main.gd` 的改动全是 `if _battle_active:` 前置短路，false 时零影响；B2 路径代码一字不动。这套范式照搬了项目既有的 `is_world_map_open` 模态拦截范式。
- **配置分层（双轨）**：存在 **`config/ecosystems.json`（旧版"首次匹配 ecology"，运行时实际读取入口）** 与 **`config/ecology/manifest.json` + 模块化 biome/species/communities（新版，逐步迁移）** 两套。`main.gd._load_ecosystem_config` / `_compile_ecosystem_config` 负责把它们编译为运行时结构。`legacy_bundles.json` 仅为兼容旧布局而存在，**新内容禁止使用**。
- **批量绘制优先**：水、岸浪、天气、飞鸟等高密度/远距离元素走批量绘制或受限呈现槽位，避免为每个水格或远鸟建独立 `_process` 节点（见 README "Rendering Details"）。
- **Node2D 无 offset 的妥协**：战棋单位用 `position + z_index=10` 而非 y-sort 双轨（与 `wandering_animal` 的双轨设计不同），高地地形可能遮挡单位 —— 这是已知待办。

## 仓库边界

- **源项目引用**：`HANDOFF.md` 多次引用 `phaserjs/progress.md` 等路径，但**本仓库不含 `phaserjs/` 目录**（那是迁移来源项目，不在本仓库内）。如需追溯战棋代码出处，需回到外部 phaserjs 项目。
- **不属于本仓库的内容**：`.godot/`（引擎生成物，已 gitignore）、`builds/`、`exports/`、`/android/`。
