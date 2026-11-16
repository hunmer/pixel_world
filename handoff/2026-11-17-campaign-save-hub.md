# 多冒险存档、Hub 与关卡闭环交接

记录时间：2026-11-17（Asia/Shanghai）。所有路径均相对于项目根目录。

## 当前状态与下一会话目标

本轮实现已经完成并向用户交付。后续用户实际体验发现世界地图关卡列表不可见，本次已修复并增加布局回归契约；当前没有尚未完成的功能项或已知阻塞。不要把本文件当作要求重新实施的计划。下一会话的具体新增目标尚未指定。

用户最初通过 `/grill-me` 澄清产品边界，随后确认实施，明确要求使用 DSH Team 尽量并行，执行成员模型为 **glm-5.3 / max**。这些产品决策已整理到 [docs/campaign_loop.md](../docs/campaign_loop.md)，请直接以该文档为规则与范围索引，不重复访谈或自行扩展商店、招募、配装等范围。

## 先读的现有产物

- [docs/campaign_loop.md](../docs/campaign_loop.md)：已确认玩法规则、存档位置、模块边界、操作流程、验证入口及结果。本交接不重复其产品规格。
- [project.godot](../project.godot)：新的默认玩家入口与 `CampaignSession` autoload 注册。
- [tests/contract_manifest.json](../tests/contract_manifest.json)：新增 `campaign` 分组的两项契约及独立场景 probe。probe 不能作为普通 `SceneTree --script` 契约运行。
- [AGENTS.md](../AGENTS.md)、[CLAUDE.md](../CLAUDE.md)、[DESIGN.md](../DESIGN.md)：项目规则、代码索引与 UI 规范，继续改代码前按需读取。

## 定位代码

| 关注点 | 入口 |
| --- | --- |
| 多档会话、出征与结算接口 | [scripts/campaign/campaign_session.gd](../scripts/campaign/campaign_session.gd) |
| 编解码与严格校验 | [scripts/campaign/campaign_profile_codec.gd](../scripts/campaign/campaign_profile_codec.gd) |
| 持久化、备份恢复与新版保护 | [scripts/campaign/campaign_profile_store.gd](../scripts/campaign/campaign_profile_store.gd) |
| 固定队伍、部署、补给与战后吸收 | [scripts/campaign/campaign_roster.gd](../scripts/campaign/campaign_roster.gd) |
| 关卡配置读取与配表 | [scripts/campaign/campaign_config.gd](../scripts/campaign/campaign_config.gd)、[data/campaign.json](../data/campaign.json) |
| 三屏路由与出征入口 | [scripts/scenes/campaign_main.gd](../scripts/scenes/campaign_main.gd)、[scenes/Campaign.tscn](../scenes/Campaign.tscn) |
| 存档选择、营地与关卡列表 | [scripts/scenes/campaign_save_select.gd](../scripts/scenes/campaign_save_select.gd)、[scripts/scenes/campaign_hub.gd](../scripts/scenes/campaign_hub.gd)、[scripts/scenes/campaign_levels.gd](../scripts/scenes/campaign_levels.gd) |
| 弹窗与公共格式化辅助 | [scripts/scenes/campaign_modal.gd](../scripts/scenes/campaign_modal.gd)、[scripts/scenes/campaign_format.gd](../scripts/scenes/campaign_format.gd) |
| 战斗场景桥接 | [scripts/battle/campaign_battle_bridge.gd](../scripts/battle/campaign_battle_bridge.gd) |
| 真实战斗终局接入 | [scripts/scenes/battle.gd](../scripts/scenes/battle.gd) 的 `_present_result`、`_settle_campaign`、`_on_result_presentation_finished`、`_on_exit_to_list` |

## 已验证证据与边界

