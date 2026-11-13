# 沉浸式战斗演出交接

- 日期：2026-11-14
- 项目：`/Users/Zhuanz/Documents/pixel_world`
- 引擎：Godot 4.7 / GL Compatibility
- 已提交实现：`a681e53 Add battlefield settings and immersive combat camera presentation`
- 提交范围：13 个文件，740 行新增、9 行删除；包含生产代码与两个针对性合约。
- 当前状态：真实 B1/B2 战斗链路、设置联动、相机状态恢复和中断边界已做 headless 验证；最终渲染画面尚未做有窗口人工验收。
- 下一阶段重点：在实际窗口中检查近平视构图、地形遮挡、角色朝向和转场平滑，再决定是否需要纯表现层调参。

## 用户目标与交付范围

在战斗右侧现有 tabs 中增加【战场设置】，提供【沉浸式演出】开关。开启后，真实攻击和技能在实际地图中先把相机平滑降到参战角色附近，以接近平视的视角播放原有 ActionAnim；同一事件的反击、追击和多段 impacts 完整结束后，再恢复演出前的战术相机。

本实现：

- 复用真实 B1/B2 Camera3D 和真实单位 Sprite3D，不创建替代演示场景。
- 不修改战斗格位、结算顺序、伤害次数或单位逻辑位置。
- 保留默认关闭时的原战术推近、旋转和 B1/B2 kick 行为。
- 保留常驻血条演出期隐藏/结束恢复，以及 PixelFx 预热和受伤表现。
- 物品仍走原有短动画；沉浸式接管只覆盖攻击与技能的 `attack_event`。

## 设置入口与持久化

入口：战斗右侧 `InfoTabs` →【战场设置】→【沉浸式演出】。

- 默认值：`false`。
- 战斗中允许切换；新值立即作用于当前镜头的生命周期和后续动作。
- 持久化文件：`user://settings.cfg`。
- ConfigFile 位置：section=`battle`，key=`immersive_presentation`。
- Settings 属性：`Settings.battle_immersive_presentation`。
- 写入接口：`Settings.set_battle_immersive_presentation(value: bool)`。
- UI 信号：`BattleUI.immersive_presentation_changed(enabled: bool)`。
- 可断言控件名：`ImmersivePresentationToggle`。

设置关闭时的语义是有意区分的：

- `ENTERING`：先反向恢复战术相机，恢复完成后才继续普通 ActionAnim，避免两个 size tween 竞争。
- `ACTIVE`：让当前完整动作结束，再由 `end()` 恢复。不要改成立即恢复，否则 ActionAnim 最后的相机快照写回可能留下交战中的 size。
- 后续尚未开始的动作不再进入沉浸式演出。

## 关键文件与接口

| 文件 | 职责与接续点 |
| --- | --- |
| `scripts/battle/immersive_camera.gd` | 核心模块 `ImmersiveBattleCamera`；状态机、参战者构图、快照、平滑进入/恢复、跳过与取消。 |
| `scripts/battle/battle_settings_tab.gd` | 独立设置页构造器；`populate(tab, immersive_enabled, on_changed) -> CheckButton`。 |
| `scripts/battle/battle_ui.gd` | 在现有 tabs 的【托管】和【日志】之间加入【战场设置】；转发真实开关信号。 |
| `scripts/settings.gd` | 默认 false、`user://settings.cfg` 读写及 setter。 |
| `scripts/scenes/battle.gd` | B1/B2 真实相机注入，以及攻击/技能的 `begin → ActionAnim.play → end` 可等待接入。 |
| `scripts/iso/isometric_camera_3d.gd` | 新增 `presentation_distance`，让近平视演出缩短实际相机距离；默认仍为 `CAMERA_DISTANCE = 64`。 |
| `tests/immersive_battle_camera_contract.gd` | 独立相机/设置/UI 合约，覆盖几何、状态和中断边界。 |
| `tests/immersive_battle_integration_contract.gd` | 真实 Battle + SceneArgs + SkillSystem + ActionAnim 的集成合约。 |

