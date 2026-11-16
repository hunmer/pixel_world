# 冒险存档与关卡闭环

默认玩家入口为 `res://scenes/Campaign.tscn`。选择或新建独立冒险档后进入营地（Hub），查看金币、公共物品、固定队伍和关卡进度；通过世界地图的纵向关卡列表进入现有战场。

## 首版规则

- 每份存档是独立冒险，支持新建、加载、重命名、确认删除。列表显示金币、通关数、保存时间；选中最近冒险，但不自动加载。
- 新档金币为 0，以第一关现有我方角色和装备组成固定跨关队伍。角色等级、经验和成长属性保留。
- 初始随身物品汇入公共库存。出征按角色默认携带方案与固定队伍顺序分配，库存不足时不生成额外物品。
- 第一关默认解锁，其后线性解锁；已通关的关卡可重复挑战，全通后仍可继续游戏。
- 首次通关奖励 200 金币和 1 份现有恢复物品；再次通关奖励 50 金币。具体奖励由关卡配置管理，在地图展示。
- 胜利提交本次战斗实际获得的经验、等级、物品消耗、奖励和进度。返回营地全员复活、恢复 HP/MP，清除战斗临时状态。
- 失败或主动放弃恢复出征前数据，不奖励、不扣除物品、不保留本次经验。
- 创建、出征前、胜利后自动保存，营地提供立即保存。战斗中退出程序后，重新加载回到出征前营地，不恢复回合。
- 每次出征有独立令牌，结算只提交一次。保存失败保留当前状态并允许重试，避免重复发奖。

## 模块边界

`CampaignSession` 管理当前冒险与跨场景服务；`scripts/campaign/` 中的模型、存储和配置模块管理纯数据与磁盘持久化。存档使用独立目录，带整数版本与备份；加载校验通过后才应用。

`campaign_battle_bridge.gd` 负责准备出征、注入 `SceneArgs.battle_args` 和打开战场。`battle.gd` 复用现有战斗内核，在胜负确定后提交冒险结果，再播放结算演出。冒险战斗不设置旧 `save_identity`，不会写入逐战场续玩记录。

旧入口 `res://scenes/Game.tscn` 保留，供逐战场 demo、生态世界和编辑器等开发用途。旧战场记录不导入冒险档。

## 首版范围

营地只查看四类数据及详情，不含商店、招募、配装、编队或金币消费。世界地图先使用关卡列表，不新增地图地形、剧情或战斗内容。

## 使用与存档位置

启动项目后点击「新建冒险」，输入名称即可进入营地；以后在存档列表选择「加载」。营地的角色与物品行可打开详情，「世界地图」列出六个现有战场；点击可用关卡的「挑战」，确认奖励后出征。返回营地时显示本次结算。

冒险文件位于 `user://campaign_saves/`，与原 `user://battle_saves/` 隔离。每档保存版本、稳定 ID、队伍、公共库存、金币和已通关关卡；`.bak` 用于损坏恢复。列表会提示不可加载的档案或备份恢复情况。最近使用索引独立记录，加载旧档也会更新最近选择。

## 验证入口

- `tests/campaign_contract.gd`：纯数据与持久化契约，使用独立临时存档目录。
- `tests/campaign_ui_contract.gd`：存档、营地、关卡、详情/确认弹层、焦点与三档分辨率交互契约；逐层断言页面尺寸和滚动区，并验证首末关卡可见。
- `res://tests/campaign_battle_integration_contract.tscn`：经 MCP `dbg_launch` 运行，断言根节点 `/root/CampaignBattleIntegration` 的 `finished=true`、`passed=true`。覆盖真实战斗结算、旧战场存档隔离、重复回调、失败回退，以及 Campaign → Battle → Campaign 的实际切换；测试存档与玩家档隔离。

真实场景探针已通过 30 项检查，运行日志 error/warning 为空；结算处断点确认本次令牌有效、`result=win`、旧 `save_identity` 为空。探针作为 `tests/contract_manifest.json` 的 probe 登记，不能用 `--script` 当普通 `SceneTree` 契约启动。

数据契约 22 组全部通过（`CAMPAIGN_CONTRACT_OK`），界面契约全部通过（`campaign_ui_contract: ALL PASS`，含三档分辨率、逐层满屏布局、六关首末卡可见及链式弹窗），均 exit 0，无脚本错误；界面测试隔离自动按钮音效后退出无资源残留。两项已登记为 `campaign` 分组，可分别运行：

```sh
python3 tools/run_contracts.py --test campaign --no-warmup
python3 tools/run_contracts.py --test campaign_ui --no-warmup
```

相关旧契约 `battle_save`、`battle_result_presentation`、`ui` 回归通过。最终默认入口另经 MCP 检查存档选择屏可见、三屏节点完整且 error/warning 为空。
