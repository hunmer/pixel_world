# 战场自动化（声明式战场 CLI）

对嵌入式战棋（`scripts/scenes/battle.gd` + `scripts/systems/`）做**无表现、可复现、可断言**的 headless 自动化执行：一份 JSON 场景声明 → 一次确定性对局 → 一份结构化战报 + 退出码。CI / 回归 / 平衡性批量模拟 / bug 最小复现均走这条链路。

```
场景 JSON ──BattleScenarioLoader──▶ scenario ──BattleRunner──▶ events[] + result ──BattleReport──▶ events.jsonl / result.json / summary.txt
                                                    │
                                                    ▼
                                     BattleActionResolver（与 battle.gd 共享的结算内核）
```

## 快速上手

以下命令均为 **PowerShell**（在本仓库根目录运行；每条一行，可直接复制执行）：

```powershell
# 跑内置示例（Godot 4.7 console 版；-- 之后是 CLI 参数）
& "D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tools/battle_cli.gd -- --scenario res://tests/fixtures/battle_scenarios/quick_duel.json

# 指定 seed 与输出目录
& "D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tools/battle_cli.gd -- --scenario res://tests/fixtures/battle_scenarios/deterministic_replay.json --seed 42 --out E:/reports/dr_42

# 内联场景（不经文件；JSON 用单引号整体包裹，内部双引号原样保留）
& "D:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tools/battle_cli.gd -- --scenario-json '{"version":1,"id":"tiny","battlefield":"res://data/battlefields/arena_1v1.json","seed":1,"factions":{"player":{"mode":"ai"},"enemy":{"mode":"ai"}}}'
```

退出码（脚本/CI 判定依据）：

| 码 | 含义 |
| --- | --- |
| 0 | 正常结束且全部断言通过（含 `stop_after_steps` 短复现） |
| 1 | 断言失败（战报 `result.assertions` 里有明细） |
| 2 | 输入参数 / 场景校验 / 非法操作（错误信息带 step 定位） |
| 3 | `max_turns` / `max_steps` 僵持保护触发——**未预期僵持不判成功** |
| 4 | 战报写盘 / 运行器内部失败 |

## 场景 JSON（version 1）

```jsonc
{
	"version": 1,                        // 必填，当前只支持 1
	"id": "my_scenario",                 // 可选，缺省取文件名
	"battlefield": "res://data/battlefields/arena_1v1.json",  // 引用预制战场（与 inline 二选一）
	"inline": { /* 内联战场，字段同 data/battlefields/*.json：rows/map、legend、playerUnits、enemyUnits */ },
	"seed": 7,                           // 整数；命中/必杀/技能/升级成长共用这一条 randf 流
	"limits": { "max_turns": 50, "max_steps": 1000 },   // 可选，僵持保护
	"stop_after_steps": 12,              // 可选，短复现：执行到第 N 步正常停（exit 0）
	"overrides": { "u_p_0": { "hp": 999, "mp": 30 } },  // 可选，按单位 ID 覆盖 hp/mp/level/exp/hasMoved/hasActed
	"factions": {
		"player": {
			"mode": "script",            // script | ai
			"script": [ /* 见下 */ ],
			"script_exhausted": "wait"   // wait（缺省）| fail（脚本耗尽报 exit 2）
		},
		"enemy": { "mode": "ai" }
	},
	"assertions": [ /* 见下 */ ]
}
```

单位 ID 规则与 `BattlefieldLoader` 一致：玩家方 `u_p_0..`、敌方 `u_e_0..`（按数组下标）；`inline` 战场走同一套校验管线（地形注册、行宽、职业存在、站位合法、不重叠）。

### 脚本（script 阵营）

按**轮次相位**逐条出队，一条 = 一个单位的复合行动（`move` + 至多一个终结构动作）：

```jsonc
{ "unit": "u_p_0", "move": { "x": 2, "y": 2 }, "attack": "u_e_0" },  // 移动后攻击（贴脸流）
{ "unit": "u_p_0", "skill": "fireball", "targets": ["u_e_0"] },      // 技能（id + 目标单位列表）
{ "unit": "u_p_0", "item": "hpPotion", "targets": ["u_p_0"] },       // 物品
{ "unit": "u_p_0", "wait": true },                                   // 等待
{ "end_turn": true }                                                 // 阵营立即结束本相位
```

- `move` 可省略（原地行动）；终结构动作也可省略（纯移动 = 移动后等待）。
- 校验失败（单位不存在/已死/已行动/距离超出/路径不可达/技能未拥有或冷却/物品耗尽等）→ `exit 2`，错误信息带 `step=N` 定位，**无静默 AI 回退**。
- 队列耗尽：`script_exhausted=wait`（缺省）时剩余单位按等待处理；`fail` 时报 exit 2。
- 战斗提前结束（分胜负 / 僵持保护 / `stop_after_steps`）时，**尚未消费的脚本条目直接作废**——不执行、不报错、不计步。
- `end_turn` 提前结束相位；未行动单位的标志由下一相位开始复位（与游戏一致）。

### AI（ai 阵营）

走游戏同款 `EnemyAI` / `PlayerAI`（确定性评分，无随机）。可选 `ai_pref`：

```jsonc
"ai_pref": {
	"strategy": "auto",          // auto | aggressive | defensive | nearest | weakest（仅玩家侧生效）
	"priorityTargetId": "u_e_1", // 优先目标（仅玩家侧 strategy 非 auto 时生效）
	"difficulty": "normal"       // novice | normal | hard | nightmare（两侧阵营通用）
}
```

#### AI 难度档（difficulty）

