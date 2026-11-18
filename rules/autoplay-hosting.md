# Rule: 托管（Autoplay）自动调试

> 本规则是 `AGENTS.md`「调试与验证（代码优先）」的展开。MCP 按会话激活、scene 必传等硬约束见 AGENTS.md；本文讲**托管怎么开、怎么验**。

托管（autoplay）让**玩家方**单位由 `PlayerAI` 自动行动（移动 + 攻击 + 技能/物品），用于无人值守跑完整场战斗，验证战斗、AI、回合、经验、胜负判定。敌方回合仍走原有敌方 AI，托管不改变任何规则或确定性契约。

## 相关文件

| 文件 | 职责 |
| --- | --- |
| `scripts/battle/turn_director.gd` | 托管状态与循环：`hosting_active`（L54，默认 `false`）、`is_hosting()`、`set_hosting(active)`、`toggle_hosting(can_start_now)`、`start_player_auto_phase()`、`_player_auto_act(u)`；偏好存 `_auto_prefs`（L55），`get_prefs/get_pref/set_pref` 访问 |
| `scripts/systems/player_ai.gd` | `class_name PlayerAI`（L10），`PlayerAI.decide(unit, grid, enemies, pref)`（L35）；阵营中立，`strategy=auto` 时复用 `EnemyAI` 逻辑 |
| `scripts/scenes/battle.gd` | `_toggle_hosting()`（L957）、`_open_pref_panel()`（L965）；L83 读 `SceneArgs.battle_args["hosting"]` 决定是否 `turn_director.set_hosting(true)` |
| `scripts/battle/battle_ui.gd` | 「开启托管 / 关闭托管」按钮（L131 附近）、「托管偏好」按钮与面板 |
| `scripts/core/battlefield_loader.gd` | 战场 JSON 的 `hosting` 字段（L12 注释、L131 `bool(d.get("hosting", false))`）→ `info.hosting` |
| `scripts/editor/battlefield_doc.gd` | 地图编辑器里勾选/保存 `hosting` 字段 |
| `main.gd` | `_enter_battle()`（L3942）、`_enter_battlefield()`（L3963）、`_enter_battle_inline()`（L4004） |

## 默认是关闭的

- `main.gd` 的两条战斗入口（B1 就地 / B2 切场景）都显式写 `"hosting": false`。
- `turn_director.hosting_active` 初始 `false`。
- 所以正常从世界进战斗时是**手动操作**，旧文档说的「默认托管」已不成立。

## 开启托管的三种真实方式

1. **战斗内按钮（手动观察用）**：点左上角「开启托管」。`toggle_hosting()` 只在玩家回合、IDLE 态、未在跑时立即启动自动回合；回合中途开启会在下个玩家回合生效。
2. **战场 JSON `"hosting": true`（推荐给复现/自动跑）**：在 `data/battlefields/*.json`（或地图编辑器勾选）里加 `"hosting": true`，经 `_enter_battlefield()` 进入时由 loader 读出并传给 `SceneArgs`。
3. **代码里设 `SceneArgs`**：

```gdscript
SceneArgs.battle_args = {
    "chapter": chapter,
    "world": self,
    "hosting": true,
}
```

> 不要为提高效率把 `main.gd` 的默认值改成 `true`——那会让所有正常游戏都自动代打。

## B1 / B2 两种战斗模式

| 模式 | 进入 | 结束时 |
| --- | --- | --- |
| **B1 就地**（默认，`Settings.battle_inline_mode=true`） | `main.gd` 实例化 `BattleSystem`，`SceneArgs.battle_args = {chapter, world, hosting}` | 3 秒后 `battle_finished` 信号 → `main.gd` `_exit_battle()`，不切场景 |
| **B2 切场景** | `change_scene_to_file("res://scenes/Battle.tscn")` | 3 秒后 `change_scene_to_file(return_to_scene)` |

**`scenes/Battle.tscn` 不能无参直启**：它依赖 `SceneArgs.battle_args["chapter"]`。优先 headless 夹具准备完整参数后实例化；需要 B1 集成时再启动 `res://main.tscn`，通过当前战斗入口函数进入，不注入 P 推进流程。

## 托管偏好（每单位，仅本场有效）

面板由 `battle.gd:_open_pref_panel()` 打开，数据存在 `turn_director._auto_prefs`（key = 单位 id）：

```gdscript
{
  priorityTargetId: StringName,  # "" = 不指定，按 strategy 选目标
  strategy: StringName          # auto / aggressive / defensive / nearest / weakest
}
```

| 策略 | UI 文案 | 行为 |
| --- | --- | --- |
| `auto` | 自动(伤害最大) | 复用 `EnemyAI` 打分，输出期望伤害最高的行动 |
| `aggressive` | 激进(优先击杀) | 优先能击杀的目标 |
| `defensive` | 保守(规避反击) | 降低被反击风险 |
| `nearest` | 最近(贴脸) | 优先距离最近 |
| `weakest` | 残血(收割) | 优先当前 HP 最低 |

未配置的单位退化为 `PlayerAI.default_pref()`（`{priorityTargetId:"", strategy:auto}`）。偏好**只存内存**，战斗结束即丢，不写存档。

## 验证托管（先代码，后运行态）

1. 优先相关契约、`tools/battle_cli.gd` 或 `tools/run_simulations.gd` 验证规则、AI、回合和确定性；只有托管循环本身的问题才补对应场景夹具，不能用模拟器通过代替场景集成通过。
2. 场景测试先准备完整 `SceneArgs.battle_args`，设置 `hosting:true` 后实例化战斗；测试配置与正常游戏设置隔离，不修改正常默认值。
3. 确需 MCP 集成验证时，读取当前入口与节点路径，使用 `runtime_call_method` 调用战斗入口和托管流程方法（如 `set_hosting(active)`，并按实际状态触发自动阶段）；方法签名、前置条件以当前源码为准。函数可驱动就不点击托管按钮。
4. 仅验证托管按钮点击 / P 输入处理本身时才模拟该输入。

用有超时的状态等待观察回合推进和结束，再断言胜负、回合、存活数或目标不变量；不要固定等 10–30 秒后查结束日志。`runtime_assert_screen_text` 可补验横幅，但不能替代战斗结果断言。

```text
mcp__godot__runtime_get_log({"levels":["error","warning"],"since_seq":<本次基线 latest_seq>})
```

日志用于定位，始终带 `levels` 并按序号增量读取。

**卡住不动的排查顺序**：

1. `turn_director.hosting_active` 是否为 true（`dbg_scopes` 不可用时看按钮文案是否已变「关闭托管」）。
2. 是否卡在 `_player_auto_act` 的 `await _tween_move`（动画/格子异常）。
3. `PlayerAI.decide` 是否返回空决策（无路径/无目标）——通过代码断言 / 状态读取或必要的断点定位，日志仅辅助。
4. 胜负是否已判定但 `_battle_ended` 已置位、循环提前退出。

## 约束

- 托管只接管玩家方；不要在托管期间同时注入手动移动/攻击输入。
- 托管沿用原有规则与随机契约；测试使用隔离夹具 / 存档环境，不假定正常战斗会话不会自动保存。
- 验证顺序与根 AGENTS.md 一致；截图只用于断言不足的视觉问题，沿用本任务已有明确授权（见 @rules/mcp-debugging.md）。
