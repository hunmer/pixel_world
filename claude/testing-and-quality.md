# 测试与质量

> 更新：2026-11-19（**契约扩到 110 项**：+装备 3〔equipment/equipment_icons/equipment_integration〕+物品图标 +沉浸舞台 +免费角色包 +人物移动测试 = 7 项；**macOS 全量基线 pass 105 / fail 0 / env-skip 5**〔HEAD e3df43b〕）。上一轮：2026-11-18（103 项，98/0/5）。

## 测试机制（契约自测 + 统一 runner）

契约本体仍是 GDScript 自测脚本（不依赖 GUT/WAT 等框架，`--script` 单文件可跑），
但**执行入口已统一**：`tools/run_contracts.py`（默认）按 `tests/contract_manifest.json`
选择/并发/计时/汇总，legacy 单契约命令保留。状态语义 `pass/fail/timeout/
environment-skip/executor-error` 与全部参数见 `docs/test_automation.md` §3。
形态清单：

### 1. `tests/*_contract.gd`（契约测试，`extends SceneTree`）

运行时实例化真实场景 / 模块，验证"契约"不变。约定：
- `_initialize()` → `call_deferred("_run")`。
- 失败用 `push_error(...)` / `_expect(cond, msg)` + `quit(1)`；成功以 `print("<NAME>_CONTRACT_OK")` 结尾。
- **地形 / 生成类测试用固化的 SHA-256 快照**（如 `EXPECTED_SEED_42_HASH`）采样大量格点，任何确定性回归都会让哈希变化而失败。

运行（headless；macOS 本机 `GODOT=/Applications/Godot.app/Contents/MacOS/Godot`，Windows 历史路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`）：
```bash
# 默认入口：统一 runner（选择/并发/超时/汇总/影响分析）
python3 tools/run_contracts.py --test terrain_generation --no-warmup

