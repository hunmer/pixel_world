# 开发约定

> 更新：2026-11-19（契约 110 项与 macOS 基线 105/0/5；装备双口径与单一权威约定；物品/装备图标目录；沉浸舞台开关；移动测试场景）。上一轮：主入口 Campaign.tscn、冒险模式磁盘安全、建筑素材与图标 ID、UI 组件 27。本文件收集对 Agent 与人类贡献者最实用的命令、规范与禁忌。高优先级条目同时摘要在根 `CLAUDE.md`；agent 工作约束另见根 `AGENTS.md`。

## 运行与启动

```bash
# 打开并运行主场景（要求 Godot 4.6+，本项目用 4.7.2）
godot --path .
# 本机（macOS，不在 PATH）：
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/Zhuanz/Documents/pixel_world
# Windows 历史路径：D:/Godot/Godot_v4.7.2-stable_win64.exe --path E:/pixel_world

# headless 跑某个契约测试（extends SceneTree 类型，运行后自动退出；legacy 单契约命令，仍可用）
godot --headless --path . --script res://tests/terrain_generation_contract.gd

# 统一契约 runner（默认入口；--test/--group/--changed/--jobs/--dry-run 等，
# 五种状态 pass/fail/timeout/environment-skip/executor-error，详见 docs/test_automation.md §3）
python3 tools/run_contracts.py --test terrain_generation --no-warmup
python3 tools/run_contracts.py --changed --dry-run      # 只跑受影响（git 变更 → 影响闭包）

# 从命令行带参运行场景（CmdArgs 解析 --key / --key=value / --no-key）
godot -d --path . res://main.tscn --seed=42

# 无头跑一场战斗（自动化 CLI，退出码 0–4）
godot --headless --path . --script res://tools/battle_cli.gd -- \
  --scenario res://tests/fixtures/battle_scenarios/quick_duel.json --out user://tmp/battle_out

# 显式进某个战场 / 重置战旗档案（Game.tscn 会话路由消费）
godot --path . -- --battlefield=plains_skirmish --reset-battle
```

- **主场景**：`res://scenes/Campaign.tscn`（**冒险模式**：存档选择 → 营地 → 关卡）。旧入口 `res://scenes/Game.tscn` 保留为**开发用途**（战旗会话路由：自动续玩最近战旗）；世界场景 `res://main.tscn` 由 Game 列表进入，或被 `config/startup.cfg`（`auto_open_last_scene`）直跳。`docs/campaign_loop.md` 是冒险模式权威文档。
- **F5 直跳最近场景**：`config/startup.cfg` 记录 `last_scene`（`SkillTest` / `UIComponentGallery` 默认排除；**当前 = Campaign.tscn**（2026-11-19 实测；该值随最近运行场景漂移。移动测试台键位/隔离见 `docs/character_movement_test.md`））；`--battlefield` / `--reset-battle` 优先。手册 `docs/startup_config.md`。
- **console 版 exe 的 stdout 是全缓冲的**（Windows 历史坑）：管道下无输出 ≠ 没输出；脚本化验证用 `timeout` 包裹或看退出码。

## 编辑器脚本缓存坑（重要兼容性提醒）

来自历史 HANDOFF（已删，坑仍真实存在），调试时极易踩：

> 运行态验证先确认加载了新代码；若出现编辑器仍使用旧脚本的问题，再清理项目 `.godot/editor` 并重启编辑器。`dbg_restart` 只是重启运行实例，不能作为已加载新脚本的证据。纯 headless / 文档改动不要求清缓存或重启编辑器。

## 测试

- **契约本体无第三方框架依赖，入口已统一**。默认入口是 `tools/run_contracts.py`
  （`tests/contract_manifest.json` 驱动 **110 项** = 105 契约默认跑 + 5 environment-skip 声明；
  `--test/--group/--changed/--all/--jobs 1-4/--dry-run/--junit` 等，
  状态 `pass/fail/timeout/environment-skip/executor-error`，手册见 `docs/test_automation.md` §3）；
  legacy 单契约命令 `godot --headless --path . --script res://tests/x_contract.gd` 仍保留。
  测试形态：
  1. `tests/*_contract.gd`（**105 个默认跑**）：`extends SceneTree`，在 `_initialize` → `call_deferred("_run")` 中跑断言，失败用 `push_error` + `quit(1)`。**地形生成测试用固化的 SHA-256 快照检测回归**（改了确定性会挂）。
  2. `scripts/tests/*.gd`：`extends Node`，`_ready` 里自跑 `_ok/_pass/_fail/_print_summary`（仿 `debug_test.gd` 框架）。
  3. 探针（`flat_rotation_probe` / `mesh_draw_probe` 等，manifest 收录但不默认跑）。
  4. Node `--test`（素材清单生成器 7 项 `tools/build_blocks_manifest.test.mjs` + 职业切片工具 6 项 `tools/slice_profession_sheets.test.py`）。
  5. UI 组件库 headless 契约 `tests/ui_contract.gd` + `ui_components_contract.gd`（1400+ checks；`ui_contract` 还静态扫描业务脚本禁直建控件）。
  6. gdtest 持久 worker 试点（`tests/gdtest/` 3 文件 8 test，`--backend gdtest` 可选后端）与批量模拟（`tools/run_simulations.gd`）。