| 档位 | 击杀加分（普攻/技能/物品） | 反击权重 | 残血集火 | 候选选择 | 无目标时 |
| --- | --- | --- | --- | --- | --- |
| `novice` 新手 | 0 / 0 / 0 | ×0（无视反击） | 无 | 选**最差**候选 | 原地待命 |
| `normal` 普通（缺省） | 5000 / 4000 / 3000 | ×1.0 | 无 | 选最佳 | 朝最近敌移动 |
| `hard` 困难 | 12000 / 10000 / 8000 | ×2.0 | ×3.0/缺失血 | 选最佳 | 朝最近敌移动 |
| `nightmare` 噩梦 | 20000 / 16000 / 12000 | ×3.0 | ×8.0/缺失血 | 选最佳 | 朝最近敌移动 |

- `normal` 与历史行为**逐值等价**（缺省不写 = 原样）；残血集火只在目标已损血时生效（满血恒 0）。
- 敌方（`factions.enemy`）与玩家侧（`factions.player`，托管/`ai` 模式）通用；玩家侧 `strategy` 非 `auto` 时集火分与难度选择同样叠加。
- 声明式场景里**非法难度名严格报错**（exit 2）；游戏内 `Settings`（`enemy_ai_difficulty` / `host_ai_difficulty`，`user://settings.cfg` `[battle]` 节）宽容回 `normal`。

### 断言

```jsonc
{ "type": "winner", "op": "==", "value": "player" }          // player | enemy | ""（未分胜负）
{ "type": "battle_over", "op": "==", "value": true }
{ "type": "unit_alive", "unit": "u_p_0", "op": "==", "value": true }
{ "type": "unit_hp", "unit": "u_e_0", "op": "<=", "value": 10 }
{ "type": "unit_position", "unit": "u_p_0", "x": 2, "y": 2 }
{ "type": "turn_number", "op": "<=", "value": 5 }
{ "type": "steps", "op": "==", "value": 12 }
{ "type": "event_count", "op": ">=", "value": 20 }
```

数值断言支持 `== != <= >= < >`；`winner` / `battle_over` / `unit_alive` 只允许 `== / !=`。

## 战报

输出目录：`--out <dir>`，缺省 `user://battle_reports/<scenario_id>/run_<seed>/`。不同 seed（或不同 scenario_id）写入不同子目录、互不干扰；**同 scenario_id + 同 seed（或 `--out` 指向同一目录）重复运行会覆盖重写该目录下的三个文件，旧报告不保留**——需要留档请用不同 `--out`。

- **events.jsonl** —— 每行一个事件的 JSON。公共字段：`seq`（全局序号）、`turn`、`phase`、`actor`、`source`（`script` / `ai` / `runner` / `resolver`）。事件类型：`battle_start`（seed + 初始地图 + 全部单位快照）、`phase_start`、`move`（from/to/path）、`attack`（命中/未命中/必杀/反击/追击/双方伤害与血量）、`skill`（MP 扣减/冷却/逐目标命中）、`item`（剩余次数/HP·MP 变化）、`death`、`exp`、`level_up`（升到几级 + `gains` 各属性成长明细）、`wait`、`turn_end`、`battle_end`（winner）、`stop`（停止原因）。
- **result.json** —— 版本 / seed / 来源 / outcome（winner、battle_over、stop_reason、turns、steps）/ limits / 初始与最终全体单位快照（含死亡单位）/ 逐条断言评估（passed + 实际值 + 人读 summary）。
- **summary.txt** —— 人读摘要（事件流水 + 最终单位 + 断言结果）。

## 确定性契约

- 同 `seed` + 同场景 + 同 Godot 版本 ⇒ `events.jsonl` **逐字节一致**（`deterministic_replay` fixture 即此回归锚点；契约测试双跑比对）。
- **随机源边界（如实说明）**：runner 开局调用一次 Godot **进程级全局 RNG** 的 `seed(scenario_seed)`（`battle_runner.gd`），命中 / 必杀 / 技能 / 升级成长共用这一条全局 `randf` 流——**不是可注入的独立 RNG 实例**（规划阶段曾拟独立 RNG，实际实现选择了全局流）。这之所以安全，是因为 CLI 每次运行都是独立的短命 headless 进程，runner 是该进程内唯一的随机消费者（战场构建固定职业 / 武器 / 站位，不消耗随机数）。因此「同 seed 复现」的承诺限定于**单次运行单 runner** 的用法；若未来要在同一进程内跑多个 runner（或与其他随机逻辑共存），必须改为独立 RNG。可复现性还限定同一 Godot 引擎版本（`randf` / `randi` 实现属引擎内部，跨版本不承诺）。
- 单位 ID、行动顺序、AI 评分全部确定；**文件路径、显示名、时间戳不参与任何随机决策**（遵守项目确定性契约）。

## 实现边界（改动前必读）

- **`scripts/battle/battle_action_resolver.gd`** 是与 `battle.gd` 共享的结算内核（普攻/技能/物品结算 + 死亡 + 经验升级 + hasActed/hasMoved 语义）。**改战斗规则必须改这里**——runner 与真实战斗共用同一实现，不允许出现第二套业务规则。
- runner（`scripts/battle/automation/battle_runner.gd`）复刻 `turn_director.gd` 的行动驱动（move→终结构动作、敌方行动后无条件 hasActed、无敌人时全员待命），但**不带任何演出**（Tween/timer/精灵均不依赖）。
- 战报 / 存档边界：战报只写自己的输出目录；`user://settings.cfg` 与 `user://battle_saves/`（玩家进度）不受影响。
- 战棋 UI 回归（SkillTest.tscn 44 项、battle 契约测试）与 CLI 链路并行有效：resolver 被 battle.gd 与 runner 双向消费，一处改动两侧都要过测。
