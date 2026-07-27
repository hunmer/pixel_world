# HANDOFF — pixel_world × 战棋融合（B1 就地战斗已完成）

> 生成于 2026-07-28。给下一个 agent 接手用。
> 详细过程见 `phaserjs/progress.md` / `phaserjs/findings.md` / `phaserjs/task_plan.md`（phaserjs 是源项目，战棋代码从那里迁移来）。

## 项目定位

- **目标项目**：`/Users/Zhuanz/Documents/pixel_world`（Godot 4.7，GL Compatibility，Node2D 等距生态世界）
- **源项目**：`/Users/Zhuanz/Documents/phaserjs/godot`（Godot 4.7，Forward Plus，战棋 RPG + 地图编辑器）
- **任务**：把 phaserjs 的战棋战斗机制融入 pixel_world，在真实世界地形上就地战斗
- **当前状态**：B1（就地战斗）+ B2（切场景）双模式已实现，运行时可在「⚙ 设置」面板切换

## 已完成的工作（3 个阶段）

### 阶段 1：战棋代码迁移（B2 切场景版）
- 从 phaserjs 复制 17 个纯逻辑文件（core/ + systems/）+ data/*.json + 渲染层重写为 Node2D
- 渲染层 4 文件重写：`iso/iso_coords.gd` / `iso/iso_board.gd` / `iso/unit_sprite.gd` / `battle/range_overlay.gd`
- 粘合层 3 文件小改：`scenes/battle.gd` / `battle/battle_ui.gd` / `battle/turn_director.gd`
- 删除了合成地图代码（chapter_data / builtin_levels / level_select / level_storage / level_to_chapter / battle_test）

### 阶段 2：真实地形数据（B2 改进）
- 新建 `scripts/core/world_to_chapter.gd`：从 pixel_world 真实 cell 采样生成战棋 chapter
  - `cell_context_to_terrain(ctx)`：CellContext → 战棋 terrain（water/mountain/plain）
  - `_find_nearest_land()`：玩家在水面时找最近陆地作战场中心
  - `_is_standable()` / `_find_standable_near()`：单位只放 walkable 格
- main.gd 按 P → `WorldToChapter.world_to_chapter()` → 切 Battle.tscn

### 阶段 3：B1 就地战斗 + 切换开关（当前）
- **B1/B2 双模式并存**，由 `Settings.battle_inline_mode` 切换（默认 true=就地）
- 新建 `scripts/settings.gd`（autoload，ConfigFile 持久化到 `user://settings.cfg`）
- main.gd 7 处侵入点（全部可逆，照搬 `is_world_map_open` 模态范式）
- battle.gd / unit_sprite.gd / range_overlay.gd 加 B1 分支（B2 路径不动）
- game_hud.gd 加「⚙ 设置」按钮 + 面板

## 关键架构（B1 就地战斗数据流）

```
玩家按 P（main.gd._unhandled_input）
  ↓ Settings.battle_inline_mode == true
main.gd._enter_battle()
  ↓ WorldToChapter.world_to_chapter(_terrain_sampler, _player_cell, 10, _current_seed)
  ↓ _enter_battle_inline(chapter)
    ↓ 备份 _cam.position / _zoom_index / _player.visible
    ↓ _player.visible = false（隐藏红点，用 UnitSprite 替代）
    ↓ _zoom_index = 2; _apply_zoom()（固定 2.0x）
    ↓ _snap_camera_position(战场中心)
    ↓ SceneArgs.battle_args = { chapter, world: self, hosting: false }
    ↓ _battle_system = battle.gd.new(); add_child(_battle_system)
    ↓ _battle_active = true
战斗中
  ↓ main.gd._handle_battle_input 转发事件（整体短路世界探索输入）
  ↓ battle.gd._unhandled_input 处理鼠标选格/键盘
  ↓ UnitSprite 用 main.gd._grid_to_screen + cell_stand_level 定位
  ↓ RangeOverlay marker 挂 main.gd 下，用 _grid_to_screen 定位
  ↓ _process 里 _battle_active 时相机固定聚焦战场
战斗结束
  ↓ battle.gd 发 battle_finished 信号
  ↓ main.gd._exit_battle(result)
    ↓ _battle_system.queue_free()
    ↓ _battle_active = false
    ↓ 恢复 _cam / _player.visible
```

## 关键文件清单（pixel_world）

### 战棋代码（从 phaserjs 迁移 + 改造）
| 文件 | 说明 | B1 改动 |
|---|---|---|
| `scripts/core/world_to_chapter.gd` | 世界 cell → chapter 适配层 | 加 `world_origin` 字段 |
| `scripts/core/{enums,terrain,weapons,professions,skills,items,unit,cmd_args}.gd` | 纯逻辑（零改动） | 无 |
| `scripts/systems/{grid,combat,skill,item,buff,turn,enemy_ai,player_ai}_system.gd` | 战斗系统（零改动） | 无 |
| `scripts/iso/iso_coords.gd` | 2D 坐标变换 | 无（B1/B2 共用） |
| `scripts/iso/iso_board.gd` | B2 棋盘控制器 | 无（B1 不实例化） |
| `scripts/iso/unit_sprite.gd` | 单位视觉 | 加 `setup_world` + `_apply_render_proxy` + `z_index=10` |
| `scripts/iso/profession_visual.gd` | 职业立绘路径 | 无 |
| `scripts/battle/range_overlay.gd` | 范围/光标层 | 加 `setup_world` + 自带 marker 工厂 + `_ColorBlock` 内部类 |
| `scripts/battle/battle_ui.gd` | 战斗 HUD | 无（CanvasLayer 屏幕空间，B1/B2 共用） |
| `scripts/battle/turn_director.gd` | 回合编排器 | 无（通过 `unit_sprites` 字典访问，接口不变） |
| `scripts/scenes/battle.gd` | 战斗场景编排 | B1/B2 分支：`_setup_b1_render`/`_setup_b2_render`/`_spawn_unit_sprite`/`_check_battle_end` |
| `scripts/scenes/title.gd` | 标题界面 | 「进入世界」按钮跳 main.tscn |
| `scripts/scenes/scene_args.gd` | 跨场景传参 autoload | 无 |
| `scripts/settings.gd` | 🆕 用户偏好 autoload | ConfigFile 读写 `battle_inline_mode` |
| `scripts/tests/test_skills.gd` | 技能/物品自测 | 44/44 passed |
| `scripts/tests/debug_test.gd` | 战斗逻辑自测 | 35/35 passed（在 phaserjs 跑过） |

### pixel_world 原有代码（侵入式改动）
| 文件 | 改动 |
|---|---|
| `main.gd` | +7 侵入点（`_battle_active` 守卫）+5 新函数（`_enter_battle_inline`/`_exit_battle`/`_handle_battle_input`/`cell_stand_level`/`screen_to_cell`）+ KEY_P 热键 |
| `scripts/game_hud.gd` | 加「⚙ 设置」按钮 + 弹出面板（OptionButton 切就地/独立场景）|
| `project.godot` | `[autoload]` 加 `Settings`；`[input]` 加 confirm/cancel/end_turn |

### 资源
- `data/{professions,skills,items}.json`：战棋数据
- `assets/{units,markers,ui,bg}/`：战棋素材（立绘/路径箭头/肖像/背景）
- `meowa_tiles/heroes/`：NPC 素材（animals 的副本，待映射职业）
- `addons/breakpoint_mcp/`：调试插件（默认不启用）

## 验证状态

| 项 | 状态 | 说明 |
|---|---|---|
| Godot 编辑器扫描 | ✅ 零 error | 清 `.godot/editor` 缓存后重新编译 |
| SkillTest.tscn | ✅ 44/44 passed | 技能/物品/MP/冷却/buff 纯逻辑 |
| debug_test.gd | ✅ 35/35 passed（phaserjs 跑过） | 职业/地形/武器/战斗/AI/回合/经验 |
| B1 端到端 | ✅ 按 P 不切场景，真实地形上出现战棋单位 | 场景树确认根是 main.tscn + 4000 真实 Column |
| B2 回归 | ⚠️ 未深度验证 | 代码保留，`Settings.battle_inline_mode=false` 应切 Battle.tscn |

## 调试方法（AGENTS.md 约束）

- **MCP 工具**：`mcp__godot__*`（breakpoint_mcp 1.9.1，编辑器桥接 127.0.0.1:9080）
- **前置检查**：每次会话开头 `editor_ping()`，返回 `pong:true` 才能继续
- **启动调试**：`dbg_launch({scene: "res://main.tscn"})`（必须传 scene）
- **代码测试 > 截图**：用 `runtime_assert_*` / `runtime_get_log`，不擅自截图
- **编辑器脚本缓存坑**：`dbg_restart` 不重新编译脚本。改代码后必须清 `.godot/editor` + 重启编辑器：
  ```bash
  rm -rf /Users/Zhuanz/Documents/pixel_world/.godot/editor
  pkill -f "Godot.*pixel_world"
  /Applications/Godot.app/Contents/MacOS/Godot --editor --path /Users/Zhuanz/Documents/pixel_world &
  ```

## 待办（优先级排序）

### 高优先级
1. **B2 模式回归验证**：`Settings.battle_inline_mode=false` → 按 P 应切 Battle.tscn（代码保留，未验证）
2. **战斗结束恢复链路**：`_exit_battle` 信号已接，但未深度验证相机/玩家/输入完全恢复
3. **Node2D 无 offset 的 y_sort 问题**：当前单位用 `position=屏幕坐标 + z_index=10`，不走 main.gd 的 y_sort 双轨。高地地形可能遮挡单位。后续可改成 wandering_animal 的双轨设计（需把 UnitSprite 从 Node2D 改成 Sprite2D/Control 等有 offset 的类）

### 中优先级
4. **forest/fort/village/wall 地形映射**：当前 `cell_context_to_terrain` 只映射 water/mountain/plain（世界层没有树林/城墙数据源）
5. **heroes 职业映射**：`meowa_tiles/heroes/` 目前是 animals 副本，未与 professions.json 的职业做映射
6. **单位跨格移动的深度排序**：`IsometricDepthSort.moving_support_sort_y`（wandering_animal 在用，UnitSprite 未接入）

### 低优先级
7. 路径箭头美化（当前 `_draw` 画三角，可换 PNG）
8. HP 条样式（当前 ColorRect，可美化）
9. blockTitles 渲染（战棋默认走 terrain fallback 色块）

## 关键技术决策记录

1. **B1/B2 双模式并存**：所有 B2 代码一字不动，B1 走新路径。切换由 `Settings.battle_inline_mode` 控制。这保证了回归安全。
2. **「新增不修改，分支注入」**：main.gd 7 处侵入点全是 `if _battle_active:` 前置短路，false 时零影响。
3. **范式照搬 `is_world_map_open`**：pixel_world 已有 world_map 模态拦截范式（7 处调用点），B1 战斗模式 1:1 复制这套范式。
4. **战场坐标 ≠ 世界坐标**：21×21 战场的 `(0,0)` 对应世界 `world_origin`。chapter 里 unit.position 仍是局部坐标，由 UnitSprite 在渲染时加 origin 转世界 cell。GridSystem 完全不感知世界坐标。
5. **Node2D 没有 offset 属性**：发现 Godot 4 的 Node2D 不像 Sprite2D/AnimatedSprite2D 有 offset。简化方案用 `position + z_index`，不走 y_sort 双轨。

## suggested skills

- **planning-with-files**：继续多阶段工作时用 `task_plan.md` / `findings.md` / `progress.md` 跟踪（已在 phaserjs/ 目录建立）
- **handoff**：会话结束时生成交接文档（本文件即是）

## 如何继续

1. 读本文件了解全局
2. 读 `phaserjs/progress.md` 的「B1 阶段」段落了解详细实施
3. 读 `phaserjs/findings.md` 了解技术发现（坐标统一/API 签名/兼容性风险）
4. 用 breakpoint MCP 验证当前状态：`editor_ping` → `dbg_launch main.tscn` → 按 P 看战斗
5. 按「待办」优先级推进
