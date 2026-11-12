# 依赖与配置

## 运行时依赖

- **Godot 4.7+**（本项目用 **4.7.2 stable**，`project.godot` 声明 `config/features=PackedStringArray("4.7", "GL Compatibility")`）。
  - 本机可执行文件：`D:/Godot/Godot_v4.7.2-stable_win64.exe`（console 版 `..._console.exe`）。**console 版 stdout 是全缓冲的**：管道场景下无输出 ≠ 没输出，脚本化验证时用 `timeout` 包裹读取。
  - 项目目录 `E:/pixel_world`（已从 `G:/` 迁移）。
- **无第三方 GDScript / npm / cargo 依赖**：战棋代码是项目内纯 GDScript（逻辑层迁移自外部 phaserjs 项目的 TS，本仓库**不含 TS/JS 源码**）。
- **vendored 第三方组件 3 个**（`addons/`）：
  | 组件 | 版本 | 用途 | 插件启用 |
  | --- | --- | --- | --- |
  | `breakpoint_mcp` | **v1.23.0** | 编辑器/运行时 MCP 调试桥（loopback 9080/9081） | ✅ |
  | `panku_console` | **v1.7.9** | 游戏内 `~` 表达式 REPL 控制台 | ✅ |
  | `at-icons` | **v1.6.0** | 700+ SVG 图标库（MIT，release zip 安装；编辑器 UI 只用 `control/` 色系） | ❌（纯资源，无需启用） |
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

### 战棋数据（`data/`）

| 文件 | 内容 |
| --- | --- |
| `data/professions.json` | 8 职业：`swordsman, knight, archer, mage, berserker, assassin, lancer, priest`（`defaultProfession`） |
| `data/skills.json` | 8 技能：`fireball, smite, heal, blizzard, powerSurge, guard, weaken, haste`（`defaultSkill`） |
| `data/items.json` | 8 物品：`hpPotion, mpPotion, antidote, shuriken, bomb, armorRing, powerRing, mightPotion`（`defaultItem`） |
| `data/battlefields/*.json` | **（2026-11-11 新增）JSON 战场 ×4**：`arena_1v1, plains_skirmish, river_crossing, mountain_pass`。schema 见 `public-interfaces.md`。用户自定义战场放 `user://battlefields/` |

> ⚠️ `story/` 目录是**目标态设计 bible**（13 职业 / 27 技能 / 25 道具 / 15 章），当前 `data/` 仍是 8/8/8。以 `data/` 为运行时事实，`story/` 为规划。

## 环境变量

| 变量 | 作用 | 何时设 |
| --- | --- | --- |
| `BREAKPOINT_BRIDGE_PORT` | 覆盖 breakpoint_mcp 监听端口（默认 9080） | **启动 Godot 之前** |

（除此之外无运行时环境变量。`seed` 通过 `@export` 或命令行 `--seed=` 传入，非环境变量。）

## 命令行参数（`core/cmd_args.gd` 解析）

`CmdArgs.get_bool/get_string/get_int(key, default)`，支持 `--key` / `--key=value` / `--no-key` 形式。示例：`--seed=42`、`--no-hosting`。`main.gd` 另有 `_shot_and_quit`（截图即退出，用于 README 截图）。

## 资源目录约定（`config/README.md`）

```
meowa_tiles/            世界像素素材（126 png）
  terrain/              地形 tile
  animals/<species_id>/ 每种动物独立目录（actions.file 相对该目录；13 种动物）
  plants/               活体灌木/草本/花卉/仙人掌/水生
  trees/                乔木
  decorations/          树桩/石块等非生长物件
  heroes/               角色素材（仍待与职业映射 —— 已知待办）
addons/at-icons/node*/  图标库按色系分目录（项目只用 control/）
assets/                 战棋素材：bg / markers / ui(buttons,cursors,frames,portraits) / units
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