# legacy 单契约命令（等价于 runner 的 native 后端，调试单文件时最短路径）
"$GODOT" --headless --path . --script res://tests/terrain_generation_contract.gd
```
> Windows console 版 exe 的 stdout 全缓冲，管道下可能看不到输出 —— 用退出码为准。**首次 headless 运行会先做资源导入，耗时明显偏长属正常**（runner 默认先 `--import` 预热一次）。

`tests/contract_manifest.json` 共 **110 项**（105 契约默认跑 + 5 environment-skip 声明；另有探针 `flat_rotation_probe` / `mesh_draw_probe` / `level_up_visual_probe` 等，manifest 收录但不默认跑），分组覆盖：

| 类别 | 脚本（省略 `_contract` 后缀） |
| --- | --- |
| 地形 / 流式（5） | `terrain_generation`(SHA-256 快照)、`terrain_sampler`、`terrain_material_registry`、`streaming_input_latency`、`dynamic_landform` |
| 群系模块（2） | `biome_modules`、`module_extension`（+ `tests/fixtures/` 火山 biome 扩展样例） |
| 生态 / 群落（7） | `ecology_registry`、`ecology_resolver`、`community_runtime`、`community_spawner`、`community_state_store`、`flora_layers`、`ecology_logic_bench` |
| 动物（4） | `animal_behavior_registry`、`animal_group_distribution`、`animal_animation_state`、`aquatic_fauna` |
| 环境生物（2） | `ambient_registry`、`bird_renderer` |
| Cell 状态（2） | `cell_state`、`cell_state_integration` |
| 配置（2） | `config_manifest`、`startup_config` |
| 表现层 / 世界 UI（7） | `weather_performance`、`depth_of_field`、`audio_system`、`world_map_overlay`*、`game_hud`、`hint_bar`、`loading_screen` |
| 世界 3D 渲染（5） | `isometric_3d`、`isometric_column_projection`、`isometric_view`、`sunlight_3d`、`sunlight_3d_gl`* |
| 世界相机/导航（1） | `world_camera_navigation` |
| 世界→战棋（1） | `world_terrain_mapping`（7 种映射快照） |
| 战棋 3D / 战场 / 编辑器（18） | `battle_3d`、`battle_screen_pick`、`battlefield_render`、`battlefields`、`map_editor`、`map_editor_ui`、`battle_occluder`、`editor_selection`、`editor_block_picker`、`editor_region_clipboard`、`editor_region_preset_store`、`map_editor_region_ops`、**`map_editor_building`**、**`building_layout`**、**`building_interior`**、**`unit_status_badges`**、**`skill_icons`**、**`status_icons`**（后 8 个 2026-11-17/18 建筑/图标波新增） |
| 战棋玩法逻辑（13） | `battle_action_chain`、`battle_movement`、`attack_event`、`character_sheet`、`battle_ai_difficulty`、`battle_turn_visibility`、`reinforcement`、**`backstab`**、**`backstab_save_roundtrip`**、**`pincer`**、**`pincer_marks`**、**`profession_growths`**（九键）、**`trade`**（后 7 个战斗规则波新增） |
| 战棋表现 / 沉浸演出（10） | `battle_presentation_hooks`、`battle_result_presentation`、`immersive_battle_camera`、`immersive_battle_integration`、`encounter_transition`、**`level_up_presentation`**、**`battle_levelup_flow`**、**`battle_ui_preview`**、**`battle_ui_status`**、**`immersive_stage`**(818 行，2026-11-19) |
| **装备 / 物品图标（4）**★ | **`equipment`**(413)、**`equipment_integration`**(332，campaign⇄战斗全链)、**`equipment_icons`**、**`item_icons`**（2026-11-19 新增） |
| **冒险模式（4）**★ | **`campaign`**(1606 行)、**`campaign_ui`**、**`campaign_battle_integration`**、**`battle_drop`**（掉落独立 RNG + 限购 + settle 幂等；2026-11-17/18 新增） |
| 战棋持久化 / 会话（2） | `battle_save`、`game_session` |
| 战棋自动化 CLI（2） | `battle_automation`、`battle_cli`（+ `tests/fixtures/battle_scenarios/` JSON） |
| 对话系统（1） | `dialogue_demo` |
| 用户素材（9） | `user_asset_catalog`、`user_asset_editor`、`user_asset_pagination`、`user_asset_runtime`、`user_asset_source_live`* + 清单/渲染等扩展 |
| UI 组件库（2） | `ui`（含业务脚本禁直建控件扫描）、`ui_components`(1404 行) |
| 音效 / 特效（2） | `game_sfx`、`pixelfx` |
| 图鉴（1）★ | `skill_list`（技能图鉴） |
| **角色包 / 移动测试（2）**★ | **`free_character_sheet`**(128)、**`character_movement_test`**(522)（2026-11-19 新增） |
| 批量模拟（1） | `simulation` |

（标 `*` 的为 manifest environment-skip 声明项：headless GL / 本机源依赖等，`--run-env-skip` 可强制执行。）

另有 `tests/gdtest/`（gdtest 持久 worker 试点：3 文件 8 test，断言镜像
cell_state / ecology_resolver / animal_behavior_registry 原生契约，经
`--backend gdtest` 或 gdtest CLI 运行）与 `tests/benches/`（bench harness）、
`tests/fixtures/simulations/`（批量模拟 batch 夹具）。

`tests/fixtures/`：模块扩展夹具（自定义 scorer / 不完整 ambient renderer / 火山 biome + manifest/world/species/communities/materials）+ `battle_scenarios/`（quick_duel / deterministic_replay / scripted_victory / ai_difficulty_focus）。

### 2. `scripts/tests/*.gd` + `scenes/SkillTest.tscn`（战棋自测，`extends Node`）

`_ready()` 里自跑 `_ok/_pass/_fail/_print_summary` 框架：
- `scripts/tests/test_skills.gd` — 技能/物品/MP/冷却/buff 纯逻辑（**44/44 passed**，2026-11-11 复验）。
- `scripts/tests/debug_test.gd` — 职业/地形/武器/战斗/AI/回合/经验（**35/35 passed**，历史记录）。

### 3. `tools/build_blocks_manifest.test.mjs`（Node 契约，7 项）

用户素材清单生成器的幂等/校验测试：`node --test tools/build_blocks_manifest.test.mjs`（见 `docs/user_assets.md`）。

### 4. 声明式战场 CLI（回归 / 平衡模拟入口）

`tools/battle_cli.gd`：一份场景 JSON → 确定性对局 → 结构化战报 + 退出码（`docs/battle_automation.md`）。适合 CI 回归、平衡性批量模拟、bug 最小复现。

### 5. 批量模拟 runner（2026-11-16 新增）

`tools/run_simulations.gd -- --batch <json> [--runs N] [--out dir]`：按 batch 夹具
（`tests/fixtures/simulations/`）批量跑 BattleRunner 对局，输出逐次 JSON 指标与
不变量判定（确定性摘要 / 停机原因 / 步数上界 / 断言 / 退出码）；默认 5-20 次，
`--runs 1000` 容量模式显式开启（实测 3.6s）。配套 `godot-autosim` 最小接入
（`addons/godot_autosim/` + `tools/autosim_battle_adapter.gd`）。手册见
`docs/test_automation.md` §2。

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
| **`ui` 契约（两行分列台账）** | ✅ 复绿 | 2026-11-15 基线：红（map_editor.gd 直建 `Button.new()` 等）；2026-11-16 实测：**3 连过 exit=0**，根因已在后续修复中消除（现 scripts/scenes/map_editor.gd 无直建 Button/CheckButton/OptionButton），manifest 已更新为 pass |
| 统一 runner 交付（2026-11-16） | ✅ | `tools/run_contracts.py`（manifest 80 契约；27 单测全绿）+ `run_contract_baseline.sh` 兼容包装 + gdtest 试点 go（A→B→A 稳定）+ 批量模拟（1000 次 3.6s）。台账 `docs/test_automation_results.md`。manifest 现口径：known-fail 4 / environment-skip 5 / pass 71 |
| **known-fail 清零（2026-11-17）** | ✅ **75/80 全绿** | 团队四任务逐项定性后五项 known-fail 全转 pass：`isometric_view`（根因=HUD 预留列致契约"焦点=窗口中心"假设失效，探针实证投影数学无回归，契约改焦点实际渲染位取样+新增舞台中心断言）、`battle_action_chain`/`battle_presentation_hooks`（断言对齐 pixelfx 呈现链与素材优先设计+密闭性修复〔本机 settings.cfg 泄漏〕+附带修 `game_sfx.gd` Nil→Array 真 bug）、`map_editor_ui`（6 项断言按实现重锚）、`user_asset_editor`（`925fe0c` 吸管功能引入的真行为回归：素材选中被 PAINT 前置检查短路、取消不回退前景槽，已修）。口径 **pass 75 / known-fail 0 / env-skip 5**，manifest evidence 全记录 |
| **103 项扩容 + macOS 全量基线（2026-11-18）**★ | ✅ **98 pass / 0 fail / 5 env-skip / 0 timeout** | `python3 tools/run_contracts.py --all --jobs 4 --out .tmp/init_baseline_2026-11-18 --no-warmup`（本机 Godot 4.7.1，HEAD `e7ed380`）。扩容项：campaign 4（`campaign`/`campaign_ui`/`campaign_battle_integration`/`battle_drop`）、建筑 3（`building_layout`/`building_interior`/`map_editor_building`）、战斗规则/演出/图标约 15 项（backstab×2、pincer×2、`profession_growths`、`level_up_presentation`、`battle_levelup_flow`、`skill_icons`、`status_icons`、`skill_list`、`unit_status_badges`、`battle_ui_preview` 等）。manifest 无 known-fail；日志 `.tmp/init_baseline_2026-11-18/summary.tsv|json` |
| **110 项扩容 + macOS 全量基线（2026-11-19）**★ | ✅ **105 pass / 0 fail / 5 env-skip / 0 timeout** | `python3 tools/run_contracts.py --all --out .tmp/init_baseline_2026-11-19/`（本机 Godot 4.7.1，HEAD `e3df43b`）。扩容 7 项全过：装备 3（`equipment`/`equipment_integration`/`equipment_icons`）+ `item_icons` + `immersive_stage` + `free_character_sheet` + `character_movement_test`。manifest 无 known-fail；日志 `.tmp/init_baseline_2026-11-19/summary.tsv|json` |

## Lint / 类型检查

- **无独立 lint/格式化工具配置**（仓库无 `.gdformat`、`gdlint` 配置，无 CI 文件）。
- GDScript 静态类型：脚本普遍使用类型标注（`-> void`、`: int`），strict 模式下新代码必须完整标注。
- 质量主要靠：① 启动期 `_validate_ecosystem_config()`（配置校验，失败 abort），② 契约测试的 SHA-256 快照，③ 与改动匹配的自动化测试；仅需运行态验证时再用 MCP `runtime_assert_*`，不要以 `print` 后肉眼判断代替验收。

## 质量风险（本次扫描 + handoff 待办）

- ~~`main.gd` 4319 行双单体~~ **已拆分（2026-11-16）**：现 main.gd 2280 / map_editor.gd 1088 / battle.gd 2273（装配层形态）。**当前最大观察项**：`battle.gd` 2026-11-19 回涨到 **2273 行 / 122 函数**（+行动历史 + campaign 接线 + ImmersiveStage 接线），`campaign_session.gd` **1044 行 / 41 函数**（业务全在 autoload，+equip/unequip）——均未到拆分阈值红线，但新增能力继续内联会重走老路，建议下一批增量前先把 battle.gd 的记录 Tab/campaign 接线、campaign_session 的 settle 流程拆出（见 `claude/report.md` §1）。
- ~~红契约~~ **已清零**（2026-11-17），2026-11-19 基线 105 pass / 0 fail 保持全绿。
- **manifest 缺录 8 项（2026-11-19 发现）**：盘上 `tests/*_contract.gd` 共 119 个，manifest contracts 只录 110——真缺录 8 个（`backstab_save_roundtrip` / `isometric_camera_lifecycle` / `battle_key_input` / `world_key_input` / `battle_threat_data` / `battle_action_history` / `map_editor_units` / `map_editor_unit_edit`，均 11-17/18 提交），runner 每次都会告警"盘上存在但 manifest 缺少"。缺录 = 不会被默认跑到也不进 `--changed` 影响闭包，**建议尽快补录**；另 `campaign_battle_integration` 在 probes 区属 runner 误报（非缺录）。
- `meowa_tiles/heroes/`（24 png）未与 `data/professions.json` 8 职业映射（已知待办）。
- `story/` 设计 bible（13 职业/27 技能/25 道具/15 章）与 `data/` 实际（8/8/8 + campaign 6 关）差距大，实现时勿把目标态当运行时事实（差距清单见 `docs/gameplay_gap.md`；A2 战役结构已由 campaign 模式部分解决）。
- 110 项契约无 CI：回归靠本地手跑；统一 runner 已可一键全量 + JUnit（`python3 tools/run_contracts.py --all --run-env-skip --junit`），接入 CI 只差 runner 前置。
- 用户素材默认源 `http://127.0.0.1:8076/blocks.json` 为本机回环；源可配置（`asset_source.cfg`）+ 断源降级，但换机器仍需配置或自建源。
- `data/battlefields/` 混有 `contract_asset_map.json.bak`、`building_demo.json.bak` 脏文件（loader 只扫 `*.json` 不受影响，建议清理）；`assets/ui/tmp/` 切片中转目录待清。

## 执行测试的建议命令

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot   # macOS 本机
# GODOT=D:/Godot/Godot_v4.7.2-stable_win64.exe       # Windows 历史路径

# === 默认入口：统一 runner（docs/test_automation.md §3） ===
python3 tools/run_contracts.py --test terrain_generation --no-warmup   # 单契约
python3 tools/run_contracts.py --group ecology --jobs 3               # 组/标签 + 并发
python3 tools/run_contracts.py --changed --dry-run                    # 只跑受影响（预览）
python3 tools/run_contracts.py --all --run-env-skip --junit           # 全量 + JUnit
tools/run_contract_baseline.sh /tmp/out                               # 旧接口兼容包装

# === legacy 单契约（等价 native 后端，调试单文件时最短路径） ===
"$GODOT" --headless --path . --script res://tests/terrain_generation_contract.gd

# 批量模拟（docs/test_automation.md §2）
"$GODOT" --headless --path . --script res://tools/run_simulations.gd -- \
  --batch res://tests/fixtures/simulations/battle_determinism_fixed.json

# Node 契约（用户素材清单）
node --test tools/build_blocks_manifest.test.mjs
```