对应 `.tscn` 与 `.uid` 已随 `a681e53` 提交；不要重复生成另一套测试入口。

## 演出生命周期

### 初始化

`battle.gd::_ready()` 在 ActionAnim setup 后创建名为 `ImmersiveCamera` 的节点：

- B1 注入 `_world._cam`。
- B2 注入 `board.camera`。
- 初始 enabled 来自 `Settings.battle_immersive_presentation`。
- `battle_ui.immersive_presentation_changed` 直接连接 `_immersive_camera.set_enabled`。

`ImmersiveBattleCamera.setup()` 把 `process_priority` 设为 100，使 main/IsoBoard 的常规 advance 先执行，再由沉浸模块刷新有效焦点。

### 一次完整交战

攻击与技能都在结算已经生成同一个 `attack_event` 后执行：

1. 保留 `_prewarm_damage_fx_variants(...)`。
2. `_set_unit_bars_visible(false)`，隐藏常驻血条。
3. `await _immersive_camera.begin(event, _unit_sprites, animation_speed, skipped)`。
4. `await action_anim.play(event, animation_speed, skipped or _immersive_camera.consume_skip_request())`。
5. `await _immersive_camera.end()`。
6. 继续原有单位刷新、死亡收尾和战斗结束检查。

反击、追击、多段和 AoE 都包含在同一个 event/impacts 中，因此一次 begin/end 覆盖整个交战；不要在每个 impact 上重复接管相机。

默认关闭、空 event、无有效参战点或预先 skip 时，`begin()` 不接管相机，原 ActionAnim 行为保持不变。

### 状态与快照

状态枚举：

- `INACTIVE = 0`
- `ENTERING = 1`
- `ACTIVE = 2`
- `RESTORING = 3`

公开接口：

- `setup(camera)`
- `set_enabled(value)`
- `is_engaged()`
- `get_state()`
- `begin(event, unit_sprites, animation_speed = 1.0, skipped = false)`
- `end()`
- `request_skip()`
- `consume_skip_request()`
- `cancel()`

快照保存并恢复：有效焦点、当前/目标 yaw、当前/目标 elevation、`presentation_distance`、`presentation_offset`、正交 size、projection、near、far 和 global transform。恢复结束会清理 snapshot/current，并回到 INACTIVE。

## 构图与相机所有权约定

### 必须复用原 Camera3D

ActionAnim、PixelFx 伤害数字、飘字和血条都引用当前真实相机做投影。不要再创建并切换到一个独立展示 Camera3D，否则这些 2D/3D 混合表现可能错位。

### 焦点通过 presentation_offset 接管

B1 的 main 每帧会重写 `focus_position`，B2 的 IsoBoard 也会推进相机。沉浸模块不直接锁死逻辑 focus，而是维护：

`presentation_offset = 有效演出焦点 - 当前逻辑 focus_position`

这样常规系统继续运行，演出焦点仍能稳定接管，结束后恢复原 offset。`process_priority = 100` 是该约定的一部分。

### 近平视仍保持四正交 yaw

- 进入时长：`0.45s / animation_speed`。
- 恢复时长：`0.36s / animation_speed`。
- 缓动：SINE / EASE_IN_OUT。
- 演出 elevation：10°。
- yaw 只从当前基准的 0/90/180/270 四个方向中选择，按参战双方横向分离评分；不要开放连续角度。
- `presentation_distance` 按横向跨度取 4.8–7.5；size 取 3.4–12。
- 取景收集 attacker、primary target，以及所有 impact 的 source/target。

缩短 `presentation_distance` 是为了避免低仰角下相机仍停在 64 世界单位外、被地形遮挡。不要把该逻辑改成永久改变常规相机距离。

### 不要改写 zoom 来实现演出