详细结果和重跑命令见 [docs/campaign_loop.md 的验证入口](../docs/campaign_loop.md#验证入口)。本轮最后一次验证结果为：

- 数据契约 22 组通过；UI 契约全部通过，退出无脚本错误、音频资源残留报错。
- 地图列表问题已由运行时尺寸测量定位：`Screens/Levels` 原尺寸为 `(0,0)`，其下 `LevelScroll` 高度为 0；多个代码创建的 `Control` 使用 `set_anchors_preset(FULL_RECT)` 会保留初始 rect 并补偿 offsets，导致锚点看似正确但尺寸归零。修复 Campaign 屏幕树、三屏和弹层用 `set_anchors_and_offsets_preset(FULL_RECT)`，三屏的 `PageMargin` 也明确铺满；Hub 的 `InventoryPanel` 增加纵向 `SIZE_EXPAND_FILL`，避免库存滚动区被压成零高度。
- 新增 UI 契约第 ⑲ 组覆盖 1024×640 / 1280×800 / 1920×1080，逐层检查根、Screens、各屏和 PageMargin 尺寸，断言列表/Hub队伍与库存/关卡 scroll 高度为正，并验证首卡可见、滚动后末卡可见。完整 UI 契约 exit 0，输出 `campaign_ui_contract: ALL PASS`。
- 上述 UI 契约运行期间独立分配 `BREAKPOINT_RUNTIME_PORT`，没有占用现有会话端口；之后尝试 runtime log 时 9081 已不可达，因此本次最终确认以完整 headless UI 契约为准，未声称重新检查运行态日志。
- 最新生产代码的真实场景 probe 30 项断言通过，运行日志 `error/warning` 为空。曾在真实结算处下断点确认 `result=win`、冒险令牌有效、旧 `save_identity` 为空，随后已清除断点与 watch。
- 默认玩家入口另行启动验证：三屏节点完整，初始存档选择屏可见，错误／警告日志为空。
- 相关旧契约通过；没有运行全量测试，也没有把契约通过描述成全部玩法或视觉效果均已人工验收。

纯契约实际通过调用本机 Godot 二进制运行；manifest 和文档另提供统一 runner 的同名入口。实测引擎版本为 **4.7.1.stable.official.a13da4feb**，项目文档还存在 4.7 / 4.7.2 的描述差异，后续排错以实际运行版本为准。

## 本轮联调的关键教训

这些是后续修改容易重新引入的问题，而非待修缺陷：

1. **先退出旧弹层层级，再同步发出动作信号。** [scripts/scenes/campaign_modal.gd](../scripts/scenes/campaign_modal.gd) 的 `close()` 顺序为：防重入 → 恢复背景焦点 → `remove_child(self)` → `chosen.emit(action_id)` → `queue_free()`。若仅在信号后延迟删除，处理器同步打开的新弹层会被 Godot 自动改成 `@CampaignModal@…`，破坏节点定位与关闭链。禁止同步 `free()` 正在发射 `pressed` 的按钮／弹层；列表重建也采用移出后延迟释放。
2. **代码创建的节点查找需显式允许无 owner。** 测试使用 `find_child(name, true, false)`；默认 `owned=true` 曾使实际存在的代码节点返回 null。桩里的已通关 ID 也必须与实际关卡 ID 同源，不能混用 `level_0` 等假 ID。
3. **UI 契约隔离自动按钮音效，不改生产音频。** [tests/campaign_ui_contract.gd](../tests/campaign_ui_contract.gd) 暂停并在退出前恢复 `Sfx` 的 `node_added` 自动挂接。密集模拟点击后立即退出曾留下 MP3 playback；verbose 清单确认不是 UI 节点泄漏。音频系统背景可参照 [已有音效交接](2026-11-14-game-sfx-system.md)。
4. **物品查询的非空结果不代表 ID 合法。** 现有查询会对未知 ID 返回默认道具，校验必须核对返回 ID；技能同理。版本号需严格检查有限整数，不能先 `int()` 截断后接受 `1.5`。
5. **好备份不得被坏主档轮换覆盖。** 新存储包装先校验并由合法备份修复主档，再复用旧 IO 的轮换；任一存档层出现未来版本都拒绝写入。不要绕过包装直接覆盖文件，也不要为本功能修改旧战场存储。具体逻辑见 [scripts/campaign/campaign_profile_store.gd](../scripts/campaign/campaign_profile_store.gd)。
6. **结算不能原地恢复战场角色。** 终局提交发生在演出前，营地全恢复应作用于持久化副本；活跃战场 `chapter` 仍供演出使用。小战场玩家槽位不足也不能静默裁剪固定队伍，部署模块已经补充确定性空格分配。
7. **不要并行启动争抢同一运行桥端口的 Godot 进程。** 本轮契约串行运行，真实场景通过 MCP；不要以 `tool not found` 推断桥不存在并改用 shell 启动替代游戏。

## 工作树与运行现场

交接时尚未执行 git commit。业务修改、新增文件及 `.gd.uid` 仍在工作树中；实际清单以 `git status --short` 和 diff 为准，不能只检查已跟踪文件的 diff。原本已有用户修改，本轮未重置、覆盖或清理其他工作。

另外修改了 [tests/battle_result_presentation_contract.gd](../tests/battle_result_presentation_contract.gd)：把依赖 `Settings` autoload 的 `BattleUI` 从静态 preload 改成运行后动态加载，避免独立 headless 契约在 autoload 初始化前编译失败却仍输出成功标记。

[config/startup.cfg](../config/startup.cfg) 本来已有用户修改，运行场景又会自动改写 `last_scene`。本次 handoff 只读检查时其值为 `res://scenes/Campaign.tscn`，而访谈初期是 `res://scenes/MapEditor.tscn`。不要整文件恢复或将该开发配置自动当作业务变更提交；处理前查看当前差异与用户最新操作。

最终已打开新的默认存档选择场景，方便用户体验；交接时未重新检查运行进程，因此下一会话不要假定它仍在运行。集成测试进程已停止，无仍需收集输出的后台测试 job。测试使用独立临时存档目录，没有把测试冒险写入玩家目录；临时目录可能留有空目录或索引。

## 团队与会话记录

团队 `team_mwjk1w3x1t8i38r`（campaign-loop-design）两名执行成员均为 `zai-coding-cn / glm-5.3 / max`，调查、数据、UI 三项团队任务均已 done，最后成员均 idle，文件已冻结。没有必要为完成本次需求重复建队。

如需追溯实现，可以读取团队 handoff 记忆：数据 `mem_mwjmd4me20mcjmq`，UI `mem_mwjljnn61x0g5qt`。持久目标 `goal-c90f6f66-ab1a-4cbe-b00b-1b7bf94b3eba` 已标记 complete（revision 2）；不要在没有新用户请求时重新激活。

## Suggested skills（建议按下一任务调用）

- `save-systems`：继续改存档 schema、恢复、迁移或故障处理时。
- `game-ui-ux`：继续改三屏布局、焦点、弹窗或可访问性时，并以 [DESIGN.md](../DESIGN.md) 为项目规范。
- `godot-debug`：需要运行游戏、看画面、查报错、下断点或验证改动前必须加载；按其 MCP 流程进行。新会话可能需要重新启用工具，不继承上个会话的激活状态。
- `dsh-agent-team`：用户要求继续团队工作时调用；若仍指定模型，保持 glm-5.3 / max，并按文件边界协调写入。
- `grilling`：仅当用户提出新的需要澄清的产品决策或再次使用 grill 触发词时；本轮已经确认的规则不需重问。

本次用户明确要求保存在项目 `handoff/`，因此按该明确路径保存；覆盖 handoff 技能默认使用系统临时目录的建议。
