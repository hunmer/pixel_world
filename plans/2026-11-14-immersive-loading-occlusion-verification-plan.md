# 验证计划：加载界面 + 沉浸遮挡（沉浸式战斗第二阶段）

- 日期：2026-11-14　作者：verifier（team_mwfq49kp1hvs8）　任务：task_mwfq4wv36iaz2
- 性质：**前瞻验收契约**。截至本文撰写（HEAD），加载界面与沉浸遮挡实现尚未落盘
  （`scripts/battle/` 仅 10 个 .gd，无 loading/occlusion 模块；`scripts/scenes/battle.gd` 无相关接入）。
  本文定义实现交付后必须通过的断言清单；标 `<待绑定>` 的接口名/节点路径以实现为准，验证执行时先用
  `find_symbol` / `project_search` 复核并回填，行号均为当前 HEAD 值、重构后会漂移。

## 0. 挂钩点与既有事实（断言设计依据）

| 事实 | 位置 | 对验证的意义 |
| --- | --- | --- |
| 演出序列 = prewarm → 血条隐藏 → begin → play → end | `scripts/scenes/battle.gd:1062-1077`（普攻）、`battle.gd:1241-1256`（技能） | 加载界面应包裹的最外层窗口；物品路径 `battle.gd:1274-1320` 不走沉浸 |
| 跳过入口 / 退出清理 | `battle.gd:637-642`（`_skip_action_presentation`）、`battle.gd:1744-1757`（`_exit_tree` 先 `cancel()`） | 异常路径隐藏断言的注入点 |
| 相机状态机 | `scripts/battle/immersive_camera.gd:56-97`（begin，ENTERING 0.45s）、`:101-107`（end）、`:127-132`（cancel）、`:283-289`（_finish_enter→ACTIVE） | 加载界面可见窗口 ≥ enter 转场时长；遮挡生命周期 = begin~end |
| B1 世界地形接口（prop 淡出） | `scripts/iso/isometric_terrain_3d.gd:89-134`：`get_prop_cells/get_prop_block_occlusion_data/get_prop_fade_alpha/get_active_prop_fade_cells/set_prop_fade_target(cell,alpha)/advance_prop_fades(delta)` | 沉浸遮挡在 B1 的天然落点；B1 入口 = `main.gd._terrain` |
| B2 内嵌同款地形 | `scripts/iso/battlefield_renderer.gd:105-110` `_ensure_terrain_3d()` → 子节点名 `BattlefieldTerrain3D` | B2 入口 = `battle.renderer` 下该节点；与 B1 同接口 |
| **B1 写竞争源** | `main.gd:3417` `_update_player_occlusion(delta)` 每帧无条件调用（不因 `_battle_active` 暂停）；`:3221` 每 0.5s（`PLAYER_OCCLUSION_REFRESH_INTERVAL=0.5`，main.gd:61）rebuild；`:3330` 把不在玩家遮挡集合的格 `set_prop_fade_target(cell, 1.0)` | 沉浸遮挡格会被周期性拉回 alpha=1 → **最可能失败的竞态**，见 B4 |
| 遮挡判定既有范式 | `main.gd:3235-3283` `_collect_player_prop_occluders`：锚点深度（`camera_back.dot(anchor) >= 主体深度-0.05`）+ 屏幕矩形相交 + 贴图像素 alpha 命中；淡化 alpha=`PLAYER_OCCLUSION_BLOCK_ALPHA=0.20`（main.gd:67） | 沉浸遮挡应复用同一判定形状（主体换成参战点集合）；"不误伤背后物体"= 深度方向断言的依据 |
| 设置默认值 | `scripts/settings.gd:28` `battle_immersive_presentation=false`；`:21` `battle_inline_mode=true` | "默认关闭不弹/不淡出"断言的前提 |
| 预烘焙现状 | `battle.gd:1136-1167` `_prewarm_damage_fx_variants/_prewarm_fx_variant` **同步**烘焙（缓存键 `路径|JSON|`，命中即返回） | "预烘焙 await" 指实现会把这段变为可等待/挪到加载界面可见帧之后；时序断言见 A5 |
| 契约测试模式 | 注册 `Engine.set_meta("breakpoint_state",{name:func})` → MCP `runtime_read_state` 读取；尾部 `print("IMMERSIVE_* PASS/FAIL checks=N")` | 新断言沿用该模式；headless 直跑判据 = stdout PASS 行 |