- 已知状态（台账，历史不改写，全表见 `testing-and-quality.md`）：**2026-11-19 macOS 全量基线 pass 105 / fail 0 / env-skip 5 / timeout 0**（HEAD `e3df43b`，`.tmp/init_baseline_2026-11-19/`，7 个新契约全过）；2026-11-18 pass 98/0/5（`e7ed380`）；更早状态见台账表。**已知缺录**：盘上 119 个 `*_contract.gd` 中 8 个未进 manifest（清单见 `faq.md` Q34）。
- **只跑改动相关测试，不盲目跑全量**（AGENTS.md）：先 `python3 tools/run_contracts.py --changed --dry-run` 预览；映射不到回退全选时检查原因，改用明确的 `--test` / `--group` 缩小范围。首跑 headless 含资源导入，耗时偏长属正常（runner 默认先 `--import` 预热）。
- **验证优先级（代码优先）**：能由单元 / 契约 / headless / CLI / 自动模拟测试覆盖时，先跑相关代码测试；其次通过函数或 API 驱动流程并自动断言；只有真实输入、焦点、命中区域或视觉表现无法由前两者覆盖时，才进行必要的游戏内交互验证。运行态诊断才走 Godot MCP；截图是可选且需用户明确要求或同意的视觉手段。测试范围限于改动相关项，勿盲目全量运行。

## 代码风格

- `.editorconfig`：仅规定 `charset = utf-8`（root）。全仓库实际统一用 **tab 缩进**（GDScript 惯例）—— 贡献者请保持 tab。
- GDScript 文件普遍带顶部 `## file.gd — 一句话职责` 文档注释（中文为主），并标注对应 TS 源（战棋部分）。**新文件请延续此风格**。
- 命名：文件名全小写 `snake_case.gd`；类用 `class_name PascalCase`；常量 `UPPER_SNAKE`；私有 `_leading_underscore`。
- 资源目录与 tile 文件统一英文小写 `snake_case`；稳定 species ID 尽量与目录名一致。
- **GDScript strict 显式类型**：新代码完整类型标注（HANDOFF 坑：漏标注在严格模式下直接编译错）。

## 配置 / 内容规范（最关键的"禁止事项"）

摘自 `config/README.md` 与 `config/ecology/README.md`：

- **不要往 `main.gd` 里加分支**：新的 biome ID、noise ID、surface ID、minimap color、weather tag 都应走 biome 模块 / 配置 / community，而不是在 main.gd 开 if。新算法进 biome 模块，可复用空间布局进 community。
- **新内容走新版模块化配置**：`config/ecology/manifest.json` + `species/` + `communities/` + `biomes/`。**禁止给新内容加 `metadata.legacy_placement_seed` 或写进 `legacy_bundles.json`**（那是兼容旧布局专用）。
- **确定性契约**：ID、`stream_key`、legacy `placement_seed` 是"存档/世界契约"。**文件路径、翻译后的显示名绝不能当随机种子**。重排 manifest 顺序或改稳定 ID 需要 world version 迁移。
- 新模块用唯一命名空间的 `stream_key`（如 `volcanic/fumaroles/member`），现有流保留旧数字 salt。
- **`story/` 是目标态设计 bible**（13 职业/27 技能/25 道具）；运行时事实是 `data/` 的 8 职业/8 技能/8 物品 + campaign 6 关。实现 story 内容 = 改 `data/*.json`，勿混用两套数字。

## 冒险模式约定（2026-11-18 新增，权威文档 `docs/campaign_loop.md`）

