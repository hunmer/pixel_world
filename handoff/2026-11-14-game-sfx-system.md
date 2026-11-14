# 2026-11-14 全局音效系统（Sfx autoload）接入

## 本次完成

用 `assets/audio/sfx` 的真实素材建立了全局音效系统，并接入战棋与世界探索：

- **新增 autoload `Sfx`**（[scripts/audio/game_sfx.gd](../scripts/audio/game_sfx.gd)，注册于 project.godot）：
  - 43 个 cue → 素材路径/音量/音高随机映射表（`CUES` 常量，一目了然可增删）。
  - 10 个 AudioStreamPlayer 固定池轮转，无每次播放分配；步长/节流防刷屏。
  - **UI 声自动挂接**：`SceneTree.node_added` 监听，任何 `BaseButton` 入树即连接
    `pressed`→`ui_confirm`、`mouse_entered`→`ui_hover`（meta `_sfx_ui_attached` 防重复），
    OptionButton `item_selected`→`ui_select`。全游戏按钮零改动覆盖。
- **战棋接线**（scripts/scenes/battle.gd、scripts/battle/turn_director.gd）：
  - 回合开始 `turn_player/turn_enemy`（`_on_player_phase` / `_on_enemy_phase`）。
  - 出手音 `_play_strike_sound`：slash→剑/斧/枪按武器 type，`projectile:arrow`→放箭。
  - 受击音 `_play_impact_sound`：miss/heal/crit/unit_death/物理三系命中（斧→钝、枪弓→穿刺、剑→斩）、
    法系 `skill_<element>`、低血量警报（我方 HP≤25%，Sfx 内 6s 冷却）。
  - 胜负/结算演出 `_on_presentation_sound`：真实素材优先，素材缺失回退原程序化波形
    （cue 映射在 `_presentation_cue_to_sfx`：victory/defeat/loot→equip/nameplate→select/boss→skill_dark）。
  - 升级 `ui_levelup`（`_gain_exp` 检测 `exp.levels` 非空）。
  - 脚步声按战棋地形：`Sfx.play_step(<terrain type>)`——手动移动在 `_perform_move`（每次移动一声），
    托管/敌方 `_tween_move` 逐格播放。
- **世界探索**（main.gd `_try_move`）：`Sfx.play_world_step(ctx)` 按目标格 CellContext 的
  is_water/雪原群系/森林地貌/山岩地貌选脚步素材，null 回退 plain。
- **设置保存**（scripts/settings.gd `save()`）：成功后 `save` 音。
- **契约测试** [tests/game_sfx_contract.gd](../tests/game_sfx_contract.gd)：43 cue 素材存在+可加载+可播放、
  脚步映射、UI 自动挂接，**ALL PASS**（注意测试里连播同一 cue 会被 0.08s 节流拦截，
  断言前要 `sfx._last_play_at.clear()`）。

## 已验证 / 已知坑

- `godot --check-only --script` 单脚本模式不加载 autoload，报 `Identifier not found: Sfx/SceneArgs`
  是该方式固有局限；真实启动（main.tscn、SkillTest.tscn headless）无任何脚本错误。
- 尚无总线布局（无 default_bus_layout.tres），所有声音走 Master，没有分类音量设置。

## 可以接着做（按优先级）

1. **BGM 接线**（`assets/audio/bgm/` 25 首）：标题/主菜单（`bgm_menu_*`）、战斗（`bgm_battle_*` 按章节/优势劣势/BOSS）、
   结算（`bgm_result_victory/defeat`）、剧情（`bgm_story_*`）、营地（`bgm_prep_camp`）、结局（`bgm_end_*`）。
   需要音乐淡入淡出管理器（参考 scripts/world_audio_system.gd 的昼夜交叉淡化实现），
   战斗内替换/叠加 encounter_transition.gd 的程序化 sting。
2. **总线布局与音量设置**：建 Master←Music/SFX/UI 的 bus layout + `Settings` 增音量滑条
   （slider²→`linear_to_db`，见 audio-design skill）；世界音频与 Sfx 都应路由到对应总线。
   目前 settings.cfg 没有任何音频键。
3. **角色语音接线**（`assets/audio/voice/`，8 角色 × attack/hurt/cry/laugh/panic/confused/shy）：
   需要职业→角色映射（hero/mercenary/priest/veteran/pegasus/hierarch/elf_companion/demon），
   挂到 `_play_strike_sound`（attack）与 `_play_impact_sound`（hurt）按 attacker/source 单位选角色。
   `voice_registry.json` 里可能已有映射数据，先读它。
4. **`unit_damaged`/`counter`/`bow_draw`/`promote`/`ui_cancel`/`ui_error`/`ui_menu_open/close`/`ui_turn_end`
   素材已进 CUES 表但还没接线**：反击（CombatSystem counter 流程）、取消移动/菜单 ESC、
   无效操作提示（射程外点击）、单位菜单开合、玩家手动结束回合（battle_ui 结束回合按钮走通用
   `ui_confirm`，可换成 `ui_turn_end`）。
5. **环境音**（`assets/audio/ambience/` 8 地点 + `sfx/terrain/` 的 river/wind loop）：
   世界里已有昼夜音乐+雨声+动物声（world_audio_system.gd），可按 biome 加常驻 river/wind loop
   与 B1 战斗就地取景时叠加地点 ambience。
6. **`sfx/ley/` 6 个 Ley 线特效音**：等 Ley/灰潮玩法落地后再接。
7. **润色**：脚步声可与移动动画节拍对齐（世界 move_time / 战棋 0.15s/格）；胜利/失败可在播
   `sfx_victory/defeat` 之外切 `bgm_result_*`；`AudioStreamRandomizer` 进一步丰富重复音色。

## 相关文件清单

- `scripts/audio/game_sfx.gd`（新，autoload Sfx）
- `project.godot`（autoload 注册）
- `scripts/scenes/battle.gd`（回合/出手/受击/升级/胜负/移动脚步）
- `scripts/battle/turn_director.gd`（托管/敌方移动脚步）
- `main.gd`（世界脚步，_try_move 内 3 行）
- `scripts/settings.gd`（保存音）
- `tests/game_sfx_contract.gd`（新契约测试）