## A. 加载界面（预期模块 `<待绑定>`，如 battle_loading_overlay）

| # | 断言点 | 载体与断言语义 | 预期值 | 失败时看什么 |
| --- | --- | --- | --- | --- |
| A1 | 唯一性 | 合约：进入战斗后遍历场景树按类型/名搜实例 | 全树恰好 1 个实例；连续两次进入战斗（B2 换场景再开一场）后仍 1 个 | `runtime_get_tree` 搜出的重复实例路径；error 日志 |
| A2 | 全局复用 | 合约：记录第一场 instance id → 退出 → 再进战斗 → 重新查询 | 同一 instance id（跨场复用，不随 Battle 节点销毁） | 第二场查不到节点（挂在 Battle 下被销毁）或 id 变化 |
| A3 | Label 右下角锚点 | MCP `runtime_get_property`（或合约直读）：`anchor_right/anchor_bottom`、`grow_horizontal`、offset；若实现未声明数值，按语义断言 | `anchor_right==1.0 && anchor_bottom==1.0`（或实现文档声明显式值，二者取其一并注明）；`grow_horizontal==GROW_DIRECTION_BEGIN`；label 全局矩形不越出 viewport、右下间隙 ≤ 实现声明值 | 读到的 anchor/offset 实际值 vs 期望；label 全局 rect |
| A4 | show/hide 幂等 | 合约：连续 `show()×3`、`hide()×3` 后查 visible / 子 Label 数 / 信号连接数 | 状态不叠加：Label 数恒 1、无重复连接、visible 与单次调用一致 | 子节点数 >1（每次 show 新建 Label）；重复信号回调日志 |
| A5 | 展示时序：≥1 帧可见 + 预烘焙 await | 合约（关键断言）：在真实 Battle 上触发沉浸演出，记录 `show()` 后 `Engine.get_process_frames()`=f0、hide 时刻 f1；若实现提供 `visible_frame_count` 计数器则直接断言 | `f1 > f0`（跨过至少 1 个 process_frame）；`visible_frame_count >= 1`。若实现用 `await RenderingServer.frame_post_draw` / `get_tree().process_frame` 均满足；headless 下二者照常推进，可测 | f1==f0（show→prewarm→hide 同帧完成，界面永远不可见）；prewarm 改造后丢缓存命中（第二次演出变慢，可对比两次耗时） |
| A6 | 默认关闭不弹 / 物品不弹 | 合约：`Settings.battle_immersive_presentation=false` 下跑普攻+技能+物品各一次，采样 overlay.visible；物品路径在开启状态下也采样 | 全程 visible==false（含开启状态下的物品路径：`_resolve_item` 不接管相机，也不弹加载） | 采样到 visible==true 的时间戳 + 对应 `[combat-event]/[skill-event]/item` 日志行 |
| A7 | 退出/异常隐藏 | 合约+MCP：三路径覆盖——①演出中 ESC 跳过（ENTERING skip）；②`_exit_tree`/B1 败北退出；③ACTIVE 中关闭开关。每路径结束后断言 overlay.visible==false 且下一场还能再 show | 三路径均隐藏、可再次使用 | 路径结束仍 visible==true；`[ImmersiveCamera] Restore/Restored` 日志缺失 |
| A8 | B1/B2 两条真实路径 | B2：扩展 `tests/immersive_battle_integration_contract.gd` 模式（SceneArgs+真实 Battle）；B1：MCP `dbg_launch scene="res://main.tscn"` → 注入 P（keycode 80）→ runtime 采样 | 两模式下 A1-A7 语义各跑一遍（B1 至少覆盖 A5/A6/A7 的运行态版） | B1 专属：overlay 挂错层被 main.gd 场景切换销毁；`[Battle] B1 就地模式` 日志（battle.gd:320）确认路径 |

