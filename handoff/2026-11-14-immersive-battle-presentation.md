# 沉浸式战斗演出 — 独立舞台（2026-11-19，第三版）

> 本文描述**现行架构**：沉浸演出 = 角色进入独立舞台场景（隔离 World3D 的 SubViewport），
> 两阵营对角站位、按回合逐次出手。旧版「相机降到参战者近平视」（2026-11-14 第一版）
> 的 ImmersiveBattleCamera 仍在仓库中但不再被驱动，历史细节见文末。
> 契约入口：`python3 tools/run_contracts.py --test immersive_stage immersive_battle_integration --out <dir>`。

## 模块地图

| 文件 | 职责 |
| --- | --- |
| `scripts/battle/immersive_stage.gd` | 舞台本体（`ImmersiveStage extends SubViewport`）：搭建代理、逐 impact 出手序列、转场、取景、信号回交 |
| `scripts/battle/immersive_stage_layout.gd` | 纯布局逻辑（RefCounted 静态）：参战者收集、阵营对角站位、HP 初态重建、出手模板/标签 |
| `scenes/ImmersiveStage.tscn` | 空壳场景（根节点挂 immersive_stage.gd） |
| `scripts/scenes/battle.gd` | 接线：CanvasLayer(layer 99) + SubViewportContainer 挂舞台；`_use_immersive_stage()` 分流 |
| `scripts/battle/action_anim.gd` | 出手循环内核：`prepare_event / run_strike / finish_event` 事件级 API（传统路径与舞台共用） |
| `scripts/iso/unit_sprite.gd` | `setup_stage(unit, camera)` 第三初始化路径（无 board/world，位置=IsoProjection.grid_to_world） |
| `scripts/battle/battle_fx.gd` | `grid` 参数去类型（duck-type `{units: {}}`），舞台内第二实例渲染伤害数字/血条特效/飘字 |
| `tests/immersive_stage_contract.gd` | 契约：布局 + B1/B2 序列 + 取景自适应 |
| `tests/immersive_battle_integration_contract.gd` | 集成契约：开关/UI 联动/演出中关闭/默认关闭传统链路 |

## 数据流（一次普攻）

1. `BattleActionResolver.resolve_attack` 照旧结算出 `attack_event`（impacts 顺序 = 主击 → 反击 → 连击 → 夹击）。
2. `battle._resolve_combat_async` 调 `_use_immersive_stage(event, skipped)`：开关开、非整体 skip、有参战者 → `await _immersive_stage.present(event, _unit_sprites, anim_speed, skipped)`；否则走原 `action_anim.play(...)`（关闭开关 = 原链路，行为不变）。
3. `present()`：
   - 收集真实单位（只读）→ `presentation_started`（battle 侧显示 stage layer）→ `_build_stage`；
   - 代理 = 真实单位深拷贝，HP 用各自首个作为目标的 impact `hp_before` 重建，`position` = 对角槽位格；
   - `_play_enter` 逐帧淡入（时长 / anim_speed）；
   - **逐 impact**（严格原顺序）：`_build_strike_event`（anim 按实际 source 武器）→ `strike_scheduled`（宿主放出手音）→ `await _anim.run_strike(pseudo)`；
   - **命中帧推进**：`impact_presented` 信号（ActionAnim HIT 相位）先 `_apply_impact_state`（HP=hp_after、死亡置位+DOWNED+渐隐）再生成伤害数字、回交宿主（impact 音效）；出手循环返回后兜底推进仅在信号未发生（被 skip 截断）时执行一次，绝不双推；
   - 全部 impact 后 `_anim.finish_event()` → `_reassert_deaths()`（finish 的视觉恢复会清倒地姿态，死亡单位重放 DOWNED+隐藏）→ `_play_exit` 淡出 → `presentation_finished`（battle 侧隐藏 stage layer）→ teardown。
4. 死亡/升级/胜负演出与结算推进全部留在真实战场原位置（`present` 返回后照旧执行），舞台绝不写回真实单位/相机。

## 站位（对角阵营）

- 参战者 = 出手者 + 主目标 + 每 impact source/target 去重（真实夹击友军、反击方都在内）。
- faction 固定分侧：player/ally → 左下（anchor (0,+5)，outward +y），enemy/other → 右上（anchor (0,−5)，outward −y）；**敌方先手不换侧**，治疗/buff 同阵营不造敌方。
- 阵营内 rank：出手者 0（前排中央）、主目标 1、其余 2；**相同 rank 用原始参加下标显式决胜**（Godot `sort_custom` 是不稳定 pdqsort，不能依赖默认稳定性）。
- 前排 3 槽（中/左(−1,+1)/右(+1,−1)），多出的沿 outward 每 2 格退一排。

## 取景自适应（防裁切）

`_center_camera`：focus = 全部站位包围盒水平中心；先按基准 `STAGE_ZOOM=3.6` 放好相机，再把每个站位「四向脚点（±0.35 身位）+ 头顶点（+1.45 立绘/血条）」经 `camera.unproject_position` 实际投影，与视口安全框（横 48px/纵 56px）比对；溢出则 `zoom = STAGE_ZOOM / overflow`（正交线性换算一次到位，下限 0.75）。任何窗口比例/人数组合不裁切参战者。契约 E 节以 480×800 / 640×480 / 1280×800 × 2/6/10 人矩阵断言：采样点全部在视口内、敌方均值屏幕位置严格右上/我方左下、同窗口 zoom 随人数非增。

