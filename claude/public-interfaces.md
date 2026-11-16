# 对外接口

> 更新：2026-11-16（新增统一契约 runner CLI、批量模拟 CLI、autosim 接入、gdtest 试点；拆分后模块 API 形态）。上一轮：表现层 autoload、用户素材服务、UI 组件库、战斗自动化 CLI。本项目是**单机游戏**，除调试桥与素材清单源外不暴露 REST API / WebSocket / SDK；本文件列出"接口"的现实形态：**玩家输入映射**、**跨场景 / 跨模块的代码契约**、**JSON 战场文件格式**、**自动化 CLI**、**调试通道**。

## 玩家输入映射（`project.godot [input]` + `main.gd._unhandled_input` @ 3608）

### 世界探索（main.gd）

| 操作 | 动作 | 实现位置 |
| --- | --- | --- |
| `WASD` / 方向键 | 沿等距网格移动（←→ 已被旋转占用，移动用 WASD） | `_input_dir` → `_try_move` |
| `Shift` | 加速（`fast_multiplier=3.0`） | `_try_move` |
| 鼠标滚轮 / `+` / `-` | 缩放（zoom 0.5–4） | `_zoom_step` |
| `F` | 复位缩放到默认档 | `_unhandled_input` |
| `Z` / `Q` / `←` | 视角逆时针旋转 90° | `_cam.rotate_step(-1)` |
| `X` / `→` / `E`(战斗中) | 视角顺时针旋转 90° | `_cam.rotate_step(1)` |
| 中键拖拽 | 平滑旋转视角（像素差 → 角度） | `_view_dragging` → `_cam.drag_by` |
| `R` | **复位视角旋转**（不再是重新生成！） | `_cam.reset_rotation()` |
| `Ctrl+R` | 重新生成世界（新种子） | `_regenerate(0)` |
| `M` | 开关大地图 | `_toggle_world_map` |
| `T` / `Shift+T` | 切换天气 / 恢复自动天气 | → weather_system |
| `N` / `Shift+N` | 切换昼夜 / 恢复自动昼夜 | → day_night_system |
| `B` | 切换景深 | → depth_of_field_system |
| `P` | 进入战斗（B1/B2 由设置决定） | `_enter_battle` |
| `O`（非战斗时） | 打开 JSON 战场列表面板 | HUD `toggle_battlefield_panel` |
| `E`（非战斗时） | 打开战场地图编辑器 | `_open_map_editor` |
| `~` | 呼出 Panku 调试控制台（REPL） | autoload `Panku` |

> 视角只支持 4 个正交角度（0/90/180/270，`isometric_view.gd SUPPORTED_ANGLES`）——素材逐角度验收仅通过四视角，其余角度会出现地形拼缝。

### 战斗（battle.gd + project.godot [input]）

| 输入动作 | 默认键 | 用途 |
| --- | --- | --- |
| `confirm` | Z / Enter | 选格 / 确认菜单 |
| `cancel` | Esc | 取消移动 / 返回 |
| `end_turn` | E | 结束回合 |

battle.gd 另处理鼠标选格、键盘移动光标。B1 相机由 main.gd 处理：中键或 `Space`+左键拖拽平移、边缘滚屏、滚轮缩放（编辑器画布还支持右键拖拽平移）。**演出播放中可按键快进/跳过**（`battle_ui.gd opening_finished/result_finished/presentation_finished` 均带 `skipped` 参数）。

### 组件画廊 / 特效画廊（独立场景）

| 场景 | 进入 | 退出 |
| --- | --- | --- |
| `scenes/UIComponentGallery.tscn` | 编辑器 F6 / 手动运行（16 组件 × 6 页交互画廊） | Esc |
| `scenes/PixelFxGallery.tscn` | 手动运行 | — |

### 调试启动快捷键（`startup_config.gd`）

F5 直跑时若 `auto_open_last_scene=true`，自动从 `Game.tscn` 中转进 `last_scene`；`--battlefield` / `--reset-battle` 命令行优先级更高。详见 `docs/startup_config.md`。

## 跨场景代码契约

### `SceneArgs`（autoload）— 唯一的跨场景传参通道

