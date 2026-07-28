# 对外接口

> 本项目是**单机游戏**，不暴露 REST API / WebSocket / SDK / CLI 给外部进程。本文件列出"接口"的两种现实形态：**玩家输入映射** 与 **跨场景 / 跨模块的代码契约**。

## 玩家输入映射（`project.godot [input]` + `main.gd._unhandled_input`）

### 世界探索（main.gd）

| 操作 | 动作 | 实现位置 |
| --- | --- | --- |
| `WASD` / 方向键 | 沿等距网格移动 | `_input_dir` → `_try_move` |
| `Shift` | 加速（`fast_multiplier=3.0`） | `_try_move` |
| 鼠标滚轮 / `+` / `-` | 缩放（`ZOOM_LEVELS=[0.5,1,2,3,4]`） | `_zoom_step` |
| `M` | 开关大地图 | `_toggle_world_map` |
| `T` / `Shift+T` | 切换天气 / 恢复自动天气 | `_unhandled_input` → weather_system |
| `N` / `Shift+N` | 切换昼夜 / 恢复自动昼夜 | → day_night_system |
| `B` | 切换景深 | → depth_of_field_system |
| `F` | 重置相机 | `_setup_camera` 相关 |
| `R` | 重新生成世界（新种子） | `_regenerate` |
| `P` | 进入战斗（B1/B2 由设置决定） | `_enter_battle` |

### 战斗（battle.gd，`project.godot [input]` 定义的命名动作）

| 输入动作 | 默认键 | 用途 |
| --- | --- | --- |
| `confirm` | Z / Enter | 选格 / 确认菜单 |
| `cancel` | Esc | 取消移动 / 返回 |
| `end_turn` | E | 结束回合 |

battle.gd 另在 `_unhandled_input` 处理鼠标选格、键盘方向移动光标。

## 跨场景代码契约

### `SceneArgs`（autoload 单例）— 唯一的跨场景传参通道

Godot `change_scene_to_file` 不带参，故用全局单例暂存。`battle.gd._ready` 读取 `SceneArgs.battle_args`：

```gdscript
SceneArgs.battle_args = {
    "chapter": <Dictionary>,     # 必填，WorldToChapter 产物
    "return_to": "res://main.tscn",  # 可选，B2 结束后回到哪
    "world": <main.gd 实例>       # 仅 B1 注入；存在则 _b1_mode=true
}
```

### `Settings`（autoload 单例）— 用户偏好

| 成员 | 类型 | 默认 | 含义 |
| --- | --- | --- | --- |
| `battle_inline_mode` | bool | true | true=就地战斗(B1) / false=独立场景(B2) |
| `set_battle_inline_mode(v)` | 方法 | — | 设置并持久化到 `user://settings.cfg` |
| `save()` | 方法 | — | 写 ConfigFile |

## 世界 → 战棋适配契约（`scripts/core/world_to_chapter.gd`）

纯静态函数，是两个子系统的边界：

| 函数 | 输入 | 输出 | 说明 |
| --- | --- | --- | --- |
| `world_to_chapter(sampler, player_cell, radius, seed)` | TerrainSampler + 玩家格 + 半径 + 种子 | `chapter` Dictionary | 主入口：生成 21×21 战场 |
| `cell_context_to_terrain(ctx)` | CellContext | StringName | CellContext → 战棋地形（当前只映射 `water`/`mountain`/`plain`） |
| `_find_nearest_land(...)` | — | 格 | 玩家在水面时找最近陆地作战场中心 |
| `_is_standable(...)` / `_find_standable_near(...)` | — | 格 | 单位只放 walkable 格 |

`chapter` Dictionary 结构（战棋侧消费）：
```
{
  width, height,          # 战场尺寸（半径 10 → 21×21）
  map: StringName[height][width],  # 地形矩阵
  playerUnits: [...], enemyUnits: [...],  # Unit dict 数组
  world_origin: Vector2i,  # B1 用：战场(0,0) 对应的世界 cell
  blockTitles: [...]       # 地形标题（可选，B1 走 fallback 色块）
}
```

## 战棋内部对外暴露的静态接口（被 battle.gd 调用）

| 脚本 | 形态 | 主要对外接口 |
| --- | --- | --- |
| `core/professions.gd` | `class_name ProfessionData` | `load_data()` / `apply_profession()` |
| `core/skills.gd` | 静态 | `load_data()` / 技能结算查表 |
| `core/items.gd` | 静态 | `load_data()` |
| `core/weapons.gd` | `class_name WeaponData` | 武器三角 / 经验公式 |
| `core/terrain.gd` | `class_name TerrainData` | 地形 def/avoid/move_cost/walkable 查表 |
| `core/unit.gd` | 静态 | UnitData 构造 + 默认成长率 |
| `systems/combat_system.gd` | 全静态 | 战斗结算（伤害/命中/暴击/死亡/经验） |
| `systems/skill_system.gd` | 全静态 | 技能结算 |
| `systems/item_system.gd` | 全静态 | 物品结算 |
| `systems/buff_system.gd` | 全静态零依赖 | buff/属性修正 |
| `systems/grid_system.gd` | 实例 | `GridSystem.new(w,h,map)`；移动范围/可达性 |
| `systems/turn_manager.gd` | 实例 | 回合调度 |
| `systems/enemy_ai.gd` / `player_ai.gd` | 静态/实例 | AI 决策 |

> 上述接口的精确签名需查各文件源码（本索引未逐行展开）。

## 信号（signal）

| 发出方 | 信号 | 监听方 | 用途 |
| --- | --- | --- | --- |
| `battle.gd` | `battle_finished(result: StringName)` | `main.gd._exit_battle`（B1） | 通知战斗结束，触发恢复 |
| `weather_system.gd` | water impact 相关 | `main.gd._on_weather_water_impact` | 雨滴击水反馈 |
| 各表现层系统 | （内部） | main.gd 装配时 connect | 系统 ↔ 主场景联动 |

## 给 AI / 调试进程的接口（非游戏内）

`addons/breakpoint_mcp` 在 `127.0.0.1:9080` 暴露 **loopback newline-delimited JSON** 协议，方法名 1:1 对应 `editor_*` / `scene_*` / `node_*` 工具。详见该插件独立 `CLAUDE.md` 与 `addons/breakpoint_mcp/README.md`。**这是唯一的进程间对外接口**，仅供本地调试 host 使用，绑定 loopback。
