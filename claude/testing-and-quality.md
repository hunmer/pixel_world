# 测试与质量

## 测试机制（无第三方框架）

全仓库**无 GUT / WAT 等测试框架**，测试是 GDScript 自测脚本，两种形态：

### 1. `tests/*_contract.gd`（契约测试，`extends SceneTree`）

运行时实例化真实场景 / 模块，验证"契约"不变。约定：
- `_initialize()` → `call_deferred("_run")`。
- 失败用 `push_error(...)` / `_expect(cond, msg)` + `quit(1)`；成功以 `print("<NAME>_CONTRACT_OK")` 结尾。
- **地形 / 生成类测试用固化的 SHA-256 快照**（如 `EXPECTED_SEED_42_HASH`）采样大量格点，任何确定性回归都会让哈希变化而失败。

运行（headless，exe 路径 `D:/Godot/Godot_v4.7.2-stable_win64.exe`）：
```bash
godot --headless --path . --script res://tests/terrain_generation_contract.gd
```
> console 版 exe 的 stdout 全缓冲，管道下可能看不到输出 —— 用 `timeout` 包裹或以退出码为准。

`tests/` 共 **37 个**契约脚本（2026-07-28 为 27 个，新增 10 个），覆盖：

| 类别 | 代表脚本 |
| --- | --- |
| 地形 / 流式 | `terrain_generation_contract`（SHA-256 快照）、`terrain_sampler_contract`、`terrain_material_registry_contract`、`streaming_input_latency_contract`、`dynamic_landform_contract` |
| 群系模块 | `biome_modules_contract`、`module_extension_contract`（+ `tests/fixtures/` 火山 biome 扩展样例） |
| 生态 / 群落 | `ecology_registry_contract`、`ecology_resolver_contract`、`community_runtime_contract`、`community_spawner_contract`、`community_state_store_contract`、`flora_layers_contract` |
| 动物 | `animal_behavior_registry_contract`、`animal_group_distribution_contract`、`animal_animation_state_contract`、`aquatic_fauna_contract` |
| 环境生物 | `ambient_registry_contract`、`bird_renderer_contract` |
| Cell 状态 | `cell_state_contract`、`cell_state_integration_contract` |
| 配置 | `config_manifest_contract` |
| 表现层 / UI | `weather_performance_contract`、`depth_of_field_contract`、`audio_system_contract`、`game_hud_contract`、`world_map_overlay_contract` |
| **3D 正交渲染（2026-11-12 新增）** | `isometric_3d_contract`、`isometric_column_projection_contract`、`isometric_view_contract`、`sunlight_3d_contract`、`sunlight_3d_gl_contract` |
| **战棋 3D / 战场（2026-11-11 新增）** | `battle_3d_contract`、`battle_screen_pick_contract`、`battlefield_render_contract`、`battlefields_contract`、`map_editor_contract` |

另有探针场景 `tests/flat_rotation_probe.tscn/.gd`（平地旋转视觉验证）。

`tests/fixtures/`（18 文件）是模块扩展测试夹具：自定义 scorer、不完整的 ambient renderer、火山 biome + 自定义 manifest/world/species/communities/materials —— 用于验证"新内容走数据/模块扩展"契约。

### 2. `scripts/tests/*.gd` + `scenes/SkillTest.tscn`（战棋自测，`extends Node`）

`_ready()` 里自跑 `_ok/_pass/_fail/_print_summary` 框架（仿 `debug_test.gd`）：
- `scripts/tests/test_skills.gd` — 技能/物品/MP/冷却/buff 纯逻辑（**44/44 passed**，2026-11-11 HANDOFF 复验）。
- `scripts/tests/debug_test.gd` — 职业/地形/武器/战斗/AI/回合/经验（**35/35 passed**，历史记录）。

通过 `scenes/SkillTest.tscn` 在编辑器手动运行（headless）。

## 已知验证状态

| 项 | 状态 | 说明 |
| --- | --- | --- |
| `SkillTest.tscn` | ✅ 44/44 | 技能/物品/MP/冷却/buff（2026-11-11 复验） |
| `debug_test.gd` | ✅ 35/35 | 战斗逻辑（历史，phaserjs 期跑过） |
| battlefields / map_editor / battle_screen_pick / battlefield_render 契约 | ✅ | 2026-11-11 HANDOFF 记录通过 |
| B1 端到端 | ✅ | 按 P 不切场景，真实地形上出现战棋单位 |
| B2 模式回归 | ⚠️ 未深度验证 | 代码保留；JSON 战场固定走 B2 且 4 示例可用，但"世界 P 按 B2"路径未深度验证 |
| 战斗结束恢复链路 | ⚠️ 未深度验证 | `_exit_battle` 信号已接，相机/玩家/输入完全恢复未验证 |
| **`tests/game_hud_contract.gd`** | ❌ **HEAD 上本来就坏** | `--script` 模式无 autoload，`game_hud.gd` 引 `Settings` 编译错（git stash 验证非近期引入）；待改造为场景内测试或 mock Settings |
| 其余契约（37 个总） | ❓ 未逐一执行 | 本索引更新未跑全量；建议按下文命令跑一轮基线 |

## Lint / 类型检查

- **无独立 lint/格式化工具配置**（仓库无 `.gdformat`、`gdlint` 配置，无 CI 文件）。
- GDScript 静态类型：脚本普遍使用类型标注（`-> void`、`: int`），strict 模式下新代码必须完整标注（HANDOFF 坑）。
- 质量主要靠：① 启动期 `_validate_ecosystem_config()`（配置校验，失败 abort），② 契约测试的 SHA-256 快照，③ MCP 调试桥的 `runtime_assert_*` 自动断言（AGENTS.md 要求：改代码后加 L1 日志 / L2 断言 / L3 断点验证，不要 `print` 后肉眼判断）。

## 质量风险（来自 HANDOFF 待办与本次扫描）

- `main.gd` 单文件 **4099 行 / 174 函数**，职责高度集中 → 可维护性风险（但有清晰函数簇分区，见 `module-responsibilities.md`）。
- `game_hud_contract.gd` 在 HEAD 上已损坏（见上表）。
- `meowa_tiles/heroes/` 素材未与 `data/professions.json` 职业映射（已知待办）。
- `cell_context_to_terrain` 旧记录称只映射 `water/mountain/plain` —— 战棋地形已扩到 11 种，世界侧映射覆盖度需复核。
- `story/` 设计 bible（13 职业/27 技能/25 道具）与 `data/` 实际（8/8/8）差距大，实现时勿把目标态当运行时事实。
- 2D 旋转渲染期的一批踩坑记录在 `handoff/2026-11-11-isometric-rotation.md`，已被 3D 迁移取代，仅作历史参考（防止有人回退到 2D 方案时重踩）。

## 执行测试的建议命令

```bash
# 跑全部契约测试（Git Bash；exe 不在 PATH 时用全路径）
GODOT=D:/Godot/Godot_v4.7.2-stable_win64.exe
for t in tests/*_contract.gd; do
  timeout 120 "$GODOT" --headless --path . --script "res://$t" || echo "FAIL: $t"
done

# 单个
"$GODOT" --headless --path . --script res://tests/terrain_generation_contract.gd
```
（37 个契约的当前通过状态未逐一执行验证，建议先跑一轮确认基线。）