```gdscript
SceneArgs.battle_args = {
    "chapter": <Dictionary>,          # 必填：world_to_chapter 或 battlefield_loader 产物（同构）
    "return_to": "res://main.tscn",   # 可选，B2 结束后回到哪
    "world": <main.gd 实例>,          # 仅 B1 注入；存在则 _b1_mode=true
    "save_identity": "bf:res/xxx",    # 可选：战旗持久化身份（GameSession 分配）；空 = 本局不存档
    "save_state": <Dictionary>,       # 可选：恢复进度的完整状态（GameSession 从存档读出）
    "save_notice": "..."              # 可选：一次性提示文案（重置 / 内容变更 / 损坏回退）
}
SceneArgs.map_editor_return_to = "res://main.tscn"  # 编辑器保存退出后回哪（默认世界）
```

### `GameSession`（autoload，`scripts/scenes/game_session.gd`）— 战旗会话路由与持久化

| 接口 | 说明 |
| --- | --- |
| `prepare_entry() -> Dictionary` | 冷启动决策：`--battlefield`（id/路径/文件名）> 最近存档 > 默认 `plains_skirmish`；消费一次性 `--reset-battle[=id]`（进程内只消费一次）。最近是世界就地战旗（`world:` 身份）时直接按档案快照 resume（B2）。返回 `{mode: resume\|fresh\|list, identity, chapter, state, notice, ...}` |
| `prepare_entry_for(identity, reset) -> Dictionary` | 战场列表点选进入（同上结构） |
| `prepare_world_entry(identity, chapter) -> Dictionary` | 世界内按 P：同身份有档案 → resume（内容变更时带提示），无 → fresh（用刚构建的 chapter） |
| `open_battle(identity, kind, source, initial_chapter)` | 任何入口进战斗前登记（深拷贝 initial 快照 + 内容签名），置 `in_session=true` |
| `commit(chapter, state) -> Dictionary` | 完整行动边界提交：codec 组装 → store 原子落盘 → 刷新最近索引 |
| `identity_for_battlefield(info)` | `bf:res|user/<id>`（无 id 旧文件回退 `<file>` 文件名） |
| `identity_for_world_chapter(seed, origin)` | `world:<seed>/<x>/<y>`（同世界同位置 = 同战旗） |
| `list_battlefields_checked()` / `reset_battlefield(identity)` | 列表 UI（含存档摘要 peek）/ 手动重置 |

**存档落盘（`scripts/core/battle_save_store.gd` + `battle_save_codec.gd`，version=1）**：`user://battle_saves/`，文件名 = 身份清洗 + sha1 前 8；tmp+bak 两段式原子写，主档损坏回退 `.bak`，索引 `index.json` 损坏时扫描自恢复。内容 = 开局 initial 快照 + 当前 chapter（含死亡单位、冷却、buff、物品次数）+ state（回合/阶段/托管偏好/胜负）。新版本存档（version 更大）拒绝恢复且**不覆盖**，停在战场列表。测试：`tests/battle_save_contract.gd`、`tests/game_session_contract.gd`。

**命令行参数**：`--battlefield=<id|路径|文件名>` 显式进入某战场（优先级最高）；`--reset-battle` / `--reset-battle=<id|路径>` 一次性重置目标档案（其余档案保留，命令行参数不持久化、天然单次生效）。

### `Settings`（autoload）— 用户偏好

| 成员 | 类型 | 默认 | 含义 |
| --- | --- | --- | --- |
| `battle_inline_mode` | bool | true | true=就地战斗(B1) / false=独立场景(B2) |
| `set_battle_inline_mode(v)` / `save()` | 方法 | — | 持久化到 `user://settings.cfg` |

### 表现层 autoload（2026-11 新增三个）

| Autoload | 脚本 | 公共接口 | 说明 |
| --- | --- | --- | --- |
| `Sfx` | `scripts/audio/game_sfx.gd` | `play(cue, throttle_seconds=0.0) -> bool`；`play_step(terrain_type)`；`play_world_step(context)`；`play_low_hp()` | 全局音效池（`res://assets/audio/sfx`，10 池）；按钮声经 `SceneTree.node_added` 自动挂接（meta `_sfx_ui_attached`，**无需手动接线**） |
| `LoadingScreen` | `scenes/LoadingScreen.tscn` + `scripts/ui/loading_screen.gd` | `show_loading(text="")` / `hide_loading()` / `set_loading_text(t)` / `is_loading_shown()` | 幂等全局遮罩，`MOUSE_FILTER_IGNORE` 不拦输入；同步重活前弹层反馈（战斗沉浸演出预热用） |
| `GameCursor` | `scripts/game_cursor.gd` | 全局游戏光标（纹理切换/战斗态） | 世界/战斗共用 |

