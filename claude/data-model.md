# 数据模型

本项目无数据库 / 无网络持久层。"数据模型"指**运行时领域对象**（多为 GDScript Dictionary，全 StringName key）、**流式生成的世界状态**与 **3D 正交渲染结构**。

## 世界生成核心数据结构（`scripts/world/`）

### `CellContext`（`scripts/world/cell_context.gd`）

**数据快照**，描述一个格子的全部环境信息，是生态解析的输入。由 `main.gd._sample_cell_context` / `TerrainSampler` 产生：

- biome（int，对应 `_biome_id`）
- landform（int，`LANDFORM_ID_TO_TYPE` 映射 plains/hills/swamp/mountain/ocean...）
- elevation / `q`（量化高度层数，`LEVELS=16`）
- water_depth（`WATER_MAX=5` 及以下为水面；`WATER_SURFACE_LEVEL=6`）
- shoreline / beach（`_is_beach`）
- surface type（`_desert_surface_kind` 等）

### `CellState`（`scripts/world/cell_state.gd`）

**渲染状态**，承载 `CellContext` 解析后的渲染决策（flora / 水体块 / 材质选择），供 3D chunk / 批量绘制消费。有对应契约测试 `tests/cell_state_contract.gd`、`cell_state_integration_contract.gd`。

### 确定性 RNG（`scripts/world/deterministic_rng.gd`）

所有"同 seed + 同 cell → 同结果"的根基。`main.gd._hash_u32` / `_cell_rand(gc, salt)` / `_quantize(x,y)` / `_seed_point` 都服务于确定性契约。**改这些会破坏测试 SHA-256 快照**。

### 流式世界状态（main.gd 实例字段）

`main.gd` 持有这些非持久化状态：

- 已生成 cell 集合 / 3D chunk（`_spawn_cell` 产生，`_free_cell` 释放；`IsometricTerrain3D.CHUNK_SIZE=2`）
- 活跃动物 `WanderingAnimal`（AnimatedSprite3D）集合 + 群体状态缓存（`CommunityStateStore`）
- 玩家位置 `_player_cell`、相机 `_cam: IsometricCamera3D`、缩放 `_zoom_index`
- 战斗态：`_battle_active`, `_battle_system`, 战前相机/玩家可见性备份

> **注意：世界状态不持久化到磁盘**。重新生成（Ctrl+R / 重启）会重新流式生成；探索过的地图在内存中保留，但程序退出即丢失。

## 3D 正交渲染结构（`scripts/iso/`，2026-11-12 迁移）

| 类 | 关键常量 / 数据 | 说明 |
| --- | --- | --- |
| `IsoProjection3D`（iso_projection_3d.gd） | `TILE_PIXELS=32, TILE_HEIGHT=16, LEVEL_PIXELS=10` | 2:1 dimetric 像素标尺 → 3D 世界单位换算 |
| `IsometricCamera3D` | `zoom 0.5–4`；`SUPPORTED_ANGLES` | 正交 Camera3D；**旋转只动相机**，不重建地形 |
| `isometric_view.gd` | `SUPPORTED_ANGLES=[0,90,180,270]` | 离散视角：素材逐角度验收仅四视角，其余角度有拼缝 |
| `IsometricTerrain3D`（isometric_terrain_3d.gd） | `CHUNK_SIZE=2, MAX_WATER_RIPPLES=48` | chunk 化 3D 柱地形；水面涟漪池 |
| `SunlightSystem`（sunlight_system.gd） | DirectionalLight3D | 由 `_setup_day_night` 创建；参数读 `config/sunlight.json` |
| `main.gd._grid_to_world(cell) -> Vector3` | — | 网格坐标 → 3D 世界坐标（返回 Vector3） |

## 生态 / 群落数据（`scripts/ecology/`）

| 类 | 角色 | 备注 |
| --- | --- | --- |
| `EcologyRegistry` | 物种 / community 注册表 | 从配置编译 |
| `EcologyResolver` | habitat 匹配 + 冲突权重选择 | 应用所有匹配 community |
| `CommunityRuntime` | 群落运行时 | |
| `CommunitySpawner` | 群落实例化（patch / 孤独动物 / 家族 / 同种鱼群 / 混合狼群） | 数据驱动，不写新代码 |
| `CommunityStateStore` | 群落状态有界缓存 | 避免流式时重复 habitat 搜索 |
| `MemberComposer` | 群落成员组合（权重 / fixed members） | |
| `AmbientRegistry` | 环境生物注册表（鸟 / 萤火虫） | 可选 observer 更新 |

群落配置字段（来自 `config/ecology/README.md`）：
- `distribution.single_species` — 整组选一个加权填充物种
- `anchor_search_radius` — 窄栖息地（如河流）找最近合法格
- `metadata.legacy_placement_seed` — **仅旧内容兼容**，新内容禁止加

## 动物行为模型（`scripts/animals/animal_behavior_registry.gd`）

**可组合行为栈**（每物种一组 scorer，分数相加决定移动方向）：

