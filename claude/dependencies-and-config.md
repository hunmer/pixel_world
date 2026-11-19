# 依赖与配置

> 更新：2026-11-19（新增 **data/equipment.json**（装备 11 条）+ `assets/ui/items|equipment/` 图标目录 + `assets/characters/free_character_pack/`；Godot 4.7.1）。上一轮：2026-11-18（campaign.json + shop.json + 建筑 recipe.json；battlefields 6→8；九键成长）。

## 运行时依赖

- **Godot 4.7+**（`project.godot` 声明 `config/features=PackedStringArray("4.7", "GL Compatibility")`；**本机（macOS）实测 4.7.1** `/Applications/Godot.app/Contents/MacOS/Godot`；Windows 历史路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`——项目跨机同步开发，两台机器版本 4.7.1/4.7.2 混用，契约基线以 macOS 4.7.1 为准）。
  - **本机（macOS）**：`/Applications/Godot.app/Contents/MacOS/Godot`。Windows 历史路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`（console 版 `..._console.exe`，stdout 全缓冲：管道下无输出 ≠ 没输出）。
  - 项目历史路径 G:/ → E:/ → 当前 `/Users/Zhuanz/Documents/pixel_world`。
- **Node.js（仅工具链，非游戏运行时）**：`tools/build_blocks_manifest.mjs`（用户素材清单生成）+ 其 node:test 契约；任何 ≥18 LTS 均可。
- **Python（素材工具 + 测试 runner）**：`tools/slice_class_sheets.py` / `slice_ui_sheet.py` / `tools/art` / `tools/audio` 生成脚本；**`tools/run_contracts.py` 统一契约 runner（仅标准库，2026-11-16 起）**，自身单测 `python3 -m unittest tools/test_run_contracts.py`（27 test）。
- **gdtest CLI（可选后端，外部可执行文件不在仓库内）**：`tests/gdtest/` 试点需要与 addons/gdtest 版本匹配的 gdtest Rust CLI（Godot 4.5+，实测 4.6/4.7）；无 CLI 时走契约口径不受影响。
- **无第三方 GDScript / npm / cargo 游戏依赖**：战棋代码是项目内纯 GDScript（逻辑层迁移自外部 phaserjs 项目的 TS，本仓库**不含 TS/JS 源码**）。
- **vendored 第三方组件 6 个**（`addons/`）：
  | 组件 | 版本 | 用途 | 插件启用 |
  | --- | --- | --- | --- |
  | `breakpoint_mcp` | **v1.23.0** | 编辑器/运行时 MCP 调试桥（loopback 9080/9081） | ✅ |
  | `panku_console` | **v1.7.9** | 游戏内 `~` 表达式 REPL 控制台 | ✅ |
  | `at-icons` | **v1.6.0** | 700+ SVG 图标库（MIT；编辑器 UI 只用 `control/` 色系） | ❌（纯资源） |
  | `pixelfx` | **v0.3.0** | 244 个代码绘制像素特效（24 类；`PixelFx2D`/`PixelFxAct2D`；战斗演出消费） | ❌（脚本库，preload 即用） |
  | `gdtest` | 运行时侧（2026-11-16 新增） | gdtest Rust CLI 的 worker/断言 helper/gdUnit4 迁移兼容；试点 `tests/gdtest/` | ❌（被 CLI harness 调用） |
  | `godot_autosim` | 4.6+（2026-11-16 新增） | 通用对局模拟/平衡框架（adapter+bot+runner+report）；接入 `tools/autosim_*.gd` | ❌（脚本库，preload 即用） |
- **物理**：`[physics] 3d/physics_engine = "Jolt Physics"`。3D 正交迁移后为真实使用。

## 配置文件总览

### 世界 / 生态配置（`config/`）

运行时入口是 **`config/ecosystems.json`**（旧版"首次匹配 ecology"，`main.gd._load_ecosystem_config` 读取）。**新版模块化配置**通过 `config/ecology/manifest.json` 聚合，二者并存、由 `_compile_ecosystem_config` 编译。