- **磁盘永远是安全态**：出征 = `prepare_battle` 先落盘"出征前快照 + attempt 标记"再进战斗；重载即恢复出征前。`settle_battle(token)` 一个令牌只结算一次（幂等）。
- **购买先落盘后内存**（原子性）；限购周期 = `completed_levels.size()`，勿另造计数器。
- **掉落用独立 RNG**（种子 = 战场 id + 出征令牌），不触战斗全局随机流；掉落表只在 `data/campaign.json` 的 `loot_table`。
- **campaign 存档在 `user://campaign_saves/`**，与旧 `user://battle_saves/` 完全隔离；campaign 出征的 `save_identity` 留空（不写旧档、不续玩旧战旗）。
- 关卡/商店数据只从 `data/campaign.json` + `data/shop.json` 读（`campaign_config.gd` / `shop_catalog.gd`），勿在 session 里写死。
- **装备（2026-11-19）**：目录只从 `data/equipment.json` 读（`core/equipment.gd` EquipmentDataScript **单一权威**）；`equip/unequip` 先落盘后内存（`CampaignSession.equip_item@512/unequip_item@540`）；**双口径勿混**：战斗 buff 加成 = base+stat_bonus（buff_system），HP/MP 容量 = base+装备不含 buff（capacity_hp/mp，campaign_roster 消费）；实际武器解析走 `WeaponData.unit_weapon`（装备槽优先，空装回退 `unit.weapon`）。

## 建筑与图标约定（2026-11-18 新增）

- **建筑素材四方向契约**（`docs/building_assets.md`）：4:1 横排精灵图、`direction_mode=four_directions`、帧选择 `posmod(camera_quadrant-rotation,4)`、footprint 1..8；占用/重叠校验只走 `BuildingLayout`（勿在 loader/编辑器各写一份）；sheet SHA-256 固化在文档，改图要同步。
- **图标稳定 ID 契约**：`skill_icons.gd` 的 iconId `'01'..'53'` 与文件绑定**永不重排**；未知 ID 回退 `DEFAULT_ICON_ID` + push_warning（不返回 null）；`status_icons.gd` 按 buff 属性推导，勿另建映射表。**物品 `item_icons.gd`（'01'..'08'→`assets/ui/items/`）与装备 `equipment_icons.gd`（'01'..'11'→`assets/ui/equipment/`）沿用同一模式**（2026-11-19）：稳定 ID + 缓存 + DEFAULT 兜底，勿重排、勿按文件名猜路径。

## 战棋约定（B1 / B2 / JSON 战场 / 编辑器 / 会话与存档）

- 由 `Settings.battle_inline_mode`（autoload `Settings`，持久化到 `user://settings.cfg`）切换：`true=就地(B1)` / `false=独立场景(B2)`。默认 true。**JSON 战场（O 键）固定走 B2**。
- 改动 `main.gd` 时遵守"**新增不修改，分支注入**"：B1 逻辑一律 `if _battle_active:` 前置短路，false 时零影响；**不要动 B2 路径代码**。
- **会话与存档**：战旗身份 `bf:res|user/<id>` / `world:<seed>/<x>/<y>` 由 `GameSession` 分配；完整行动边界 `commit()` 落盘，**不要在演出中途写档**。新版本存档拒绝恢复且不覆盖（版本策略见 `data-model.md`）。
- **结算与表现分离**：`battle_action_resolver.gd` 是 battle.gd 与自动化共享的结算内核；改战斗规则只改它 + systems，勿在演出/UI 层复写结算逻辑。演出可开关可快进，关演出必须不影响结算正确性。**沉浸舞台（2026-11-19）同理**：`ImmersiveStage`（`Settings.battle_immersive_presentation` 开关）是纯表现增强，演出走 `await _immersive_stage.present()`，结算仍在 resolver；关舞台零影响，勿在舞台层写任何结算/判定。
- 战场坐标 `(0,0)` = 世界 `world_origin + (bx,by)`；`GridSystem` 完全不感知世界坐标，由 `UnitSprite` 渲染时加 origin 转换。
- **JSON 战场**：schema 与校验规则见 `public-interfaces.md`；`rows` 是**顶层字段**；`BattlefieldLoader` 是唯一权威校验点（编辑器 `quick_validate` 只是轻校验）。用户战场放 `user://battlefields/`（与 `res://data/battlefields/` 同名时 res 优先）。
- **编辑器**：SpinBox 竞态用 `_syncing_boxes` 模式防；素材库面板消费 `UserAssetService`，勿绕过服务直读 blob。区域操作（复制/粘贴/移动）一律走 `EditorRegionClipboard` 五层 payload，勿自拼 Dictionary 丢层（tile_overrides/block_z/props/units 都要跟）；命名预设只经 `EditorRegionPresetStore` 落盘（原子写）。
- **胜利条件 / 增援**：只通过战场 JSON 的 `victory` / `reinforcements` 字段声明（schema 见 `public-interfaces.md`），`BattlefieldLoader` 静态严校验；勿在 battle.gd 里写死特定战场的胜负特判。增援刷入只调 `ReinforcementSpawner`，勿在演出层自刷。
- **UI 组件库 / 设计 token**：新 UI 一律用 `ui/` 的 Pixel* 组件（**27 个**，含 6 布局容器；冒险模式 campaign 七屏已是全量消费者）+ `ComponentTheme`，间距/圆角/字号取值**只从 DESIGN.md token 常量取**——禁裸数字样式值、自建 StyleBox、绝对定位、横向滚动（正误例与三档分辨率验收见根 `DESIGN.md`）。`tests/ui_contract.gd` 会静态扫描业务脚本里的 `Button.new()/CheckButton.new()/OptionButton.new()` 直建控件并置 FAIL；旧业务 UI（battle_ui/HUD）迁移按 roadmap 渐进，不阻塞功能开发。

