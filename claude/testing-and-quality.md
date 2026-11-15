# 测试与质量

> 更新：2026-11-15（第二轮增量：契约 69→78 个；建立 macOS 全量基线 62/72；新增增援/地形映射/编辑器区域操作等 6 契约）。

## 测试机制（无第三方框架）

全仓库**无 GUT / WAT 等测试框架**，测试是 GDScript 自测脚本，三种形态：

### 1. `tests/*_contract.gd`（契约测试，`extends SceneTree`）

运行时实例化真实场景 / 模块，验证"契约"不变。约定：
- `_initialize()` → `call_deferred("_run")`。
- 失败用 `push_error(...)` / `_expect(cond, msg)` + `quit(1)`；成功以 `print("<NAME>_CONTRACT_OK")` 结尾。
- **地形 / 生成类测试用固化的 SHA-256 快照**（如 `EXPECTED_SEED_42_HASH`）采样大量格点，任何确定性回归都会让哈希变化而失败。

运行（headless；macOS 本机 `GODOT=/Applications/Godot.app/Contents/MacOS/Godot`，Windows 历史路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`）：
```bash
"$GODOT" --headless --path . --script res://tests/terrain_generation_contract.gd
```
> Windows console 版 exe 的 stdout 全缓冲，管道下可能看不到输出 —— 用退出码为准。**首次 headless 运行会先做资源导入，耗时明显偏长属正常。**

`tests/` 共 **80 个 .gd**（**78 个契约** + 2 个探针 `flat_rotation_probe` / `mesh_draw_probe`），覆盖：

| 类别 | 脚本（省略 `_contract` 后缀） |
| --- | --- |
| 地形 / 流式（5） | `terrain_generation`(SHA-256 快照)、`terrain_sampler`、`terrain_material_registry`、`streaming_input_latency`、`dynamic_landform` |
| 群系模块（2） | `biome_modules`、`module_extension`（+ `tests/fixtures/` 火山 biome 扩展样例） |
| 生态 / 群落（6） | `ecology_registry`、`ecology_resolver`、`community_runtime`、`community_spawner`、`community_state_store`、`flora_layers` |
| 动物（4） | `animal_behavior_registry`、`animal_group_distribution`、`animal_animation_state`、`aquatic_fauna` |
| 环境生物（2） | `ambient_registry`、`bird_renderer` |
| Cell 状态（2） | `cell_state`、`cell_state_integration` |
| 配置（2） | `config_manifest`、`startup_config` |
| 表现层 / 世界 UI（7） | `weather_performance`、`depth_of_field`、`audio_system`、`world_map_overlay`、`game_hud`、`hint_bar`、`loading_screen` |
| 世界 3D 渲染（5） | `isometric_3d`、`isometric_column_projection`、`isometric_view`、`sunlight_3d`、`sunlight_3d_gl` |
| 世界相机/导航（1） | `world_camera_navigation` |
| 世界→战棋（1） | `world_terrain_mapping`（cell_context_to_terrain 7 种映射快照，2026-11-15 新增） |
| 战棋 3D / 战场 / 编辑器（12） | `battle_3d`、`battle_screen_pick`、`battlefield_render`、`battlefields`、`map_editor`、`map_editor_ui`、`battle_occluder`、`editor_selection`、`editor_block_picker`、`editor_region_clipboard`、`editor_region_preset_store`、`map_editor_region_ops`（后五个 2026-11-15 编辑器波新增） |
| 战棋玩法逻辑（7） | `battle_action_chain`、`battle_movement`、`attack_event`、`character_sheet`、`battle_ai_difficulty`、`battle_turn_visibility`、`reinforcement`（增援刷入/防提前判胜，2026-11-15 新增） |
| 战棋表现 / 沉浸演出（5） | `battle_presentation_hooks`、`battle_result_presentation`、`immersive_battle_camera`、`immersive_battle_integration`、`encounter_transition` |
| 战棋持久化 / 会话（2） | `battle_save`、`game_session` |
| 战棋自动化 CLI（2） | `battle_automation`、`battle_cli`（+ `tests/fixtures/battle_scenarios/` 4 个场景 JSON） |
| 对话系统（1） | `dialogue_demo` |
| 用户素材（5） | `user_asset_catalog`、`user_asset_editor`、`user_asset_pagination`、`user_asset_runtime`、`user_asset_source_live` |
| UI 组件库（2） | `ui`（含业务脚本禁直建控件扫描）、`ui_components` |
| 音效（1） | `game_sfx` |
| 特效库（1） | `pixelfx` |

`tests/fixtures/`：模块扩展夹具（自定义 scorer / 不完整 ambient renderer / 火山 biome + manifest/world/species/communities/materials）+ `battle_scenarios/`（quick_duel / deterministic_replay / scripted_victory / ai_difficulty_focus）。

### 2. `scripts/tests/*.gd` + `scenes/SkillTest.tscn`（战棋自测，`extends Node`）

`_ready()` 里自跑 `_ok/_pass/_fail/_print_summary` 框架：
- `scripts/tests/test_skills.gd` — 技能/物品/MP/冷却/buff 纯逻辑（**44/44 passed**，2026-11-11 复验）。
- `scripts/tests/debug_test.gd` — 职业/地形/武器/战斗/AI/回合/经验（**35/35 passed**，历史记录）。

### 3. `tools/build_blocks_manifest.test.mjs`（Node 契约，7 项）

用户素材清单生成器的幂等/校验测试：`node --test tools/build_blocks_manifest.test.mjs`（见 `docs/user_assets.md`）。

### 4. 声明式战场 CLI（回归 / 平衡模拟入口）

`tools/battle_cli.gd`：一份场景 JSON → 确定性对局 → 结构化战报 + 退出码（`docs/battle_automation.md`）。适合 CI 回归、平衡性批量模拟、bug 最小复现。

## 已知验证状态

| 项 | 状态 | 说明 |
| --- | --- | --- |
| `SkillTest.tscn` | ✅ 44/44 | 技能/物品/MP/冷却/buff（2026-11-11 复验） |
| `debug_test.gd` | ✅ 35/35 | 战斗逻辑（历史，phaserjs 期跑过） |
| UI 组件库 | ✅ | `ui_components_contract` headless **1062 checks**（2026-11-15 复验通过，编辑器波扩容自 735）+ MCP 画廊运行态验收 |
| 用户素材 | ✅ | 5 个 user_asset_* 契约 + node --test 7 项（docs/user_assets.md 记录；`user_asset_source_live` 需本机 8076 源） |
| 沉浸战斗演出 | ✅ | handoff/2026-11-14-immersive-battle-presentation.md 记录契约 + 运行态验收通过 |
| `tests/game_hud_contract.gd` | ✅ 已修复 | `e8fda38` 改造为 headless 可跑，2026-11-15 基线通过 |
| **6 个新契约（2026-11-15 编辑器/增援波）** | ✅ 全过 | `reinforcement`、`world_terrain_mapping`(22 checks)、`editor_block_picker`、`editor_region_clipboard`(116 asserts)、`editor_region_preset_store`(73 asserts)、`map_editor_region_ops`（本次扫描实测） |
| 基线后受影响复跑（2026-11-15 晚） | ⚠️ 4/6 | ✅ `editor_selection` / `hint_bar` / `battlefield_render` / `ui_components`(1062)；❌ **`ui`**（map_editor.gd 仍有 `Button.new()`@943 / `CheckButton.new()`@1410 / `OptionButton.new()`@2124 直建控件）、❌ **`map_editor_ui`**（1024×640 与 1280×800 侧栏未保持 320px；改 z 后实际重建的单块 level=6）——均待修 |
| 全量契约基线 | ⚠️ 62/72 通过 | **2026-11-15 macOS 全量基线**（HEAD `3a08327`，`tools/run_contract_baseline.sh`）：6 失败（battle_action_chain / battle_presentation_hooks / isometric_view / map_editor_ui / ui / sunlight_3d_gl[headless 环境限制，非回归]）、4 超时（action_anim / immersive_battle_camera / world_map_overlay 均 autoload 依赖编译失败挂起；user_asset_source_live 依赖本机 8076 源）。详见 [docs/testing_baseline_2026-11-15.md](../docs/testing_baseline_2026-11-15.md)。其后契约总数 72→78 |

## Lint / 类型检查

- **无独立 lint/格式化工具配置**（仓库无 `.gdformat`、`gdlint` 配置，无 CI 文件）。
- GDScript 静态类型：脚本普遍使用类型标注（`-> void`、`: int`），strict 模式下新代码必须完整标注。
- 质量主要靠：① 启动期 `_validate_ecosystem_config()`（配置校验，失败 abort），② 契约测试的 SHA-256 快照，③ MCP 调试桥的 `runtime_assert_*` 自动断言（AGENTS.md 要求：改代码后加 L1 日志 / L2 断言 / L3 断点验证，不要 `print` 后肉眼判断）。

## 质量风险（本次扫描 + handoff 待办）

- `main.gd` 单文件 **4319 行 / 176 函数**、`map_editor.gd` **3285 行 / 150 函数** —— 双单体职责高度集中，可维护性风险（拆分均为 roadmap P3 项；map_editor 增长最快）。
- **两个红契约待修**：`ui`（map_editor.gd 三处直建控件）与 `map_editor_ui`（侧栏宽度 / z 重建断言）——2026-11-15 编辑器波的回归，见上表。
- `meowa_tiles/heroes/`（24 png）未与 `data/professions.json` 8 职业映射（已知待办）。
- `story/` 设计 bible（13 职业/27 技能/25 道具）与 `data/` 实际（8/8/8）差距大，实现时勿把目标态当运行时事实（差距清单见 `docs/gameplay_gap.md`）。
- 78 个契约无 CI：回归靠本地手跑；macOS 基线已建立（2026-11-15），剩 6 失败 + 4 超时待归零。
- 用户素材默认源 `http://127.0.0.1:8076/blocks.json` 为本机回环；源已可配置（`asset_source.cfg`）+ 断源降级，但换机器仍需配置或自建源。
- `data/battlefields/contract_asset_map.json.bak` 脏文件混在战场目录（loader 只扫 `*.json` 不受影响，建议清理）。

## 执行测试的建议命令

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot   # macOS 本机
# GODOT=D:/Godot/Godot_v4.7.2-stable_win64.exe       # Windows 历史路径

# 单个契约
"$GODOT" --headless --path . --script res://tests/terrain_generation_contract.gd

# 跑全部契约（Git Bash / zsh；首次运行含导入耗时）
for t in tests/*_contract.gd; do
  "$GODOT" --headless --path . --script "res://$t" >/dev/null 2>&1 || echo "FAIL: $t"
done

# Node 契约（用户素材清单）
node --test tools/build_blocks_manifest.test.mjs
```