| 文件 | 顶层结构 | 作用 |
| --- | --- | --- |
| `config/ecosystems.json` | `version, default_ecosystem="temperate", generation{...}, species{plants,animals,ambient}, ecosystems[10], pool_selection` | **运行时主入口**：生成参数 + 物种 + 10 个生态（按序首匹配） |
| `config/ecology/manifest.json` | `version, modules[{kind,path}]` | 新版：声明 world/species/communities/biomes 各模块文件 |
| `config/ecology/world/base.json` | `world{default_biome_id, generation, pool_selection, materials}` | 新版：全局地形生成参数 + **战棋地形贴图 materials**（battlefield_renderer 消费） |
| `config/ecology/biomes/catalog.json` | `biomes[10]` | 新版：10 个 biome 模块（desert/snow/temperate + water/shore 各变体） |
| `config/ecology/species/{plants,animals,ambient}.json` | `species{...}` | 新版：物种定义（ID/资源/动画/行为） |
| `config/ecology/communities/{core,legacy_bundles}.json` | `communities[10]` | 新版：可复用群落定义。**`legacy_bundles` 仅供旧布局兼容，禁用于新内容** |
| `config/README.md` + `config/ecology/README.md` | — | 配置约定文档（必读） |

**10 个 ecosystem / biome ID**（两套一致）：`desert_water, desert_transition_water, water, desert_shore, desert_transition_shore, shore, snow, desert, desert_transition, temperate`（默认）。

### 表现层配置（`config/`）

| 文件 | 作用 |
| --- | --- |
| `config/weather.json` | 天气：`auto_interval_seconds, transition_seconds, rain_start_chance, rain_continue_chance, snow_exit_hysteresis_levels, *_impact_attempts_per_second` |
| `config/day_night.json` | 昼夜：`cycle_seconds, start_progress, sunrise/sunset 边界, night_overlay_opacity` |
| `config/sunlight.json` | **（2026-11-12 新增）3D 阳光**：`sun_azimuth_degrees 32.0, day_energy 0.75, day/night ambient, shadow_max_distance 72.0, shadow_bias 0.03, shadow_normal_bias 0.45` |
| `config/audio.json` | 音乐 / 雨声环境音 / 动物叫声配置 |
| `config/depth_of_field.json` | 景深：`enabled_by_default, focus_half_height, focus_feather, far/near_strength, vignette_strength` |
| `config/startup.cfg` | **（2026-11-14 新增）调试启动配置**（INI）：`[startup] auto_open_last_scene / last_scene / excluded_scenes`。编辑器调试读写 res://，导出后读写 user://；权威文档 `docs/startup_config.md` |

### 战棋与冒险数据（`data/`）