## B. 沉浸遮挡（预期接口 `<待绑定>`，建议实现提供纯查询函数）

| # | 断言点 | 载体与断言语义 | 预期值 | 失败时看什么 |
| --- | --- | --- | --- | --- |
| B1 | 选中集合 = 相机与单位之间 | 合约：摆位舞台（1 格 prop 在相机↔单位连线遮挡位、贴图 alpha 实心），调实现的遮挡收集入口（建议签名 `collect_engagement_occluders(points, camera) -> Array[Vector2i]`，无副作用） | 遮挡位格 ∈ 返回集合；集合 ⊆ `get_prop_cells()` | 返回集合为空（漏选）或含无关格；无查询函数则只能退到 B2' 运行态观测 |
| B2 | 不误伤背后物体 | 同上舞台再加 1 格：anchor 深度比**全部**参战点更远（背后） | 背后格 ∉ 集合；运行态下其 `get_prop_fade_alpha==1.0` 全程 | 背后格 alpha 被压到 0.2（深度方向写反）——对照 main.gd:3271 的方向语义（`camera_back.dot(anchor) < 主体深度-margin` → skip） |
| B3 | 生命周期跟随演出 | 合约：ACTIVE 期间采样沉浸格 alpha；end()/cancel() 后 `get_prop_fade_alpha(格)→1.0`（允许 await `advance_prop_fades` 收敛，阈值 `PROP_FADE_SETTLE`）；死亡收尾路径同样恢复 | 进入演出 alpha→目标值（≤0.2 或实现声明值）；end/cancel/_exit_tree/致死演出后全部回 1.0 | `[ImmersiveCamera] Engaged` 后 alpha 仍 1.0（没接管）；`Restored` 后 alpha 残留 <1（没恢复） |
| B4 | **B1 写竞争**（最关键） | 合约（B1 运行态）：沉浸 ACTIVE 持续 ≥2.5s（跨 ≥4 个 0.5s 玩家遮挡刷新周期，main.gd:61/3221），期间每 0.2s 采样沉浸格 alpha | 沉浸格 alpha 全程 < 1.0（不被 main 的 `_rebuild_player_prop_occlusion`（main.gd:3330 恢复 1.0）拉回）；实现须用 `_battle_active+is_engaged` 跳过玩家 rebuild 或 alpha 合并取 min，验收断言不因方案不同而变 | alpha 采样序列呈周期性弹回 1.0（0.5s 节奏）即实锤；配 `[ImmersiveCamera] Engaged` 时间戳 |
| B5 | 默认非沉浸路径不变 | 合约：Settings=false 下跑一场战斗，演出前后 `get_active_prop_fade_cells()` 集合 == 战斗外玩家遮挡自身集合（无新增） | 沉浸关闭时战场格零淡化；非战斗期玩家遮挡（main.gd:3217）行为不变（世界侧目视回归见 C-目视7） | 演出时刻出现新的 fade 格但 enabled==false |
| B6 | B1/B2 入口各自正确 | B2：integration 合约断言淡出发生在 `battle.renderer/BattlefieldTerrain3D`（battlefield_renderer.gd:105-110）；B1：MCP 断言发生在 `main._terrain` 且两场各自生效 | B1 战斗淡出落在世界地形、退出后世界无残留；B2 落在内嵌地形、场景销毁即随树清理 | B2 找不到 BattlefieldTerrain3D（相机 viewport 时序导致 `_ready:102` 未建 3D——实现须保证入口在 setup 后可达）；B1 退出后世界格 alpha 残留 |
| B7 | 方块（柱）遮挡覆盖 | 静态审查 + 运行态：确认实现除 prop 外是否处理地形柱 block 本身（IsometricTerrain3D 现只有 prop fade 接口）。若实现含柱级接口 `<待绑定>`，对"相机与单位之间的高柱"断言其隐藏/缩短/降 alpha；若无柱级接口 | 任务规格含"方块/树木集合"——**柱部分必须有着落**：有接口则断言生效且可恢复；无接口则在本计划标记验收缺口并上报 Lead（见薄弱点 5） | 近平视 10° 下高柱仍挡角色（只能目视发现，headless 断言依赖实现接口存在） |
| B8 | 性能：不遍历无限世界 | 合约：单次遮挡收集耗时（`Time.get_ticks_msec()` 差）≤5ms（headless）；处理格数 ≤ `get_prop_cells().size()`（B1 仅已流式加载 chunk 的格，天然有限）；B2 ≤ width×height。静态审查 diff：不出现全域世界坐标循环 | 耗时与格数达标；`runtime_get_monitors` 的 process time 相对演出前基线增幅可忽略 | 收集耗时 >5ms；演出开始瞬间掉帧（monitors 采样） |
| B9 | 与常驻系统无回归 | 回归 C 全绿 + 演出期间 `presentation_offset` 仍由沉浸模块独占（battle.gd:273-281 kick 已让位）；血条/像素特效照旧 | C 部分两合约 PASS 且新增断言全过 | 任一既有断言由绿变红 |