IsoBoard 每帧会按 `_target_zoom` 更新正交 size。沉浸模块直接插值 size 和 `presentation_distance`，不接管常规 zoom。后续改动若写 zoom，必须重新处理 B2 的每帧所有权冲突。

## 跳过、取消与已知竞态

### 进入转场中的跳过

此时 ActionAnim 尚未 play。`battle.gd::_skip_action_presentation()` 先调用 `request_skip()`，让镜头反向恢复；随后 `consume_skip_request()` 把同一次跳过传给 ActionAnim，避免镜头已经退出却仍播放完整动作。

skipped ActionAnim 不捕获或推近相机，所以允许与恢复并行。

### ACTIVE 中关闭的 size 竞态

ActionAnim 会保存自己的相机 size，在 strike/return 中推近，并在 `_finish_play()` / `_restore_camera_immediate()` 最后写回。

曾发现的风险：如果 ACTIVE 中关闭立即完成沉浸恢复，而 ActionAnim 仍在运行，它可能最后把 size 写回交战值；随后 `immersive.end()` 因已经 INACTIVE 而不再恢复。

当前修复是：ACTIVE 中关闭只更新 enabled，等待当前完整动作结束，由 `end()` 统一恢复。不要用另一套并行 size tween 覆盖这个顺序。

### 退出与死亡

`battle.gd::_exit_tree()` 首先调用 `_immersive_camera.cancel()`，立即 kill transition 并恢复快照，然后继续原有血条恢复、结果视觉、存档和 kick 清理。`ImmersiveBattleCamera._exit_tree()` 也有 cancel 防御。

真实 B1/B2 已验证败北和场景退出后没有镜头数值残留。

## 血条与 PixelFx 联动

- 血条仍在 ActionAnim 前隐藏，由原 finished、物品结束和 `_exit_tree` 路径恢复；沉浸模块不另建血条状态机。
- `_prewarm_damage_fx_variants()`、`_prewarm_fx_variant()`、`_prewarm_item_damage_fx()` 必须保留在原位置，不要重复烘焙或挪回受伤帧。
- PixelFx 继续使用同一个真实 Camera3D 的 `unproject_position`，所以复用原相机是兼容性的关键。
- 沉浸 engaged 时，`battle.gd::_on_action_phase_started()` 跳过旧 strike/return kick；`_apply_action_camera_kick()` 不再让 B1 additive kick 或 B2 presentation_offset 覆盖演出焦点。
- 默认关闭时旧 kick、ActionAnim size 推近和恢复行为不变。

## 已实际执行的验证

以下是 `a681e53` 提交前实际执行的验证结果。本次交接任务只写文档，没有重跑测试。

### 独立相机与 UI 合约

通过 Godot MCP 启动 `res://tests/immersive_battle_camera_contract.tscn` 的独立 headless peer，再读取：

```text
runtime_read_state(name="immersive_contract", peer="peer-25")
```

结果：`finished=true, passed=true`，59/59。

覆盖：默认 distance=64、真实距离变化、ACTIVE/10°/四向 yaw、ActionAnim 推近兼容、全 impacts/AoE 构图、完整恢复、ACTIVE 关闭的 size 竞态、ENTERING 关闭与跳过、cancel、预跳过、设置页回调和真实 BattleUI 五个 tabs。

### 真实 Battle 集成合约

通过 Godot MCP 启动 `res://tests/immersive_battle_integration_contract.tscn`，再读取：

```text
runtime_read_state(name="immersive_integration", peer="peer-30")
runtime_get_log(levels=["error", "warning"], peer="peer-30", since_seq=0)
```

结果：`finished=true, passed=true`，39/39；error/warning 日志为空。

该合约用 BattlefieldLoader 加载 `res://data/battlefields/arena_1v1.json`，通过 SceneArgs 实例化真实 `Battle.tscn`，由真实 SkillSystem → ActionAnim → ImmersiveCamera 驱动 guard；不是单独的新相机 demo。

