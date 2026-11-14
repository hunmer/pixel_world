# 对外接口

> 本项目是**单机游戏**，不暴露 REST API / WebSocket / SDK / CLI 给外部进程。本文件列出"接口"的现实形态：**玩家输入映射**、**跨场景 / 跨模块的代码契约**、**JSON 战场文件格式**、**调试通道**。

## 玩家输入映射（`project.godot [input]` + `main.gd._unhandled_input` @ 3503）

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

battle.gd 另处理鼠标选格、键盘移动光标。B1 相机由 main.gd 处理：中键或 `Space`+左键拖拽平移、边缘滚屏、滚轮缩放（编辑器画布还支持右键拖拽平移）。

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

## 世界 → 战棋适配契约（`scripts/core/world_to_chapter.gd`）

| 函数 | 输入 | 输出 | 说明 |
| --- | --- | --- | --- |
| `world_to_chapter(sampler, player_cell, radius, seed)` | TerrainSampler + 玩家格 + 半径 + 种子 | `chapter` Dictionary | 主入口：生成 21×21 战场 |
| `cell_context_to_terrain(ctx)` | CellContext | StringName | CellContext → 战棋地形 |
| `_find_standable_near(...)` | — | 格 | 单位只放 walkable 格 |

`chapter` Dictionary 结构：`{ id?, name?, width, height, map: StringName[][], playerUnits:[], enemyUnits:[], world_origin?, hosting? }`。

## JSON 战场加载契约（`scripts/core/battlefield_loader.gd`）★ loader 是唯一权威校验点

| 接口 | 说明 |
| --- | --- |
| `BattlefieldLoader.list_battlefields()` | 扫描 `res://data/battlefields/*.json` + `user://battlefields/*.json`（res 优先、同名跳过）；坏 JSON 条目带 error 返回（HUD 置灰显示） |
| `BattlefieldLoader.load_battlefield(path)` | JSON → chapter（与 world_to_chapter 同构）；校验：地形名合法 / 行宽一致 / 职业合法 / 坐标界内 / standable / 单位不重叠 / 双阵营各≥1 |
| `DEFAULT_LEGEND` | 图例字符 → 地形名默认映射（编辑器 `BattlefieldDoc` 与之一致） |

**战场 JSON 顶层 schema**（`rows` 是**顶层字段，不嵌在 terrain 下**）：

```json
{
  "id": "arena_1v1", "name": "竞技场单挑", "description": "...",
  "rows": ["....", ".@@.", "...."],
  "legend": { "@": "water", "#": "mountain", "T": "forest", "F": "fort", "V": "village", "W": "wall", "g": "grass", "s": "sand", "S": "snow", "r": "rocky" },
  "playerUnits": [{ "class": "swordsman", "name": "剑士", "level": 1, "x": 2, "y": 1 }],
  "enemyUnits":  [ ... ],
  "hosting": true
}
```

地形共 **11 种**：`plain, grass, sand, snow, rocky, forest, water, village, fort, wall, mountain`（`core/terrain.gd`）。

## 战场编辑器契约（`scripts/editor/`）

| 组件 | 主要接口 |
| --- | --- |
| `BattlefieldDoc`（battlefield_doc.gd） | 模型 `{ id, name, description, hosting, width, height, rows, units:[{class,name,level,x,y,faction}] }`；`generate(seed)`（确定性：水域/山脊/森林/村庄/要塞）、`resize()`、`to_json_dict()`、`load_path()`、`save_model()`（保存即回读校验）、`quick_validate()` |
| `EditorCanvas`（editor_canvas.gd） | 内嵌 `BattlefieldRenderer` 渲染；左键按下/拖动发 `cell` 信号（多高度拾取）；右键或 Space+左键平移、滚轮缩放；已放单位显示职业头像+阵营色环+等级徽标 |
| `map_editor.gd`（场景） | 四工具：画笔/填充/橡皮/角色放置；种子输入+🎲随机+🌱生成；侧栏分组折叠 + at-icons 图标 |
| `TilePreview`（tile_preview.gd) | 地形调色板缩略图（真实 ColumnBatch 等距方块柱渲染，4 列 GridContainer） |

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
| `systems/turn_manager.gd` | 实例 | 回合调度 |

## 信号（signal）

| 发出方 | 信号 | 监听方 | 用途 |
| --- | --- | --- | --- |
| `battle.gd` | `battle_finished(result: StringName)` | `main.gd._exit_battle`（B1） | 战斗结束，触发恢复 |
| `world_map_overlay.gd` | `open_state_changed(is_open: bool)` | main.gd | 大地图开合 |
| `game_hud.gd`（BattlefieldPanel） | `battlefield_picked(path)` | `main.gd._on_battlefield_picked` | O 列表点选战场 |
| `weather_system.gd` | water impact 相关 | `main.gd._on_weather_water_impact` | 雨滴击水反馈 |
| `editor_canvas.gd` | `cell`（左键/拖动） | `map_editor.gd` | 画笔/填充/橡皮/放置工具解释 |

## 给 AI / 调试进程的接口（非游戏内）

- **`addons/breakpoint_mcp`**：`127.0.0.1:9080`（编辑器）/ **9081**（运行时）loopback newline-delimited JSON，方法名 1:1 对应 `editor_*` / `scene_*` / `node_*` / `dbg_*` / `runtime_*` 工具。经 MCP **按会话激活**后调用（见 `AGENTS.md` 与 `rules/godot-tools-map.md`：295 个工具、49 个可激活；`editor_*` 等 246 个激活也拿不到）。
- **`addons/panku_console`**：游戏内 `~` REPL；项目命令集 `scripts/debug_console_commands.gd` 注册为 `dbg.*`（`help / list_battlefields / battlefield(id) / editor / enter_battle / battle_mode / player / time_scale`）。新命令 = 对象公共方法 + `_HELP_方法名` 常量；新对象用 `Panku.gd_exprenv.register_env(name, obj)` 注册。autoload 单例与场景根 `current` 自动可用。