## 用户素材服务（`scripts/assets/`，2026-11-14 新增）

外部素材（像素方块图）经**本机 HTTP 清单源**导入游戏，供编辑器/战场渲染消费。运维手册：`docs/user_assets.md`。

### `UserAssetService`（`user_asset_service.gd`，非 autoload —— 场景内实例化）

- 默认源 `DEFAULT_SOURCE_URL = "http://127.0.0.1:8076/blocks.json"`；blob/清单落盘 `user://custom_assets/`（`blobs/` + library JSON）。
- **信号**：`manifest_loaded(result)` / `asset_ready(asset_id)` / `asset_failed(asset_id, error)` / `source_changed(url)`。
- 主要接口：`set_source_url(url)` / `request_manifest()` / `request_asset_image(id)` / `get_texture(id)`（LRU 64）/ `list_assets()` / `find_by_id(id)` / `find_by_sha(sha)` / `get_asset_state(id)` / `remove_asset(id, keep_blob=true)` / `update_asset(id, changes)` / `import_local_file(path, kind)` / `import_image_bytes(...)`。
- descriptor 契约：`id / kind / image / sha256 / render{mode: full|pivot|scale|footprint, ...}`；导入幂等（sha 去重）。
- 并发限制：`MAX_CONCURRENT_REQUESTS=3`，超时 10s，重试 2 次。

### `UserAssetVisualAdapter`（`user_asset_visual_adapter.gd`）

渲染侧适配：`resolve(asset_id) / resolve_many(ids)` → 视觉描述（含烘焙贴图）；`build_visual(descriptor, image)` / `bake_image(...)`；`placeholder_visual(id)`（缺图占位）；`visual_for_entries(props, tile_overrides)`（编辑器/战场批量解析）；烘焙缓存 `invalidate_baked(id)`。

## UI 组件库（`ui/`，2026-11 新增）

- 16 个 `@tool` 像素风组件：`PixelButton / PixelCheckButton / PixelOptionButton / PixelDropdown / PixelLineEdit / PixelTextArea / PixelSlider / PixelSpinBox / PixelProgressBar / PixelTabs / PixelPanel / PixelPopup / PixelImage / PixelIcon / PixelAudioPlayer / PixelVideoPlayer`（`ui/components/pixel_*.gd`）。
- 主题：`ui/theme/component_theme.gd` — `ComponentTheme.create()` 每次**新建独立 Theme**（不污染项目默认主题）。
- 文档：`ui/README.md`（304 行：设计原则、用法、测试）。交互画廊 `scenes/UIComponentGallery.tscn`（F6）。
- headless 契约：`tests/ui_contract.gd`（735 checks）。
- ⚠️ **现有业务 UI（battle_ui / map_editor / HUD）尚未迁移到该库**——新旧两套并存。

## 战斗自动化 CLI（`tools/battle_cli.gd`，2026-11 新增）