## C. 回归与执行方式

### C1. headless 契约（先跑，作基线；实现合入后复跑 + 新增合约）
```
D:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/immersive_battle_camera_contract.gd
D:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --script res://tests/immersive_battle_integration_contract.gd
```
- 判据：stdout 末行 `IMMERSIVE_CONTRACT PASS checks=59` / `IMMERSIVE_INTEGRATION PASS checks=39`（实现后 checks 只增不减且仍 PASS）；exit code 0；输出无 `SCRIPT ERROR`。
- 坑：console 版 stdout 全缓冲——管道无输出 ≠ 没输出，等进程退出再读全量；测试等待用 wall-clock（`Time.get_ticks_msec()` 15s 超时，handoff 已证帧数超时会伪失败）。
- 新增断言的落点：优先扩展这两个合约（或实现自带新合约，同命令模式）；reader 名沿用 `immersive_contract` / `immersive_integration`，需要 MCP peer 读态时用 `runtime_read_state(name=...)`。
- 只跑与本改动相关的合约，不跑全量（`game_hud_contract.gd` HEAD 上本就坏，不算回归）。

### C2. 真实 B1/B2 路径（需运行态时走 godot MCP，先读 skill godot-debug）
- B1：`dbg_launch({scene:"res://main.tscn"})` → `runtime_inject_input`（P，keycode 80，press+release，confirm:true）。
- B2：先把 `Settings.set_battle_inline_mode(false)`（`runtime_call_method`，confirm:true），再同上按 P。
- 断言用 `runtime_assert_node_state / runtime_assert_scene_structure / runtime_await_condition({timeout_ms:5000+})`；`runtime_get_log` **必带** `levels:["error","warning"]` + `since_seq` 增量。同一时刻只保留一条 9081 桥接实例；结束还原本机偏好（immersive=false、inline=true）。

### C3. headless 通过 ≠ 画面验收，必须有窗口目视清单
1. 加载界面：出现/消失不闪烁、停留时长合理（不拖沓）；Label 右下角不越界、不遮关键 HUD。
2. 沉浸演出期间：相机与单位之间的高柱/树木确实淡出；结束后恢复无突兀闪变。
3. 背后（更远）的树不被淡化。
4. 进入/恢复 10° 近平视转场不穿地形（handoff 待办 1/2 延续项）。
5. B1 与 B2 各自：普通攻击、近战/远程/AoE 技能、反击、多段（impacts≥2）。
6. 退出（胜/负/ESC/B1 败北回 Main）后：无残留淡化、无加载界面残留、相机数值回快照。
7. 非战斗期玩家遮挡（main.gd:3217）仍正常（世界探索时树照旧淡出）。
截图类（`runtime_screenshot_diff`）仅当断言判不了且用户同意后使用。

