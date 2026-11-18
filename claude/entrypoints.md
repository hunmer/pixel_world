# 入口与启动

> 更新：2026-11-18（主场景改为 `scenes/Campaign.tscn`；autoload 8→9 新增 `CampaignSession`；场景表 +Campaign/SkillList）。

## 引擎入口

- `project.godot`：`run/main_scene = "res://scenes/Campaign.tscn"`（**2026-11-18 起**，此前为 Game.tscn）；`config/features = PackedStringArray("4.7", "GL Compatibility")`；窗口 1280×800；物理 `Jolt Physics`；输入映射含 `confirm` / `cancel` / `end_turn`。
- 运行：`godot --path .`（本机 `/Applications/Godot.app/Contents/MacOS/Godot`，实测 4.7.1；Windows 历史路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`，console 版 stdout 全缓冲——管道无输出 ≠ 没输出）。
- **9 个 autoload**（`project.godot [autoload]`，按注册顺序）：

| # | 名称 | 脚本 | 职责 |
| --- | --- | --- | --- |
| 1 | `Settings` | `scripts/settings.gd` | 用户偏好（user://settings.cfg；`battle_inline_mode` 等） |
| 2 | `SceneArgs` | `scripts/scenes/scene_args.gd` | 跨场景传参（`battle_args` 等） |
| 3 | `CampaignSession` | `scripts/campaign/campaign_session.gd` | **（2026-11-18 新增）** 冒险模式会话：档案/关卡/商店/出征令牌（973 行） |
| 4 | `Sfx` | `scripts/audio/game_sfx.gd` | UI/战斗音效池 |
| 5 | `LoadingScreen` | `scenes/LoadingScreen.tscn` | 全局加载遮罩 |
| 6 | `GameSession` | `scripts/scenes/game_session.gd` | 旧战旗会话路由 + 逐战场存档（user://battle_saves/） |
| 7 | `StartupConfig` | `scripts/scenes/startup_config.gd` | 调试启动配置（config/startup.cfg） |
| 8 | `GameCursor` | `scripts/game_cursor.gd` | 全局游戏光标 |
| 9 | `Panku` | `addons/panku_console/...` | 游戏内 `~` REPL（v1.7.9） |

> 排查 autoload 顺序问题时记得 `CampaignSession` 在 `GameSession` **之前**注册；campaign 出征的 `save_identity` 留空（不写旧 battle_saves）。

## 调试启动配置（`config/startup.cfg`）

- INI：`[startup] auto_open_last_scene / last_scene / excluded_scenes`（`docs/startup_config.md`）。编辑器调试读写 res://，导出后 user://。
- 可让 F5 直跳任意场景（含 main.tscn 世界、Battle.tscn——后者依赖 SceneArgs，建议走 Game.tscn 路由）。**当前工作树该文件有本地未提交修改**（直跳配置）。

## 场景入口表（16 .tscn 自有）

| 场景 | 角色 | 进入方式 |
| --- | --- | --- |
| `scenes/Campaign.tscn` | **默认主入口**：冒险模式（存档选择→营地→关卡） | project.godot main_scene / F5 |
| `scenes/Game.tscn` | 战旗会话路由（开发入口；冷启动自动续玩最近战旗） | 列表选"战旗入口" / startup.cfg |
| `scenes/Battle.tscn` | 战棋 B2 独立场景（**依赖 `SceneArgs.battle_args`，不能无参直启**） | Game/Campaign 路由 / B1 不用它 |
| `main.tscn` | 世界生态场景（B1 宿主） | Game 列表"生态世界" / startup.cfg |
| `scenes/Title.tscn` | 标题屏（含 SkillListButton → 技能图鉴） | — |
| `scenes/SkillList.tscn` | 技能图鉴（27+ 技能卡片，scripts/scenes/skill_list.gd） | Title 按钮 |
| `scenes/MapEditor.tscn` | 战场编辑器 | 世界按 E / Game 列表 |
| `scenes/SkillTest.tscn` | 技能/物品自测入口（44/44） | — |
| `scenes/HomeEntry.tscn` | 主页占位 | — |
| `scenes/DialogueDemo.tscn` | 分支对话演示 | — |
| `scenes/UIComponentGallery.tscn` | UI 组件画廊（F6 可独立运行） | — |
| `scenes/PixelFxGallery.tscn` | 特效画廊 | — |
| `scenes/Isometric3DTest.tscn` | 3D 柱网格验证 | — |
| `scenes/LoadingScreen.tscn` | autoload 遮罩场景 | — |
| `ui/pixel_panel.tscn` | 组件库 Panel | — |
| `tests/` 探针 ×5 | 截图/对齐探针（非玩法） | — |

## 冒险模式启动链（新默认主链）

```
Campaign.tscn (campaign_main.gd 装配层, 173 行)
  → CampaignSession.list_profiles()
     ├─ 有档案 → 存档选择屏（campaign_save_select，437 行）
     │    继续/新建（名字+AI难度）/重命名/删除
     └─ 无档案 → 直接新建流程
  → 营地 Hub（campaign_hub，416 行）：金币/公共库存/roster/进度
     ├─ 关卡列表（campaign_levels，245 行）→ 出征
     │    CampaignSession.prepare_battle(level_id)
     │      → 出征前快照落盘 + attempt 标记 → 产出 campaign_token
     │    campaign_battle_bridge → SceneArgs.battle_args{..., campaign_token}
     │    → change_scene(Battle.tscn)
     │    战斗结束 bridge.settle(result, chapter)
     │      → CampaignSession.settle_battle(token, result, chapter)
     │        胜：first_clear/repeat 奖励 + loot_table 独立 RNG 掉落
     │            + _diff_level_ups 升级差分 → 回营地（弹 level_up_presentation）
     │        负/弃：_settle_restore 恢复出征前状态
     ├─ 商店（campaign_shop，249 行）：data/shop.json，金币购买，
     │    limit_per_clear × completed_levels.size() 限购
  → changed(reason) 信号驱动 UI 刷新（不轮询）
