# 数据模型

本项目无数据库 / 无网络持久层。"数据模型"指**运行时领域对象**（多为 GDScript Dictionary，全 StringName key）与**流式生成的世界状态**。

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

**渲染状态**，承载 `CellContext` 解析后的渲染决策（flora / 水体块 / 材质选择），供批量绘制消费。有对应契约测试 `tests/cell_state_contract.gd`、`cell_state_integration_contract.gd`。

### 确定性 RNG（`scripts/world/deterministic_rng.gd`）

所有"同 seed + 同 cell → 同结果"的根基。`main.gd._hash_u32` / `_cell_rand(gc, salt)` / `_quantize(x,y)` / `_seed_point` 都服务于确定性契约。**改这些会破坏测试 SHA-256 快照**。

### 流式世界状态（main.gd 实例字段）

`main.gd` 持有这些非持久化状态：

- 已生成 cell 集合 / Column 批次（`_spawn_cell` 产生，`_free_cell` 释放）
- 活跃动物 `WanderingAnimal` 集合 + 群体状态缓存（`CommunityStateStore`）
- 玩家位置 `_player_cell`、相机 `_cam`、缩放 `_zoom_index`
- 战斗态：`_battle_active`, `_battle_system`, 战前相机/玩家可见性备份

> **注意：世界状态不持久化到磁盘**。重新生成（R 键 / 重启）会重新流式生成；探索过的地图在内存中保留，但程序退出即丢失（README 的"explored map data"指会话内）。

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
- Terrain：`{ type, def_bonus, avoid_bonus, move_cost:{foot,armor,cavalry,flying}, walkable }`，`move_cost=99` 不可通行。

### `chapter`（战斗输入，见 `public-interfaces.md`）
`{ width, height, map: StringName[][], playerUnits:[], enemyUnits:[], world_origin, blockTitles }`

### 战斗运行时状态（battle.gd）
- `GridSystem`（实例）：地形矩阵 + 移动范围 / 可达性。
- `TurnManager`（实例）：回合调度。
- 状态机 `Mode`：`IDLE | UNIT_SELECTED | MOVING | MENU | ENEMY_TURN | ANIMATING`。
- `_unit_sprites: { unitId -> UnitSprite3D }`、`current_move_range`、`current_attack_tiles`、`cursor_pos`、`_pending_move_undo`。
- `TurnDirector`：敌方 AI 回合 + 玩家托管编排 + 偏好数据（`key=unitId → {priorityTargetId, strategy}`）。

## 用户偏好持久化（`Settings` autoload）

`user://settings.cfg`（ConfigFile）：
```
[battle]
inline_mode=true   ; true=就地(B1) / false=独立场景(B2)
```
**这是唯一持久化到磁盘的应用状态**。

## 缓存 / 流式状态边界

- `CommunityStateStore`：群落状态**有界缓存**，完成的与空的领地计划共享，避免流式单格更新重复搜索。
- `terrain_material_registry`（`scripts/world/terrain_material_registry.gd`）：地形材质注册（避免重复创建）。
- `noise_registry`（`scripts/world/noise_registry.gd`）：命名噪声场缓存。
- 鸟渲染器（`scripts/ecology/ambient_renderers/bird_renderer.gd`）：viewport 生命周期内的飞越，自带清理。