## 转场与倍速

- 进入/退出转场逐帧步进，帧数 = `时长 × 60 / anim_speed`（speed 8 ≈ 1-2 帧）；`_cancelled`（cancel/退出树）立即跳出，不挂任何 await 补等待。
- cancel()（宿主 _exit_tree）后 present 协程在下一个 await 检查点直接 return，**不补发 presentation_finished**（宿主本身在退出树）。
- 演出中 `request_skip()`：当前出手立即收尾，剩余 impact 只推进状态不再演出；`finished.skipped=true`。

## battle.gd 接线要点

- `_stage_layer`（CanvasLayer layer=99）**平时 visible=false**，`presentation_started/finished` 才显示/隐藏——否则空舞台或收尾黑幕会盖住真实战场（V3 修复的真实视觉缺陷，headless 测试盲区）。
- **独演侧栏隐藏**（V4）：同一对 started/finished handler 里 `_hide_battle_side_columns/_restore_battle_side_columns`——进入独演即隐藏「战场侧栏」（画布层 100/101 压在舞台层 99 之上）：battle_ui 右侧栏（`battle_ui.get_sidebar()`）+ B1 世界 HUD 左停靠栏/右侧栏（`GameHUD/HUDRoot/LeftRail|SidePanel`，世界侧栏在战斗侧栏下方同宽露出，只藏战斗侧栏会漏）。恢复按 `_stage_hidden_columns` 记录的**原可见性精确还原**（原本隐藏不强行打开）；`cancel()` 不补发 finished，`_exit_tree` 里兜底 `_restore_battle_side_columns()`——B1 世界 HUD 属于 main 不随战斗释放，漏恢复 = 永久隐藏。
- 旧 `ImmersiveBattleCamera` 仍创建并接开关信号，但演出链路不再调它的 begin/end（双镜头驱动会打架）；`immersive_battle_camera` 契约因此保留旧 rig 纯逻辑断言（env-skip 基线）。
- 舞台 `strike_scheduled → _sfx.play_strike`、`impact_presented → _sfx.play_impact`（注意不是 `_on_impact_presented`——后者会在真实战场生成特效）。
- B1/B2/campaign 共用：B1 与 B2 都经 battle.gd 同一 `_resolve_combat_async/_resolve_skill` 分流。

## 契约覆盖（tests/immersive_stage_contract.gd）

- A 布局纯逻辑：参战者顺序/对角/朝向/HP 初态/dies 聚合/出手模板/标签/敌方先手不换侧/治疗不造敌方/**稳定排序**。
- B B2（arena_1v1）：① 开启整场（含真实 HP 零写回、真实相机四元组零写入、命中帧 HP 推进、**侧栏隐藏→恢复+记录清空**）② 敌方先手 ③ 倍速可感知 ④ 演出中 skip（**侧栏恢复**）⑤ 整体 skip 走传统链路（**不动侧栏**）⑥ 关闭恢复（**侧栏保持可见**）⑦ 死亡 + 舞台层隐藏 + **原本隐藏的侧栏不被强行打开**。
- C B2（plains_skirmish）：⑧ 治疗 ⑨ buff ⑩ AoE ⑪ 反击/连击/夹击合成链（标签/模板/逐次 HP/死亡终态 DOWNED+隐藏）⑫ 演出中销毁 battle 的退出清理（layer 显示中、侧栏隐藏中）。
- D B1：世界内联同样进舞台、世界相机零写入；**三处侧栏（战斗+世界左栏/右侧栏）演出中隐藏、结束恢复；⑭ 演出中退出战斗经 _exit_tree 精确恢复世界侧栏**。
- E 取景自适应矩阵（见上）。
- `immersive_battle_integration`：默认关 guard 走传统链路（相机七元组复原）、开关开启进舞台、演出中关闭 → request_skip。

## 已知盲区与待办

1. **最终画面未目视验收**：headless 契约证明序列/数据/投影几何，不证明像素美感、转场手感、音画同步；需要窗口目视 B1/B2 普攻/技能/夹击各一场。
2. 契约 StageWatcher 依赖舞台内部字段（`_stage_units/_slots/_sprites/_fade_rect`）——重构舞台内部命名需同步契约。
3. `--script` 契约模式下 autoload 标识符（Settings/SceneArgs/LoadingScreen）编译期不可用，必须 `root.get_node("Settings")` + `.set/.call`；主脚本不得 preload battle 场景链（编译期连锁失败）。
4. `Engine.set_meta("breakpoint_state", {...捕获 self...})` 若不在退出前 remove_meta，引擎关机时 breakpoint_mcp bridge 会触碰已析构对象 → recursive_mutex SIGABRT（契约 exit=-6）。
5. 旧版（相机近平视）历史：见 git 历史与 `scripts/battle/immersive_camera.gd`；其「ACTIVE 关闭在动作边界恢复」「wall-clock 超时」等经验已吸收进舞台契约。

## 运行态验证（如需）

先读 `godot-debug` skill 并按会话激活 Godot MCP；B1 从 `res://main.tscn` 按 P、B2 关 inline mode 后按 P 或 campaign 出征；断言用 `runtime_read_state` 注册 reader 或契约 exit code。不要 bash 直启游戏、不要直启无 SceneArgs 的空 Battle.tscn、不要把 headless 数值通过当作画面验收。