```

## 世界场景启动（main.gd `_ready`）

```
main.gd._ready
  → _load_ecosystem_config → _compile_ecosystem_config（→ ecology_config_compiler）
  → _configure_generation_services()@485：装配 scripts/world/ 全部模块
  → _setup_player / _setup_camera / _setup_hud / _setup_minimap / _setup_world_map
  → _setup_day_night / _setup_depth_of_field / _setup_audio / _setup_fireflies / _setup_weather
    （presentation_stage builder 统一装配表现层）
  → _update_streaming()：首帧流式生成玩家周边 chunk
```

## 战斗 / 战场 / 编辑器入口（世界侧）

```
main.gd._unhandled_input
  ├─ KEY_P → _enter_battle()：world_to_chapter(采样器, 玩家格) 产出 chapter
  │    → Settings.battle_inline_mode ? _enter_battle_inline()（B1，add_child）
  │                          : change_scene_to_file(Battle.tscn)（B2）
  ├─ KEY_O → HUD BattlefieldPanel → battlefield_picked(path) → _enter_battlefield(path)
  └─ KEY_E → _open_map_editor() → MapEditor.tscn
```

Game.tscn 冷启动路由（开发用途）：`StartupConfig` 读 startup.cfg → 无直跳时 `GameSession.prepare_entry()` 决策链（`--battlefield` 参数 > 最近存档 > 默认 plains_skirmish）→ 带存档恢复进 Battle / 停在列表。

## 构建导出

- 无 `export_presets.cfg`；`.gitignore` 排除 `/builds/ /exports/ /android/`。打包建议见 `dependencies-and-config.md`。

## 运行时初始化注意

- **流式窗口**：世界只保证玩家周边 `STREAM_*` 范围内 chunk 存在；依赖全图数据的测试用 `WorldQueryService`（与生成顺序无关）。
- **视角旋转**：仅 4 正交角度（0/90/180/270），旋转只动 Camera3D；等距素材其余角度有拼缝，勿放开连续角度。
- **CampaignSession 先落盘后内存**：任何会改档案状态的操作（购买/出征/结算）都是先持久化再改内存态；重载即回到安全点。
- **截图退出**：main.gd `_shot_and_quit`（README 截图用）。