| 文件 | 内容 |
| --- | --- |
| `data/professions.json` | 8 职业：`swordsman, knight, archer, mage, berserker, assassin, lancer, priest`。**2026-11-18 九键成长**：`growths{hp,mp,str,mag,skl,spd,luk,def,res}`（旧 power→str/mag、agility→spd 由 `ProfessionData.growths_for` 归一，缺键逐键回退 `_GROWTH_FALLBACK`） |
| `data/skills.json` | 8 技能：`fireball, smite, heal, blizzard, powerSurge, guard, weaken, haste`；每技能 `iconId`（稳定 ID，`skill_icons.gd` 解析） |
| `data/items.json` | 8 物品：`hpPotion, mpPotion, shuriken, bomb, …`；每物品 `iconId`（稳定 ID '01'..'08'，`item_icons.gd` 解析，缺/空归一 DEFAULT_ICON_ID） |
| `data/equipment.json`★ | **（2026-11-19 新增）装备目录**：11 条（weapon 6 / shield 2 / staff 1 / relic 2），条目 `{id, name, slot(weapon/shield/staff/relic), stats(九键子集正加成), allowed_professions(空=通用), weapon_id(仅 weapon/staff), icon_id('01'..'11'), acquisition}`；消费方 `EquipmentDataScript`（core/equipment.gd） |
| `data/campaign.json`★ | **（2026-11-18 新增）冒险模式关卡表**：6 关卡（线性解锁），每关 `first_clear`/`repeat` 奖励（gold/items）+ `loot_table`（独立 RNG，种子=战场 id+出征令牌） |
| `data/shop.json`★ | **（2026-11-18 新增）营地商店目录**：`{id, price, limit_per_clear}`；限购上限 = `limit_per_clear × completed_levels.size()` |
| `data/battlefields/*.json` | JSON 战场 ×8：`arena_1v1, plains_skirmish, river_crossing, mountain_pass, last_stand, ambush_reinforce, building_demo, house_interior_demo`。schema 见 `public-interfaces.md`（victory/reinforcements/**buildings** 层）。用户自定义战场放 `user://battlefields/` |
| `assets/buildings/{medieval_watchtower,spacious_house}/recipe.json`★ | **内置建筑素材清单**（四方向 4:1 横排精灵图 + footprint + SHA-256 固化；契约见 `docs/building_assets.md`） |
| `data/dialogue/demo_intro.json` | 分支对话演示数据 |

> ⚠️ `story/` 目录是**目标态设计 bible**（13 职业 / 27 技能 / 25 道具 / 15 章），当前 `data/` 仍是 8/8/8。以 `data/` 为运行时事实，`story/` 为规划。

### 用户素材（网络清单，2026-11-14 新增）

- 默认源 `http://127.0.0.1:8076/blocks.json`（本机回环 http-server，指向历史机器 F:/blocks；**换机器需重建或改源**）。
- 清单协议 / 导入 / blob 存储 / 回滚：`docs/user_assets.md`（运维手册）；生成器 `tools/build_blocks_manifest.mjs`。
- 落盘：`user://user_assets/`（blob + catalog）。

## 环境变量

| 变量 | 作用 | 何时设 |
| --- | --- | --- |
| `BREAKPOINT_BRIDGE_PORT` | 覆盖 breakpoint_mcp 监听端口（默认 9080） | **启动 Godot 之前** |

（除此之外无运行时环境变量。`seed` 通过 `@export` 或命令行 `--seed=` 传入，非环境变量。）

## 命令行参数（`core/cmd_args.gd` 解析）

`CmdArgs.get_bool/get_string/get_int(key, default)`，支持 `--key` / `--key=value` / `--no-key` 形式。示例：`--seed=42`、`--no-hosting`。`main.gd` 另有 `_shot_and_quit`（截图即退出，用于 README 截图）。

## 资源目录约定（`config/README.md`）

```
meowa_tiles/            世界像素素材（terrain 10 / animals 24 / plants 39 / trees 25 / decorations 4 /
                       generated/ 程序生成 icon 增量 / heroes 24 + professions_static_manifest.json
                       （职业切片产物清单，仅 tools/slice_profession_sheets.py 消费）；heroes 仍待职业映射）
addons/at-icons/node*/  图标库按色系分目录（项目只用 control/）
assets/                 战棋素材：bg / markers / ui(buttons,cursors,frames,portraits + items 8★ +
                       equipment 11★ 图标) / units / buildings/{medieval_watchtower,spacious_house}/
                       （四方向建筑精灵图+recipe.json）/ characters/free_character_pack/★
                       （免费角色包：002..021 共 20 PNG + manifest.json；upstream_example/ 带
                       .gdignore 归档不参与导入；消费方 scripts/characters/free_character_sheet.gd）
```

- 所有 tile 文件与目录统一英文小写 `snake_case`。
- 每个静态生态对象必须声明 `layer`：`tree` / `ground_cover` / `decoration`。
- 动物配置：`actions`（idle/move 动画）、`movement`（duration/move_steps/step_pause/sort_switch_progress）、`behavior`（wander/near_water/avoid_snow/prefer_snow）、`foot_offset_y`（补偿透明留白）。

## 导出建议

- 无 `export_presets.cfg`；`.gitignore` 排除 `/builds/` `/exports/` `/android/`。
- 打包时建议排除 `addons/at-icons/` 未用色系目录（node*/animation/mesh 等，编辑器 UI 只用 `control/`），以及按需剔除 `docs/`、`story/`、`tests/`。

## 框架版本差异提醒

- **Godot 4 vs 3**：项目用 4.x API（`@export`、`StringName`、`FastNoiseLite`、`Camera3D`、`AnimatedSprite3D`、`DirectionalLight3D` 等），与 Godot 3 不兼容。
- **4.7 无 `DirAccess.remove_recursive`**（HANDOFF 坑）：删除目录需自写递归。
- **`Dictionary.merge` 默认不覆盖已有键**：合并配置时注意 `overwrite` 参数。
- **GDScript strict 显式类型**：严格模式下未标注类型的变量会报错，新代码保持完整类型标注。
- **breakpoint_mcp 要求 Godot 4.2+**（4.4+ 推荐），本项目 4.7 满足；运行时桥（9081）**单实例**——已有一个运行中的游戏再启动会绑定失败。