## D. 断言点 → 工具映射速查

| 断言 | 首选载体 | 具体调用要点 |
| --- | --- | --- |
| 合约内逻辑断言（A1/A2/A4/A5/A6、B1-B3/B5/B8） | headless 契约 `_check` | 沿用 `tests/immersive_battle_*.gd` 的 `_check(cond,label)` + `breakpoint_state` reader；帧计数用 `Engine.get_process_frames()`，超时一律 `Time.get_ticks_msec()` |
| 节点属性/锚点（A3） | `runtime_get_property` → 值写进合约 `_check` 固化 | path=`<overlay 路径>/Label`，读 anchor/grow/offset |
| 节点存在/唯一/消失（A1/A7） | `runtime_assert_scene_structure({expect:[{path,type},{path,absent:true}]})` | B1/B2 各跑一遍 |
| 异步状态到位（A8/B3/B4） | `runtime_await_condition({path,property,value,op:"eq"/"lt",timeout_ms:5000-15000})` | alpha 采样轮询由合约内 while+`state_changed`/计时完成 |
| 运行态数值快照 | `runtime_read_state({name:"immersive_contract"|"immersive_integration"})` | 只读合约结果 JSON（finished/passed/checks） |
| 日志判据（所有失败的证据采集） | `runtime_get_log({levels:["error","warning"],since_seq})` / headless stdout | 关键行：`[ImmersiveCamera] Begin/Engaged/Restore/Restored`、`[combat-event]/[skill-event] impacts=`、`[Battle] BattleReady`、`[battle] B1 就地模式`、`[battlefield-render] 等距 3D 方块渲染完成`、`IMMERSIVE_* PASS/FAIL` |
| 性能（B8/B9） | `runtime_get_monitors()` 对比演出前后 | process time 增幅阈值 ±实现声明 |

## 薄弱点 Top 5（按命中概率排序）

1. **B1 写竞争**（B4）：`main.gd:3417` 玩家遮挡不因战斗暂停，0.5s 周期把沉浸格拉回 alpha=1。演出 >2.5s 的周期采样断言必抓；实现必须显式协调（跳过 rebuild 或合并 alpha）。
2. **加载界面"至少 1 帧"时序**（A5）：prewarm 现为同步（battle.gd:1156-1167），若 show→prewarm→hide 同帧完成，界面永不可见。帧计数断言 `f_hide > f_show` 必抓；headless 可测（process_frame 照常推进）。
3. **全局复用被场景切换销毁**（A2）：overlay 若挂在 Battle 节点下，B2 `change_scene` 后即销毁——第二场看不到或双实例。跨场 instance id 断言必抓。
4. **遮挡集合方向搞反**（B1/B2）：淡化背后物体或漏掉相机之间的格。摆位舞台（正面 1 格 + 背后 1 格）双向断言；依赖实现提供纯查询函数，无则只能运行态 alpha 观测、精度降级。
5. **方块（柱）遮挡规格缺口**（B7）：IsometricTerrain3D 现只有树木 prop 的 fade 接口，地形柱 block 无对应机制；若实现只做了 prop，任务规格里的"方块"就没着落——验收时若无柱级接口，直接上报 Lead 作为缺口而非误判实现失败。

## 执行顺序建议（实现合入后）

1. 静态审查实现 diff（绑定 `<待绑定>` 接口名/路径，复核第 0 节行号漂移）。
2. headless 跑 C1 两合约（基线仍绿）+ 新增合约。
3. MCP：B2 路径（integration 场景化断言 A8/B6）→ B1 路径（main.tscn+P，A8/B4 长采样）。
4. 窗口目视 C3 清单（用户在场时）。
5. 全部结论写入验证报告：断言点 → PASS/FAIL → 失败证据（文件:行号 + 日志原文）。