覆盖：默认关闭时保持原相机；真实开关开启；ACTIVE 关闭在动作边界恢复 size、position、rotation、elevation、yaw、distance 和 presentation_offset；ActionAnim 快照清理；ENTERING skip 同步跳过真实动作；ENTERING 关闭只恢复镜头、不错误跳过动作。

测试等待必须使用 wall-clock 超时加状态信号。早期按 1200 headless 帧计时会在真实 tween 完成前伪超时，已改为 `Time.get_ticks_msec()` 的 15 秒超时；不要退回固定帧数超时。

### 真实 B1

从 `res://main.tscn` 启动独立 headless peer，按 P 进入 B1；没有直启空 Battle.tscn。

实测：

- 真实 CheckButton、Settings 和 ImmersiveCamera enabled 联动。
- guard、powerSurge、普通攻击以及 impacts=2/3 的反击/多段事件均只执行一次 Begin → Engaged → Restore → Restored。
- 自动战斗到回合 5 败北并退出后，相机恢复 size=12.5、elevation=30°、presentation_distance=64。

### 真实 B2

通过 Settings 将 inline mode 设为 false，再从 `res://main.tscn` 按 P，经真实 SceneArgs 进入 B2。

实测：

- powerSurge、fireball 和真实普通攻击进入沉浸链路。
- ACTIVE 稳定采样：ImmersiveCamera state=2、enabled=true，elevation=10°、distance=4.8、projection=正交；ActionAnim 推近时 size 会基于演出 size 再变化。
- ACTIVE 中通过真实开关关闭，当前动作结束后恢复。
- 败北退出回 Main 后，size=12.5、elevation=30°、yaw=45°、distance=64，presentation_offset 与 B1 kick 均为零；error/warning 为空。

### 其他检查

实际执行：

```bash
git diff --check
```

结果：通过。实现未修改 `scripts/battle/action_anim.gd`；测试后已还原本机偏好为 `battle_immersive_presentation=false`、`battle_inline_mode=true`，本任务启动的 peer 均已停止，未干扰用户的 9081 实例。

## 真实限制与已知待办

1. **最终画面未验收。** 上述测试均为 headless；它们证明真实战斗链路、状态机和相机数值恢复，不证明最终渲染构图、像素清晰度、地形遮挡、角色脚底锚点或视觉平滑已经合格。
2. **需要窗口目视检查。** 建议分别检查 B1/B2 的普通攻击、近战/远程技能、反击、多段和 AoE；观察进入/退出是否穿地形，双方是否同时入镜，Sprite3D front/side/back 是否合理，血条和 PixelFx 是否跟住单位。
3. **宽范围技能可能取景较远。** 当前用全部参与者包围盒和 size 上限保证覆盖，超大跨度 AoE 的“近景感”可能弱于 1v1；只能在目视后调整构图参数，不要牺牲目标覆盖。
4. **ACTIVE 关闭不是立即切回。** 这是为避免 ActionAnim size 写回竞态的明确设计；如产品要求立即中断，必须同时改 ActionAnim 的快照所有权并补回归，不应只改 `set_enabled()`。
5. **输入恢复依赖原战斗状态机。** 演出期间本来就只有 skip 输入；沉浸模块不另设输入锁。若后续重构 mode 或 main 的 B1 输入短路，需要重新验证退出后旋转、缩放、平移和拾取。

## 后续验证入口

需要运行验证时先读 `godot-debug` skill，并只跑相关测试。可使用上述两个 `.tscn` 的独立 headless peer 和 `runtime_read_state` 断言；真实 B1/B2 都从 `res://main.tscn` 按 P 进入，B2 通过 Settings 切 inline mode。不要用 bash 直启游戏，不要直启没有 SceneArgs 的空 Battle.tscn，也不要把 headless 数值通过当作画面验收。