无头跑战棋：场景 JSON → 结算 → 事件流/结果。手册：`docs/battle_automation.md`。

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tools/battle_cli.gd -- --scenario res://tests/fixtures/battle_scenarios/quick_duel.json --seed 42 --out user://tmp/battle_out
# 或内联场景：--scenario-json '{"version":1,"id":"tiny","battlefield":"res://data/battlefields/arena_1v1.json","seed":1,"factions":{"player":{"mode":"ai"},"enemy":{"mode":"ai"}}}'
```

- 场景 fixture 目录：`tests/fixtures/battle_scenarios/*.json`（`quick_duel`、`deterministic_replay` 等）。

- 产物：`events.jsonl`（逐事件流）/ `result.json`（终局+断言）/ `summary.txt`。
- **退出码契约**：`0` 正常且断言通过；`1` 断言失败；`2` 输入/非法操作；`3` 步数上限（僵持保护）；`4` 输出/运行失败。
- 内核 API：`BattleScenarioLoader.load_from_file(path, seed_override)` / `load_from_dict(d, fallback_id, seed_override)` → scenario；`BattleRunner.run(scenario)`（static）→ result；`battle_action_resolver.gd` 是 **battle.gd 与自动化共享的行动结算内核**（无表现回放路径）。

## 统一契约测试 runner（`tools/run_contracts.py`，2026-11-16 起默认入口）

manifest 驱动（`tests/contract_manifest.json`：80 契约 + 2 探针），仅 Python 标准库；详见 `docs/test_automation.md` 与 `claude/testing-and-quality.md`。

```bash
python3 tools/run_contracts.py --test terrain_generation --no-warmup   # 单契约
python3 tools/run_contracts.py --group ecology --jobs 3               # 组/标签 + 并发
python3 tools/run_contracts.py --changed --dry-run                    # 只跑受影响（git 变更 → 影响闭包）
python3 tools/run_contracts.py --all --run-env-skip --junit            # 全量 + JUnit
```

## 批量战斗模拟 CLI（`tools/run_simulations.gd` + `tools/simulation_batch.gd`，2026-11-16 新增）

按 batch 夹具批量跑 BattleRunner 对局，输出逐次 JSON 指标与汇总（`--runs 1000` 容量模式实测 3.6s）；核心 `simulation_batch.gd` 为 RefCounted，被 CLI / autosim adapter / `tests/simulation_contract.gd` 三方共用。配套 `addons/godot_autosim/` 最小接入（`tools/autosim_battle_adapter.gd` + `autosim_first_action_bot.gd`）。

```bash
"$GODOT" --headless --path . --script res://tools/run_simulations.gd -- \
  --batch res://tests/fixtures/simulations/battle_determinism_fixed.json --runs 100 --out user://tmp/sim_out
```

## 世界 → 战棋适配契约（`scripts/core/world_to_chapter.gd`）

| 函数 | 输入 | 输出 | 说明 |
| --- | --- | --- | --- |
| `world_to_chapter(sampler, player_cell, radius, seed)` | TerrainSampler + 玩家格 + 半径 + 种子 | `chapter` Dictionary | 主入口：生成 21×21 战场 |
| `cell_context_to_terrain(ctx)` | CellContext | StringName | CellContext → 战棋地形 |
| `_find_standable_near(...)` | — | 格 | 单位只放 walkable 格 |

`chapter` Dictionary 结构：`{ id?, name?, width, height, map: StringName[][], playerUnits:[], enemyUnits:[], world_origin?, hosting?, victory?, reinforcements? }`（后两个可选键见下）。

`cell_context_to_terrain` 覆盖 11 种战棋地形中的 **7 种**（确定性映射，无 RNG）：water / mountain / snow / sand / rocky / grass / plain；forest / village / fort / wall 无世界数据源不映射。

## JSON 战场加载契约（`scripts/core/battlefield_loader.gd`）★ loader 是唯一权威校验点

| 接口 | 说明 |
| --- | --- |
| `BattlefieldLoader.list_battlefields()` | 扫描 `res://data/battlefields/*.json` + `user://battlefields/*.json`（res 优先、同名跳过）；坏 JSON 条目带 error 返回（HUD 置灰显示） |
| `BattlefieldLoader.load_battlefield(path)` | JSON → chapter（与 world_to_chapter 同构）；校验：地形名合法 / 行宽一致 / 职业合法 / 坐标界内 / standable / 单位不重叠（**含跨增援波次**）/ 双阵营各≥1 |
| `DEFAULT_LEGEND` | 图例字符 → 地形名默认映射（编辑器 `BattlefieldDoc` 与之一致） |

**战场 JSON 顶层 schema**（`rows` 是**顶层字段，不嵌在 terrain 下**）：

```json
{
  "id": "arena_1v1", "name": "竞技场单挑", "description": "...",
  "rows": ["....", ".@@.", "...."],
  "legend": { "@": "water", "#": "mountain", "T": "forest", "F": "fort", "V": "village", "W": "wall", "g": "grass", "s": "sand", "S": "snow", "r": "rocky" },
  "playerUnits": [{ "class": "swordsman", "name": "剑士", "level": 1, "x": 2, "y": 1 }],
  "enemyUnits":  [ ... ],
  "victory": { "type": "defend_turns", "turns": 8 },
  "reinforcements": [
    { "turn": 3, "units": [{ "class": "archer", "name": "伏弩", "level": 2 }],
      "positions": [{ "x": 5, "y": 0 }] }
  ],
  "hosting": true
}
```

**可选玩法字段**（非法整卡拒绝加载，非法路径 `load_battlefield` 返回 null + push_error）：

- `victory: { type: "rout" | "defend_turns" | "seize", turns?: int }` — 胜利条件注入 `TurnManager.victory`，`check_victory(enemies, ctx)` 按类型判定（defend_turns 坚持到 N 回合 / seize 敌全灭或占点）。缺省 = rout（歼灭）。
- `reinforcements: [ { turn: int(≥1), units: [同 enemyUnits 条目但无 x/y], positions: [{x,y}]（与 units 等长） } ]` — 按回合波次增援：敌方回合开始由 `ReinforcementSpawner.spawn_due(chapter, grid, turn, turn_number)` 刷入（`search_radius=3` 曼哈顿环找空位，被占丢弃 + warning，已消费波次从 chapter 移除防恢复局重刷）；未到点单位经 `pending_units(chapter)` 并入敌存活集合，防提前判胜。

地形共 **11 种**：`plain, grass, sand, snow, rocky, forest, water, village, fort, wall, mountain`（`core/terrain.gd`）。

## 战场编辑器契约（`scripts/editor/`）

| 组件 | 主要接口 |
| --- | --- |
| `BattlefieldDoc`（battlefield_doc.gd） | 模型 `{ id, name, description, hosting, width, height, rows, units:[{class,name,level,x,y,faction}] }`；`generate(seed)`（确定性：水域/山脊/森林/村庄/要塞）、`resize()`、`to_json_dict()`、`load_path()`、`save_model()`（保存即回读校验）、`quick_validate()` |
| `EditorCanvas`（editor_canvas.gd） | 内嵌 `BattlefieldRenderer` 渲染；左键按下/拖动发 `cell` 信号（多高度拾取）；右键或 Space+左键平移、滚轮缩放；已放单位显示职业头像+阵营色环+等级徽标 |
| `map_editor.gd`（场景） | 工具：画笔/填充/橡皮/角色放置/**replace 整体替换**；**区域选择→复制/剪切/粘贴/拖动移动/方向键 nudge**；取色器（Alt 临时吸取 + 前景色/背景色）；种子输入+🎲随机+🌱生成；侧栏分组折叠 + at-icons 图标；快捷键提示弹窗（?） |
| `TilePreview`（tile_preview.gd) | 地形调色板缩略图（真实 ColumnBatch 等距方块柱渲染，4 列 GridContainer） |
| `AssetLibraryPanel`（asset_library_panel.gd） | 用户素材库面板：浏览/选用 `user://custom_assets/` 导入的方块图（消费 UserAssetService + VisualAdapter） |
| `EditorRegionClipboard`（region_clipboard.gd，2026-11-15） | 区域剪贴板内核（全静态）：`extract(...)` 五层 payload（rows / block_z / tile_overrides / props / units，坐标相对选区左上角）；`validate / bounds_error / write / clear_rect / paste / move / payload_size / describe`；`PAYLOAD_VERSION=1` |
| `EditorRegionPresetStore`（region_preset_store.gd） | 区域命名预设持久化：`list/save/load/rename/delete/has/count`；单文件 `user://editor_presets/presets.json`，tmp+bak 原子写 |
| `EditorBlockList` / `EditorBlockPickerDialog` | 方块画廊列表（GridContainer，`block_activated(kind,id)` 信号，compact/gallery 三态）与 4 列 640×480 选择弹窗（`block_chosen(kind,id)`） |
| `EditorShortcutHintsDialog` | 快捷键提示浮层（复用 hint_bar 键帽渲染） |

**UI 组件库 / 设计 token 契约**（`ui/` + 根 `DESIGN.md`）：新增界面一律走 `ui/components/pixel_*` 22 控件 + `ComponentTheme`（token 唯一实现：SPACE 4/8/16/24、CORNER、FONT、MARGIN 常量）；**禁裸数字样式值 / 自建 StyleBox / 绝对定位 / 横向滚动**。`tests/ui_contract.gd` 会静态扫描业务脚本（含 map_editor.gd）里的 `Button.new()/CheckButton.new()/OptionButton.new()` 直建控件并置 FAIL。

## 战棋内部静态接口（被 battle.gd 调用）

| 脚本 | 形态 | 主要对外接口 |
| --- | --- | --- |
| `core/professions.gd` | `class_name ProfessionData` | `load_data()` / `apply_profession()` / `has_profession()` |
| `core/skills.gd` / `items.gd` | 静态 | `load_data()` / 查表结算 |
| `core/weapons.gd` | `class_name WeaponData` | 武器三角 / 经验公式 |
| `core/terrain.gd` | `class_name TerrainData` | 地形 def/avoid/move_cost/walkable 查表（11 地形） |
| `core/unit.gd` | 静态 | UnitData 构造 + 默认成长率 |
| `systems/combat_system.gd` 等五个 | 全静态 | 战斗/技能/物品/buff 结算 |
| `systems/grid_system.gd` | 实例 | `GridSystem.new(w,h,map)`；移动范围/可达性 |
| `systems/turn_manager.gd` | 实例 | 回合调度；`var victory: Dictionary = {type:rout}` 可被 chapter 注入，`check_victory(enemies, ctx)` 注入式判定 |
| `systems/trade_system.gd` | 全静态 | `can_trade(from,to)` / `adjacent_trade_targets(unit,grid)` / `execute_trade(from,to,item_entry)` — 相邻友军物品传递 |
| `core/reinforcement_spawner.gd` | 全静态 | `spawn_due(chapter,grid,turn,turn_number)->Array` / `pending_units(chapter)->Array`（见上文增援字段） |

## 信号（signal）

### 世界侧

| 发出方 | 信号 | 监听方 | 用途 |
| --- | --- | --- | --- |
| `world_map_overlay.gd` | `open_state_changed(is_open: bool)` | main.gd | 大地图开合 |
| `game_hud.gd`（BattlefieldPanel） | `battlefield_picked(path)` | `main.gd._on_battlefield_picked` | O 列表点选战场 |
| `weather_system.gd` | water impact 相关 | `main.gd._on_weather_water_impact` | 雨滴击水反馈 |
| `user_asset_service.gd` | `manifest_loaded(result)` / `asset_ready(id)` / `asset_failed(id, error)` / `source_changed(url)` | 编辑器素材面板等 | 素材导入进度 |

### 战斗侧（2026-11 演出系统新增一大批）

| 发出方 | 信号 | 用途 |
| --- | --- | --- |
| `battle.gd` | `battle_finished(result: StringName)` | 战斗结束（B1 由 main.gd._exit_battle 恢复；B2 切回场景） |
| `battle_ui.gd` | `nameplate_shown / boss_banner_shown / loot_shown / cheer_requested / collapse_requested / presentation_sound_requested(cue)` | 演出步骤请求（名字牌/横幅/战利品/欢呼/倒地/音效由宿主接线到 Sfx） |
| `battle_ui.gd` | `opening_finished(skipped)` / `result_finished(result, skipped)` / `presentation_finished(kind, skipped)` | 演出阶段完成（支持快进） |
| `battle_ui.gd` | `immersive_presentation_changed(enabled)` | 沉浸演出开关切换 |
| `action_anim.gd` | `phase_started(phase, event)` / `impact_presented(impact)` / `float_text_requested(uid, text, color, size)` / `flash_requested(color, dur)` / `finished(event, skipped)` | 行动动画各阶段（回合导演 turn_director 驱动） |
| `result_presentation.gd` | `nameplate_shown / boss_banner_shown / loot_shown / cheer_requested` | 结算演出同款钩子 |
| `immersive_camera.gd` | `state_changed` | 沉浸相机状态 |
| `editor_canvas.gd` | `cell`（左键/拖动） | 编辑器画笔/填充/橡皮/放置工具解释 |

## 给 AI / 调试进程的接口（非游戏内）

- **`addons/breakpoint_mcp`**：`127.0.0.1:9080`（编辑器）/ **9081**（运行时）loopback newline-delimited JSON，方法名 1:1 对应 `editor_*` / `scene_*` / `node_*` / `dbg_*` / `runtime_*` 工具。经 MCP **按会话激活**后调用（见 `AGENTS.md` 与 `rules/godot-tools-map.md`：295 个工具、49 个可激活；`editor_*` 等 246 个激活也拿不到）。
- **`addons/panku_console`**：游戏内 `~` REPL；项目命令集 `scripts/debug_console_commands.gd` 注册为 `dbg.*`（`help / list_battlefields / battlefield(id) / editor / enter_battle / battle_mode / player / time_scale`）。新命令 = 对象公共方法 + `_HELP_方法名` 常量；新对象用 `Panku.gd_exprenv.register_env(name, obj)` 注册。autoload 单例与场景根 `current` 自动可用。