| 行为 | 含义 |
| --- | --- |
| water preference | 倾向水域（只在岸边，不进水格） |
| avoid snow | 漫游时远离雪地 |
| prefer snow | 倾向雪地（逃离时可短暂越界） |
| group cohesion | 受群体中心影响（`ANIMAL_GROUP_COHESION_WEIGHT=6.0`） |
| player avoidance | 玩家进 6 格警戒半径（`ANIMAL_FLEE_RADIUS=6`）→ 朝远离方向、约 2 倍速逃跑（`ANIMAL_FLEE_SPEED=2.0`） |

## 战棋领域模型（`scripts/core/`）

全部用 **Dictionary + StringName key** 表达（仿 TS 源），由 `data/*.json` 懒加载。

### `UnitData`（`core/unit.gd`）
```
{ id, name, classId, faction, level, exp,
  stats: { hp, mp, str, mag, skl, spd, luk, def, res, mov },  # mp 即 MP 上限
  growths: { hp, mp, str, mag, skl, spd, luk, def, res },
  weapon: <Weapon dict>, items: [...], skills: [...] }
```
- `faction`：`Enums.FACTION_PLAYER` / `FACTION_ENEMY`（`core/enums.gd`，StringName）。
- `power` 统一表示主攻击属性，`apply_profession` 按武器类型写 `str`（物理）或 `mag`（魔法）。

### `Weapon`（`core/weapons.gd`）
`{ id, name, type, might, hit, crit, range:[min,max]|int, weight, uses }`
- 武器三角（`WEAPON_TRIANGLE`）+ 三角修正（`TRIANGLE_MODIFIER`）+ 经验公式。

### `SkillData` / `ItemData` / `ProfessionData` / `TerrainData`（`core/*.gd`）
- Skill：`type(damage/heal/aoe/buff/debuff), element, range, targetType, mpCost, cooldown, power, hitBonus, stat, buffValue, buffTurns`
- Item：`type(consumable/throwable/equip/buff), target, effect(heal_hp/heal_mp/damage/buff/cleanse/equip), power, range, uses, ...`
- Profession：`power, agility→spd, attack_range`（职业固有射程优先于武器）
- Terrain：`{ type, def_bonus, avoid_bonus, move_cost:{foot,armor,cavalry,flying}, walkable }`，`move_cost=99` 不可通行。**11 种地形**：`plain, grass, sand, snow, rocky, forest, water, village, fort, wall, mountain`。

### `chapter`（战斗输入，见 `public-interfaces.md`）
`{ id?, name?, width, height, map: StringName[][], playerUnits:[], enemyUnits:[], world_origin?, hosting? }`

两个来源产出同构 chapter：`world_to_chapter`（世界地形采样）与 `BattlefieldLoader.load_battlefield`（JSON 文件）。

### JSON 战场文档模型（`scripts/editor/battlefield_doc.gd`）

```
{ id, name, description, hosting: bool,
  width, height, rows: PackedStringArray,      # 字符画，legend 字符 → 地形
  units: [{ class, name, level, x, y, faction }] }
```
- `generate(seed)`：确定性生成（水域/山脊/森林/村庄/要塞布局）。
- `to_json_dict()` 输出与 `data/battlefields/*.json` 完全一致的 JSON；`save_model()` 保存即回读校验；`quick_validate()` 轻校验（完整校验在 BattlefieldLoader）。

### 战斗运行时状态（battle.gd）
- `GridSystem`（实例）：地形矩阵 + 移动范围 / 可达性。
- `TurnManager`（实例）：回合调度。
- 状态机 `Mode`：`IDLE | UNIT_SELECTED | MOVING | MENU | ENEMY_TURN | ANIMATING`。
- `_unit_sprites`、`current_move_range`、`current_attack_tiles`、`cursor_pos`、`_pending_move_undo`。
- `TurnDirector`：敌方 AI 回合 + 玩家托管编排 + 偏好数据（`key=unitId → {priorityTargetId, strategy}`）。

### 战场地形高度规则（`battlefield_renderer.gd`）

渲染为等距方块柱：`water → h1`；`plain/grass/sand/snow/rocky/forest/village → h2`；`fort → h3`；`wall → h4`；`mountain → h5`。贴图取自 `config/ecology/world/base.json` 的 materials。

## 用户偏好持久化（`Settings` autoload）

`user://settings.cfg`（ConfigFile）：
```
[battle]
inline_mode=true   ; true=就地(B1) / false=独立场景(B2)
```
**这是唯一持久化到磁盘的应用状态**。

## 缓存 / 流式状态边界

- `CommunityStateStore`：群落状态**有界缓存**，完成的与空的领地计划共享，避免流式单格更新重复搜索。
- `terrain_material_registry`（`scripts/world/terrain_material_registry.gd`）：地形材质注册（避免重复创建）。注意 `set_texture_processor(raw_texture, texture_path)` **必须两参都传**，漏第二参整批贴图全 null 崩溃（HANDOFF 坑）。
- `noise_registry`（`scripts/world/noise_registry.gd`）：命名噪声场缓存。
- 鸟渲染器（`scripts/ecology/ambient_renderers/bird_renderer.gd`）：viewport 生命周期内的飞越，自带清理。
- `BattlefieldLoader` 扫描缓存：`res://data/battlefields/` + `user://battlefields/`，res 优先、同名跳过。