## 视角 / 3D 渲染约定

- **只支持 4 个正交视角**（0/90/180/270，`isometric_view.gd SUPPORTED_ANGLES`）：素材逐角度验收仅四视角，其余角度有拼缝。**勿放开连续角度**。
- 旋转是**纯相机行为**（`IsometricCamera3D`），不重建地形；`R` 复位视角、`Ctrl+R` 才重新生成世界（勿混淆）。
- 2D 旋转渲染方案的踩坑存档在 `handoff/2026-11-11-isometric-rotation.md`，**已被 3D 迁移取代** —— 不要按它改代码，仅供回退时参考。

## 常见 API 坑（历史 HANDOFF / handoff/ 摘录）

- `Dictionary.merge` 默认**不覆盖**已有键。
- `TerrainMaterialRegistry.set_texture_processor(raw_texture, texture_path)` **两参必传**，漏第二参整批贴图 null 崩。
- `IsoCoords.to_cell` 用 `roundi`（不是 floor/int()）。
- Godot 4.7 **无** `DirAccess.remove_recursive`，删目录自写递归。
- 切场景前先 `set_input_as_handled()`，防输入穿透到新场景。
- B1 下 `battle.gd.board == null`：相机归 `main.gd` 管；hover 可越界但点击必须 `in_bounds`。
- `RangeOverlay` 只负责显示，不参与任何判定。
- **不清理他人未提交的改动**（工作树纪律）。

## 调试（MCP 桥 / Panku 控制台）

- **MCP 工具按会话激活**（AGENTS.md）：`mcp_connector_session_tools` preview-activate → activate `confirmed:true`（仅在用户明确指定激活这些精确工具后设置 `confirmed:true`，遵循当前工具 schema 与上层权限规则；已有对应授权不重复询问；`connectionKey: json-godot`，ttl 1–30 分钟，下一轮推理生效，不跨会话继承）。全集 295，其中 49 个可激活。工具地图见 `rules/godot-tools-map.md`；**不要用 `search` 找工具名**，查该文或 `tool-names.md`。
- 仅在需要 MCP 时按需自检用 `find_symbol` + `runtime_get_monitors`；**不要用 `editor_ping`**（不在 `runtime,dap,knowledge` 三组内，激活也拿不到，`tool not found` 会误判成「没装」）。9080 不通 = 编辑器没开或插件未启用（由用户确认）。
- 启动调试：`dbg_launch({scene: "res://main.tscn"})`（**必须传 scene**，省略只会进默认主场景）。仅需运行态时使用，场景路由表见 AGENTS.md。
- 编辑器桥 `127.0.0.1:9080`（`BREAKPOINT_BRIDGE_PORT` 覆盖）；运行时桥 `9081`（**单实例**，已有游戏在跑再启动会绑定失败）。
- 游戏内 `~` 呼出 **Panku REPL**（autoload `Panku`）：`dbg.*` 命令集见 `scripts/debug_console_commands.gd`；新命令 = 对象公共方法 + `_HELP_方法名` 常量 + `Panku.gd_exprenv.register_env` 注册。

## 安全与边界（本索引工具的自约束）

- 这些文档只读 / 写文档与索引，不改源代码。
- 默认忽略 `.godot/`、二进制大文件（`.png`/`.mp3`/`.import`）。
- 不主动执行 git 提交、分支、reset、checkout。
