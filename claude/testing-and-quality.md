# 测试与质量

## 测试机制（无第三方框架）

全仓库**无 GUT / WAT 等测试框架**，测试是 GDScript 自测脚本，两种形态：

### 1. `tests/*_contract.gd`（契约测试，`extends SceneTree`）

运行时实例化真实场景 / 模块，验证"契约"不变。约定：
- `_initialize()` → `call_deferred("_run")`。
- 失败用 `push_error(...)` + `quit(1)`；成功正常退出。
- **地形 / 生成类测试用固化的 SHA-256 快照**（如 `EXPECTED_SEED_42_HASH`）采样大量格点，任何确定性回归都会让哈希变化而失败。

运行（headless）：
```bash
godot --headless --path . --script res://tests/terrain_generation_contract.gd
```

`tests/` 共 **27 个** 契约脚本，覆盖：

| 类别 | 代表脚本 |
| --- | --- |
| 地形 / 流式 | `terrain_generation_contract`（含 SHA-256 快照）、`terrain_sampler_contract`、`terrain_material_registry_contract`、`streaming_input_latency_contract`、`dynamic_landform_contract` |
| 群系模块 | `biome_modules_contract`、`module_extension_contract`（+ `tests/fixtures/` 火山 biome 扩展样例） |
| 生态 / 群落 | `ecology_registry_contract`、`ecology_resolver_contract`、`community_runtime_contract`、`community_spawner_contract`、`community_state_store_contract`、`flora_layers_contract` |
| 动物 | `animal_behavior_registry_contract`、`animal_group_distribution_contract`、`animal_animation_state_contract`、`aquatic_fauna_contract` |
| 环境生物 | `ambient_registry_contract`、`bird_renderer_contract` |
| Cell 状态 | `cell_state_contract`、`cell_state_integration_contract` |
| 配置 | `config_manifest_contract` |
| 表现层 / UI | `weather_performance_contract`、`depth_of_field_contract`、`audio_system_contract`、`game_hud_contract`、`world_map_overlay_contract` |

`tests/fixtures/`（11 文件）是模块扩展测试夹具：自定义 scorer、不完整的 ambient renderer、火山 biome + 自定义 manifest/world/species/communities/materials —— 用于验证"新内容走数据/模块扩展"契约。

### 2. `scripts/tests/*.gd` + `scenes/SkillTest.tscn`（战棋自测，`extends Node`）

`_ready()` 里自跑 `_ok/_pass/_fail/_print_summary` 框架（仿 `debug_test.gd`）：
- `scripts/tests/test_skills.gd` — 技能/物品/MP/冷却/buff 纯逻辑（**44/44 passed**）。
- `scripts/tests/debug_test.gd` — 职业/地形/武器/战斗/AI/回合/经验（**35/35 passed**，HANDOFF 记录在 phaserjs 跑过）。

通过 `scenes/SkillTest.tscn` 在编辑器手动运行（headless）。

## 已知验证状态（HANDOFF, 2026-07-28）

| 项 | 状态 | 说明 |
| --- | --- | --- |
| Godot 编辑器扫描 | ✅ 零 error | 清 `.godot/editor` 缓存后重新编译 |
| `SkillTest.tscn` | ✅ 44/44 | 技能/物品/MP/冷却/buff |
| `debug_test.gd` | ✅ 35/35 | 战斗逻辑（phaserjs 跑过） |
| B1 端到端 | ✅ | 按 P 不切场景，真实地形上出现战棋单位 |
| B2 模式回归 | ⚠️ 未深度验证 | 代码保留，`Settings.battle_inline_mode=false` 应切 Battle.tscn |
| 战斗结束恢复链路 | ⚠️ 未深度验证 | `_exit_battle` 信号已接，相机/玩家/输入完全恢复未验证 |

> 注：27 个 `tests/*_contract.gd` 的当前通过状态本索引**未逐一执行验证**（需 Godot 运行环境）。上述"已知通过"仅来自 HANDOFF 手动记录的 3 项。

## Lint / 类型检查

- **无独立 lint/格式化工具配置**（仓库无 `.gdformat`、`gdlint` 配置，无 CI 文件）。
- GDScript 静态类型：脚本普遍使用类型标注（`-> void`、`: int`、`Array[float]`），但非强制。
- 质量主要靠：① 启动期 `_validate_ecosystem_config()`（配置校验，失败 abort），② 契约测试的 SHA-256 快照。

## 质量风险（来自 HANDOFF 待办）

- `main.gd` 单文件 **3886 行 / ~90 函数**，职责高度集中 → 可维护性风险（但有清晰函数簇分区，见 `module-responsibilities.md`）。
- B2 模式与战斗恢复链路**未深度验证**（见上表）。
- Node2D 无 offset → 高地地形可能遮挡战棋单位（已知架构妥协）。
- `meowa_tiles/heroes/` 是 animals 副本，未与 professions.json 职业映射（已知待办）。
- `cell_context_to_terrain` 只映射 `water/mountain/plain`，缺 `forest/fort/village/wall`（已知待办）。

## 执行测试的建议命令

```bash
# 跑全部契约测试（PowerShell/Git Bash 循环）
for t in tests/*_contract.gd; do
  godot --headless --path . --script "res://$t" || echo "FAIL: $t"
done

# 单个
godot --headless --path . --script res://tests/terrain_generation_contract.gd
```
（需本机装 Godot 4.7；本索引生成环境未执行。）
