# Rule: 托管（Autoplay）自动调试

> 本规则是 `AGENTS.md`「关键约束」的展开。托管默认开启、走编辑器桥接启动等硬约束见 AGENTS.md;本文讲**完整托管调试流程**。

托管系统让玩家方单位自动行动（移动+攻击），用于无人值守跑完整场战斗、验证战斗/AI/回合/经验/胜负判定等模块。任何阵容都能开启托管（托管遍历运行时 `grid.units` 的 player 单位，与阵容来源无关）。

## 相关文件

| 文件 | 职责 |
| --- | --- |
| `godot/scripts/systems/player_ai.gd` | 玩家方托管决策器 `PlayerAI.decide(unit, grid, enemies, pref)`。阵营中立，`strategy=auto` 时零侵入复用 `EnemyAI.decide`；否则按策略加权打分。 |
| `godot/scripts/scenes/battle.gd` | 托管循环 `_run_player_auto_phase` / `_player_auto_act`（镜像敌方 AI 回合结构），托管开关 `_toggle_hosting`，偏好面板 `_open_pref_panel`。手动输入路径在托管期间被锁。 |
| `godot/scripts/tests/battle_test.gd` | 调试入口：从命令行参数解析 `hosting`（默认 `true` 启动即全托管）。 |
| `godot/scripts/core/cmd_args.gd` | 命令行参数解析工具 `CmdArgs`（`has_flag`/`get_bool`/`get_string`），解析 `OS.get_cmdline_user_args()` + `OS.get_cmdline_args()`。 |

## 一键全托管调试（推荐）

`battle_test.gd` 默认开启托管（`CmdArgs.get_bool("hosting", true)`）。改了战斗相关代码后，直接跑 `BattleTest.tscn`，托管会自动跑完玩家→敌方→循环→胜负→跳转的完整流程，无需人工操作：

```text
mcp__godot__dbg_launch({ "scene": "res://scenes/BattleTest.tscn" })
```

> `dbg_launch` 不支持带 CLI 参数，所以经 MCP 启动时 `hosting` 走默认值 `true`。需要覆盖默认值时用下面的命令行方式。

等 10-15 秒后读输出，验证：

- `runtime_get_log({ "levels": ["error", "warning"] })` **没有托管相关报错**（特别注意：曾有的 `modulate:a does not exist in Node3D` 已修复，若复现说明单位死亡动画回退了）。
- 场景最终跳转到 `LevelSelect.tscn`（托管跑完整场战斗并分出胜负），可用 `runtime_get_tree()` 确认根节点。

> 更严格的自动化验证（断言胜负文字、等待 banner 出现）见 @knowledges/project-debug-and-auto-verification.md。

## 手动验证托管开关 / 偏好面板

若要观察 UI 交互（开关按钮、偏好面板），需启动时关闭托管。**不用改代码**，直接用 Godot CLI 带命令行参数启动（`--` 分隔用户参数，Godot 4 推荐；不加 `--` 也兼容）：

```bash
# 推荐：-- 分隔后的参数进 OS.get_cmdline_user_args()
godot -d --path D:/phaserjs/godot res://scenes/BattleTest.tscn -- --no-hosting
# 兼容写法
godot -d --path D:/phaserjs/godot res://scenes/BattleTest.tscn --hosting=false
```

进战斗后（托管已关闭）：

1. 左上角点「开启托管」按钮 → 玩家方立即自动行动到回合结束。
2. 点「托管偏好」按钮 → 弹出居中面板，每个 player 单位可配：
   - **优先目标**下拉：动态列出当前存活敌方单位（单位名 + 职业），选中后该单位绝对优先打它。
   - **策略**下拉：`自动(伤害最大)` / `激进(优先击杀)` / `保守(规避反击)` / `最近(贴脸)` / `残血(收割)`。
3. 偏好仅本场战斗有效（存 `battle.gd` 内存，不持久化）；关闭面板后立即生效。
4. 点「关闭托管」切回手动操作。

## 托管偏好数据结构（仅本场有效）

```text
# battle.gd 的 _auto_prefs：key = 单位 id (StringName)
{
  priorityTargetId: StringName | "",   # "" = 用 strategy
  strategy: StringName                 # auto / aggressive / defensive / nearest / weakest
}
```

未配置单位退化为 `PlayerAI.default_pref()`（等价现有 `EnemyAI` 行为）。

## 在自定义场景启用托管

任何调用 `Battle.tscn` 的地方，往 `SceneArgs.battle_args` 加 `"hosting": true` 即可启动即托管，无需改 battle.gd：

```gdscript
SceneArgs.battle_args = {
    "chapter": <your_chapter>,
    "hosting": true,   # 加这一行
}
```
