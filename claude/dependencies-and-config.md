# 依赖与配置

## 运行时依赖

- **Godot 4.6+**（本项目用 **4.7**，`project.godot` 声明 `config/features=PackedStringArray("4.7", "GL Compatibility")`）。
- **无第三方 GDScript / npm / cargo 依赖**：全仓库不依赖任何外部 GDScript 库；战棋代码是项目内纯逻辑（迁移自 phaserjs 的 TS 逻辑层，但已用 GDScript 重写，**不含 TS/JS 源码**）。
- **唯一 vendored 第三方组件**：`addons/breakpoint_mcp`（James Livingston, v1.9.1，调试用），见其独立 `CLAUDE.md`。
- **物理**：3D 引擎选用 Jolt Physics（`project.godot [physics]`）。项目实际是 2D，此项对玩法基本无影响。

## 配置文件总览

### 世界 / 生态配置（`config/`）

运行时入口是 **`config/ecosystems.json`**（旧版"首次匹配 ecology"，`main.gd._load_ecosystem_config` 读取）。**新版模块化配置**通过 `config/ecology/manifest.json` 聚合，二者并存、由 `_compile_ecosystem_config` 编译。

| 文件 | 顶层结构 | 作用 |
| --- | --- | --- |
| `config/ecosystems.json` | `version, default_ecosystem="temperate", generation{...}, species{plants,animals,ambient}, ecosystems[10], pool_selection` | **运行时主入口**：生成参数 + 物种 + 10 个生态（按序首匹配） |
| `config/ecology/manifest.json` | `version, modules[{kind,path}]` | 新版：声明 world/species/communities/biomes 各模块文件 |
| `config/ecology/world/base.json` | `world{default_biome_id, generation, pool_selection}` | 新版：全局地形生成参数 |
| `config/ecology/biomes/catalog.json` | `biomes[10]` | 新版：10 个 biome 模块（desert/snow/temperate + water/shore 各变体） |
| `config/ecology/species/{plants,animals,ambient}.json` | `species{...}` | 新版：物种定义（ID/资源/动画/行为） |
| `config/ecology/communities/{core,legacy_bundles}.json` | `communities[10]` | 新版：可复用群落定义。**`legacy_bundles` 仅供旧布局兼容，禁用于新内容** |
| `config/README.md` + `config/ecology/README.md` | — | 配置约定文档（必读） |

**10 个 ecosystem / biome ID**（两套一致）：`desert_water, desert_transition_water, water, desert_shore, desert_transition_shore, shore, snow, desert, desert_transition, temperate`（默认）。

`ecosystems.json.generation` 子键：`biome_index_order, materials, height, noise, flora, regions, climate, biome_profiles`。

### 表现层配置（`config/`）

| 文件 | 作用 |
| --- | --- |
| `config/weather.json` | 天气：`auto_interval_seconds, transition_seconds, rain_start_chance, rain_continue_chance, snow_exit_hysteresis_levels, *_impact_attempts_per_second` |
| `config/day_night.json` | 昼夜：`cycle_seconds, start_progress, sunrise/sunset 边界, night_overlay_opacity` |
| `config/audio.json` | 音乐 / 雨声环境音 / 动物叫声配置（`music{...}, weather_ambience{...}, animal_sounds{...}`） |
| `config/depth_of_field.json` | 景深：`enabled_by_default, focus_half_height, focus_feather, far/near_strength, vignette_strength` |

### 战棋数据（`data/`）

| 文件 | 内容 |
| --- | --- |
| `data/professions.json` | 8 职业：`swordsman, knight, archer, mage, berserker, assassin, lancer, priest`（`defaultProfession`） |
| `data/skills.json` | 8 技能：`fireball, smite, heal, blizzard, powerSurge, guard, weaken, haste`（`defaultSkill`） |
| `data/items.json` | 8 物品：`hpPotion, mpPotion, antidote, shuriken, bomb, armorRing, powerRing, mightPotion`（`defaultItem`） |

战棋脚本（`core/professions.gd` 等）从 `res://data/*.json` **懒加载**，全 StringName key。

## 环境变量

| 变量 | 作用 | 何时设 |
| --- | --- | --- |
| `BREAKPOINT_BRIDGE_PORT` | 覆盖 breakpoint_mcp 监听端口（默认 9080） | **启动 Godot 之前** |

（除此之外无运行时环境变量。`seed` 通过 `@export` 或命令行 `--seed=` 传入，非环境变量。）

## 命令行参数（`core/cmd_args.gd` 解析）

`CmdArgs.get_bool/get_string/get_int(key, default)`，支持 `--key` / `--key=value` / `--no-key` 形式。示例：`--seed=42`、`--no-hosting`。

## 资源目录约定（`config/README.md`）

```
meowa_tiles/
  terrain/        地形 tile
  animals/<species_id>/   每种动物独立目录（actions.file 相对该目录）
  plants/         活体灌木/草本/花卉/仙人掌/水生
  trees/          乔木
  decorations/    树桩/石块等非生长物件
  heroes/         NPC 素材（当前是 animals 副本，待映射职业 —— 已知待办）
assets/
  bg/ markers/ ui/(buttons,cursors,frames,portraits) units/   战棋素材
```

- 所有 tile 文件与目录统一英文小写 `snake_case`。
- 每个静态生态对象必须声明 `layer`：`tree` / `ground_cover` / `decoration`。
- 动物配置：`actions`（idle/move 动画）、`movement`（duration/move_steps/step_pause/sort_switch_progress）、`behavior`（wander/near_water/avoid_snow/prefer_snow）、`foot_offset_y`（补偿透明留白）。

## 框架版本差异提醒

- **Godot 4 vs 3**：项目用 4.x API（`@export`、`StringName`、`FastNoiseLite`、`PackedStringArray`、`Color`、`Vector2i` 等），与 Godot 3 不兼容。
- **Node2D 无 `offset`**：Godot 4 的 `Node2D` 不像 `Sprite2D`/`AnimatedSprite2D` 有 `offset` 属性。战棋单位因此用 `position + z_index=10`，未接入 y-sort 双轨（见 HANDOFF 技术决策 #5）。
- **breakpoint_mcp 要求 Godot 4.2+**（4.4+ 推荐），本项目 4.7 满足。
