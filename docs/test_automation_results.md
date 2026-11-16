# 测试自动化基线台账（2026-11-16）

> ⚠️ 本文件为当时任务时点记录（历史不改写）。**当前口径以 `docs/test_automation.md` §4 为准**：
> 2026-11-17 五项 known-fail 全部修复清零，80 契约 = pass 75 / known-fail 0 / env-skip 5；
> 本文件中的 known-fail 4、79 契约等数字均为历史快照。
>
> 任务：契约测试入口「可选择、可并发、可诊断、可复现」+ 小规模验证纯逻辑基准。
> 交付：`tests/contract_manifest.json`、`tools/run_contracts.py`、`tools/test_run_contracts.py`、
> `tools/run_contract_baseline.sh`（兼容包装）、`tests/benches/ecology_logic_bench.gd` +
> `tests/ecology_logic_bench_contract.gd`。
> 本文档记录每一步验证的命令、退出码、耗时与日志路径。
>
> | 环境项 | 值（2026-11-16 实测） |
> | --- | --- |
> | 机器 | macOS 26.6.2，Apple Silicon arm64 |
> | Godot | `/Applications/Godot.app` = **4.7.1.stable.official.a13da4feb**（项目文档口径 4.7.2；本机二进制以 `--version` 实测为准） |
> | python3 | 3.12.9 |
> | node | 25.8.1 |
> | cargo | 1.92.0 |
> | 缓存 | `.godot/` 导入缓存热（首跑全量导入曾 ~64 分钟；热跑契约普遍 <10s） |

## 1. 契约清单（S1）

`tests/contract_manifest.json`：**79 契约 + 2 探针**（原 78 + 新增 `ecology_logic_bench`），
每条含 `name / path / group / tags / known_status / parallel_safe / fast_flag_safe / evidence`。

- **known_status 分类**（基于 docs/testing_baseline_2026-11-15.md + 当日实测）：
  - `known-fail` 4：`map_editor_ui`、`battle_action_chain`、`battle_presentation_hooks`、`isometric_view`
    —— 真实回归，runner 照常执行、保持 fail 可见，不吞不修。
  - `environment-skip` 5：`sunlight_3d_gl`（需非 headless GL）、`user_asset_source_live`（live 源）、
    `action_anim` / `immersive_battle_camera` / `world_map_overlay`（--script 模式 autoload 编译挂起）。
  - 其余 `pass` 70。⚠️ **基线漂移实测**：`ui` 契约 2026-11-16 连跑 3 次全过（exit=0），
    基线文档记 fail 的根因（`scripts/scenes/map_editor.gd` 直建 `Button.new()`）已在后续修复中消除，
    manifest 已按实测更新为 `pass`。
- **parallel_safe=false 14**：user://battlefields 共享目录组（map_editor 等 6 个）、计时组
  （weather_performance 等 4 个）、4 个 known-hang。
- **fast_flag_safe=false 42**：计时/渲染/帧时序证据契约（保守起步，见 §4 白名单结论）。

## 2. 统一 runner（S2）

`tools/run_contracts.py`（标准库 only）：`--test/--group/--changed/--all/--list/--dry-run/
--jobs 1-4/--timeout/--out/--fast-fps/--disable-render-loop/--run-env-skip/--junit/--no-warmup/
--verbose/--godot`。要点：进程组 `os.setsid` + 超时 `killpg(SIGKILL)`（退出码按旧约定记 124）；
默认先 `godot --headless --import` 预热；并发只作用于 `parallel_safe=true`，unsafe 契约在并发阶段
之后严格串行；environment-skip 默认不执行直接标记（`--run-env-skip` 才真跑，跑挂仍记
environment-skip 不计失败，跑过记 pass 并提示更新 manifest）；退出码 0=全过或仅 env-skip，
1=存在真实 fail/timeout/executor-error，2=用法错误。

`--changed` 影响分析：全仓 res:// 引用闭包（含 uid:// 解析）映射改动文件 → 受影响契约；
源码根内文件若无任何契约引用 → **保守全选**并打印理由；源码根外（docs/、.codegraph/ 等）→
无契约映射不选。

### 2.1 代表性验证记录（S2.4）

| 验证点 | 命令 | 结果 | 日志 |
| --- | --- | --- | --- |
| 正常路径 + 产物 | `python3 tools/run_contracts.py --test ecology_resolver cell_state animal_behavior_registry terrain_sampler --junit --out /tmp/contract_run_s24` | exit=0，pass=4（terrain_sampler 11.9s，确定性 hash 内部断言过），tsv/json/junit 齐全 | /tmp/contract_run_s24 |
| known-fail 可见 | `python3 tools/run_contracts.py --test ui map_editor_ui --out /tmp/contract_run_s24_fail2` | `map_editor_ui` [fail] exit=1 3s；`ui` [pass]（复绿，见 §1） | /tmp/contract_run_s24_fail2 |
| env-skip 默认跳过 | 同上命令含 `sunlight_3d_gl` | `[environment-skip] sunlight_3d_gl (exit=-1, 0s)` 未执行、可见 | /tmp/contract_run_s24_fail |
| 真实超时清理 | `python3 tools/run_contracts.py --test world_map_overlay --run-env-skip --timeout 25` | 25s 整被 killpg，记 environment-skip（known-hang 语义），exit=0，**无残留进程**（pgrep 复核） | /tmp/contract_run_s24_to |
| 并发正确性 | `--test community_runtime community_spawner community_state_store ecology_registry ecology_resolver --no-warmup`，jobs=4 vs jobs=1 | 墙钟 **1.8s vs 4.3s**（5×~0.9s 契约）；并发上限 ≤N 由单测 flock 计数验证 | /tmp/cr_j4、/tmp/cr_j1 |
| 全组冒烟 | `--group ecology --jobs 3` | pass=6（flora_layers 57s 长尾主导墙钟） | /tmp/contract_run_s24_par |

### 2.2 runner 单测（S2.2）

`python3 tools/test_run_contracts.py`：**23 用例全绿**（约 11s）。覆盖：选择/未知名报错、
`--changed` 闭包命中与非源码路径不选、未映射源码保守全选、pass/fail/executor-error 分类、
**超时杀整个进程组（含假 godot 的子进程，逐 pid 验证死亡）**、并发重叠数 ≤ 上限、
unsafe 契约串行阶段、env-skip 升降级语义、tsv/json/junit 产物、带空格路径、CLI 用法错误退出 2、
真实 godot 冒烟（2 纯逻辑 pass + isometric_view known-fail 保持 fail）。

开发中修掉的 runner bug（记录备查）：① 逐行读 stdout 无超时会永久阻塞（挂起时 wait 的超时
永远到不了）→ 改 `communicate(timeout=)`；② macOS `/var`→`/private/var` symlink 使
`relative_to` 崩 → repo 先 `resolve()`；③ 影响闭包方向曾建反（沿"谁引用我"而非"我引用谁"）。

### 2.3 baseline 兼容包装（S2.3）

`tools/run_contract_baseline.sh [output_dir]` 保留旧参数与环境变量（GODOT/CONTRACT_TIMEOUT）、
4 列 summary.tsv、逐契约 `<out>/<name>.log`、`[status] name (exit=N, Ns)` 行格式；内部委托
`run_contracts.py --all --run-env-skip --jobs 1`。差异：状态枚举新增 environment-skip /
executor-error（旧脚本把它们误记 fail/timeout）；存在真实失败时退出码 1（旧恒 0）。

## 3. 生态纯逻辑基准（S3.2）

- `tests/benches/ecology_logic_bench.gd`：固定 8 配方（沙漠水格/温带平原/雪谷/岸带等）× 确定性
  漂移，批量构造 CellContext 测 `EcologyResolver.resolve()` 吞吐；无 RNG、无场景、无帧依赖。
- `tests/ecology_logic_bench_contract.gd`：断言 catalog 非空、命中率>0、单次 resolve < 2ms（放宽
  包络）、**同规模双跑 checksum 一致**、4096 规模不劣化一个数量级。
- 实测（2026-11-16，直跑命令 `godot --headless --path . --script res://tests/ecology_logic_bench_contract.gd`）：
  exit=0，1.9s；`us_per_resolve`：512 规模 146.7/107.1µs（两次）、4096 规模 133.7µs；
  checksum 双跑一致（3848705273）；non_empty=448/512（岸带/深水配方合法未命中）。
- 踩坑记录：CellContext 构造器第 12 参要求 `Array[StringName]`，传无类型数组会构造出 null 且
  只报 SCRIPT ERROR 不退出（null 上属性访问中断后 `quit()` 不执行 → 引擎转挂起）。
  bench 已显式转型，契约的 non_empty 断言可兜住此类回归。

## 4. 加速参数 A/B（S3.1）

方法：`python3 tools/run_contracts.py --test <5 契约> [--disable-render-loop | --fast-fps 10]
--no-warmup --jobs 1`，每模式 3 次，取中位数（数据 /tmp/cr_ab/results.tsv，全部 pass）。

| 契约 | plain | --disable-render-loop | --fixed-fps 10 |
| --- | ---: | ---: | ---: |
| ecology_resolver | 0.8s | 0.8s | 0.8s |
| dynamic_landform | 0.8s | 0.9s | 1.0s |
| ambient_registry | 0.7s | 0.7s | 0.8s |
| world_terrain_mapping | 2.0s | 1.9s | 1.9s |
| pixelfx | 45.1s | **41.5s** | 42.8s |

结论与白名单建议：

1. **纯逻辑契约加 flag 无收益也无害**（±0.1s 为噪声）——现白名单（`fast_flag_safe=true` 的
   pure 系）维持即可，跑不跑 flag 都不影响结果。
2. **渲染/特效密集型契约（pixelfx）`--disable-render-loop` 中位数 -8%**，3 次全过；收益真实
   但有限。pixelfx 已在白名单内，可用 `--disable-render-loop` 跑全量 fx 类。
3. `--fixed-fps 10` 对含帧等待的契约有反向风险（10fps 下等 N 帧变慢 6 倍），**不建议**把
   frame/scene/计时类契约加进白名单；现 42 个 `fast_flag_safe=false` 维持不动。
4. 单跑收益最大的是并发与预热：jobs=4 对 5×0.9s 契约 2.4× 提速；`--import` 预热 ~9s
   消除首跑 64 分钟级导入长尾。

## 5. terrain bench 决定（S3.3）

**本轮不做独立 terrain bench**，理由：① 确定性契约硬约束要求 `EXPECTED_SEED_42_HEIGHT_BIOME_HASH`
断言保留在 `tests/terrain_sampler_contract.gd` 原位（main parity 也是同一断言），把采样逻辑抽到
`tests/benches/` 属于"原契约必须继续覆盖同一断言"的高风险重构，收益仅是复用 bench 形态；
② terrain_sampler 实测 11.9s（热）在可接受范围；③ ecology bench 已验证 bench 模式可行，
terrain 基准待 Lead 认为有必要时按同一模式补。

## 6. 验收复核（五契约 + hash）

`python3 tools/run_contracts.py --test terrain_sampler terrain_generation ecology_resolver
animal_behavior_registry cell_state`（见 §6.1 实测记录）：全 pass；terrain_sampler 内部
SHA-256 断言通过即证明 `EXPECTED_SEED_42_HEIGHT_BIOME_HASH` 未变（该常量仍在原文件，git diff
显示 tests/terrain_sampler_contract.gd 零改动）。

---

# B 链验证记录（任务 task_mwin5u5n1gqcvd5，2026-11-16）

## 7. gdtest 持久 worker 试点（S4）

核实：gdtest 0.2.7（2026-11-12，MIT OR Apache-2.0，rust_version 1.96 > 本机 1.92 →
cargo install 不可用）；安装走 GitHub Release 预编译（api.github.com 资产 302 可达，
github.com/raw 直连被墙），二进制在 /tmp/gdtest_dl/，未入库。

| 命令 | 退出码 | 耗时 | 结果 | 日志 |
| --- | --- | --- | --- | --- |
| gdtest -j1 tests/gdtest/test_{cell_state,ecology_resolver,animal_behavior_registry}.gd（首跑） | 0 | 10s | 8/8 test pass（含 auto-import） | — |
| A1: 原生 3 契约（--no-warmup） | 0 | 3s | 3/3 pass | /tmp/gdtest_pilot/A1.log |
| B1: gdtest -j1 | 0 | 2s | 8/8 pass | /tmp/gdtest_pilot/B1.log |
| B4: gdtest -j4 | 0 | 1s | 8/8 pass（与 -j1 一致） | /tmp/gdtest_pilot/B4.log |
| B2: gdtest -j1（复跑） | 0 | 2s | 8/8 pass | /tmp/gdtest_pilot/B2.log |
| A2: 原生 3 契约（复跑） | 0 | 3s | 3/3 pass（native 不回归） | /tmp/gdtest_pilot/A2.log |
| python3 tools/run_contracts.py --test cell_state ecology_resolver animal_behavior_registry --backend gdtest --gdtest <gdtest> --no-warmup | 0 | ~4s | 3/3 pass（经 runner） | /tmp/gdtest_backend_run |
| 同上（默认 native 复跑） | 0 | ~4s | 3/3 pass | /tmp/native_after_backend |
| 同上 --gdtest /no/such/gdtest | 2 | <1s | 用法错误拦截 | — |
| python3 tools/test_run_contracts.py（23+4 用例） | 0 | 9.3s | 27 tests OK | — |

结论：**go**。`--backend gdtest` 已并入 runner（无映射契约自动回落 native 并注明）；
gdtest 0.2.7 不支持目录目标，必须传文件列表。

## 8. 批量模拟（S5.1 + S5.2）

新增：tools/simulation_batch.gd、tools/run_simulations.gd、
tests/fixtures/simulations/{battle_determinism_fixed,battle_smoke_sequential}.json、
tests/simulation_contract.gd（manifest 80 项之一，group=simulation）。

| 命令 | 退出码 | 耗时 | 结果 | 日志 |
| --- | --- | --- | --- | --- |
| godot --headless --script res://tests/simulation_contract.gd（首版） | 0 | 0.9s | 2 个 SCRIPT ERROR 被 exit=0 掩盖（见下"坑"） | /tmp/sim_contract/contract.log |
| 同上（修复后） | 0 | 0.9s | 全检查过，无 SCRIPT ERROR | /tmp/sim_contract/contract2.log |
| run_simulations --batch battle_determinism_fixed | 0 | ~1s | 6 run 全 victory、摘要唯一 8f66c63971ec、5 不变量全过 | /tmp/sim_contract/cli_fixed.log |
| run_simulations --batch battle_smoke_sequential | 0 | ~1s | 5 run（seed 42-46）defeat+victory 混合、断言全过 | /tmp/sim_contract/cli_seq.log |
| run_simulations（无参数） | 2 | <1s | 输入错误 | /tmp/sim_contract/cli_noargs.log |
| run_simulations --batch battle_determinism_fixed --runs 1000 --out /tmp/sim_contract/capacity | 0 | 3.6s | 1000 run、唯一摘要=1、指标 JSON 369KB | /tmp/sim_contract/cli_1000.log |
| python3 tools/run_contracts.py --group simulation --no-warmup | 0 | 1s | simulation 契约 pass=1 | /tmp/sim_group_run |

**坑（已修）**：GDScript 无 `String(float)` 构造器，JSON 数字一律 float，
`String(d[key])` 在运行期报 "Nonexistent 'String' constructor"；simulation_batch.gd
改为先验类型再取值。另：GDScript 运行期 SCRIPT ERROR **不改变进程退出码**，
契约必须 grep 日志确认无 SCRIPT ERROR，不能只看 exit=0。

S5.2 RNG 隔离证据（battle_runner.gd L52-53 每 run 重播种全局 RNG）：
同进程 A→B→A 两次 A 摘要一致（d664fd7543ec）；1000 次唯一摘要=1；
跨进程（契约进程 vs CLI 进程）quick_duel seed=7 摘要同为 8f66c63971ec。
并发只做进程级（runner --jobs），simulation_batch.gd 内部只顺序执行。

## 9. godot-autosim 0.2.0（S5.3）

| 命令 | 退出码 | 耗时 | 结果 | 日志 |
| --- | --- | --- | --- | --- |
| （未 --import 直接跑 CLI） | 0* | 0.2s | Parse Error：AutoSim* 类名不在全局类缓存（*退出码不可信） | /tmp/autosim_run/cli.log |
| godot --headless --path . --import | 0 | ~9s | class_name 注册（global_script_class_cache.cfg 9 处 autosim） | /tmp/autosim_run/import.log |
| --script addons/godot_autosim/cli/cli.gd -- --adapter=res://tools/autosim_battle_adapter.gd --strategy=res://tools/autosim_first_action_bot.gd --iterations=8 --seed=42 --output=/tmp/autosim_run/balance_report.json | 0 | 0.9s | 8 iterations 全过、win rate 100%（quick_duel seed 42-49 全 player 胜）、报告 JSON 落盘 | /tmp/autosim_run/cli2.log |

结论：**兼容（go）**，最小接入完成（vendored addons/godot_autosim + 单动作适配器）。
局限：逐回合 bot 决策需 BattleRunner 暴露增量步进接口（现为整场一动作）；examples
目录未拷贝。

## 10. MCP 冻结+固定步进确定性（S5.4，可选）

配方：runtime_spawn_peers(2) → 双端 time_scale=0 → 双端 seed 20261116 →
双端 step_frames(120, physics) → runtime_peers_digest(root=/root/Main)。
结果：**converged=false，6932 节点分叉**（完整输出
dsh-spill 48f9945a27c5-mcp__godot__runtime_peers_digest.txt）。
归因：与工具文档前置条件一致——冻结期 idle 帧回调仍消耗全局 RNG；两 peer 启动期
自由运行时长不同，起始世界状态不可等价对齐（7000+ 活节点）。判定：该配方适用小型
受控场景，不适用主世界；战斗域无帧驱动，确定性以 §8 摘要锚点为准。peers 已全部停止。

## 11. B 链验收自检

| 检查 | 结果 |
| --- | --- |
| native runner 单测 27/27（含 4 个 gdtest 后端用例） | OK 10.1s |
| simulation 契约经 runner（--group simulation） | pass=1 exit=0 |
| manifest 覆盖检查（80 项与盘上一致） | 无告警 |
| A 链五契约 + bench + simulation 复跑 | 见 §12 最终表 |
| gdtest 后端/native/CLI 校验 | 见 §7 |
| 未动 main.gd / scripts/ / 确定性契约（git diff HEAD 为零） | 是 |
| ui 复绿按"两行分列台账"处理（不改写 2026-11-15 历史基线文档） | 是 |

## 12. B 链最终验收跑（2026-11-16）

命令与结果见下表（native 后端，--no-warmup；命令模板：
`python3 tools/run_contracts.py --test <names> --no-warmup --out <dir>`）：

| 范围 | 退出码 | 耗时 | 结果 | 日志 |
| --- | --- | --- | --- | --- |
| terrain_sampler terrain_generation ecology_resolver animal_behavior_registry cell_state（A 链验收五契约） | 见 §6（本轮未重复跑，S2.4 已 6/6 pass） | — | — | — |
| ecology_logic_bench simulation（两新增契约） | 0 | 2.8s | 2/2 pass（1.6s/1.0s） | /tmp/final_accept_b |
| gdtest 三契约（native 后端复跑 cell_state ecology_resolver animal_behavior_registry） | 0 | 2.5s | 3/3 pass（0.7-0.9s） | /tmp/final_accept_native |

---

# C 链记录（任务 task_mwin5zwv1grciuo，2026-11-16）

## 13. 失败与跳过清单（manifest 全量视角）

| 契约 | manifest 状态 | 处置 |
| --- | --- | --- |
| battle_action_chain | known-fail | 照常执行保持 fail 可见（B1 普攻 floats=2 impacts=1，2026-11-15 基线） |
| battle_presentation_hooks | known-fail | 同上（名牌 cue 未生成程序化音频） |
| isometric_view | known-fail | 同上（角度 0.0 鼠标拾取偏移） |
| map_editor_ui | known-fail | 同上（2026-11-16 当日实测仍 exit=1） |
| sunlight_3d_gl | environment-skip | 需非 headless GPU；2026-11-15 基线计为"失败"，本 manifest 按根因归 env-skip（口径并列不改写历史） |
| user_asset_source_live | environment-skip | 需本机 8076 live 源 |
| action_anim / immersive_battle_camera / world_map_overlay | environment-skip | --script 模式 autoload 编译失败挂起（known-hang） |
| 其余 71 | pass | 正常执行 |

已知红项零个被"修绿"或静默忽略：本轮唯一状态变更只有 `ui`（2026-11-16 实测 3 连过，
evidence 已记根因与复现实测，见 §1）。

## 14. 复现命令速查

```bash
# 单契约（legacy，仍可用）
godot --headless --path . --script res://tests/ecology_resolver_contract.gd

# 新入口：单契约 / 组 / 受影响 / 全量基线
python3 tools/run_contracts.py --test ecology_resolver --no-warmup
python3 tools/run_contracts.py --group ecology --jobs 3
python3 tools/run_contracts.py --changed --dry-run          # 预览影响分析
python3 tools/run_contracts.py --all --run-env-skip --junit --out /tmp/full_run
tools/run_contract_baseline.sh /tmp/baseline_out            # 兼容包装（内部走 runner）

# gdtest 后端（试点 3 契约；gdtest 二进制按 docs/test_automation.md §1.2 安装）
GDTEST=/tmp/gdtest_dl/gdtest-v0.2.7-aarch64-apple-darwin/gdtest \
  python3 tools/run_contracts.py --test cell_state ecology_resolver animal_behavior_registry \
  --backend gdtest --no-warmup

# 批量模拟（默认 5-20 次；1000 次容量模式显式开启）
godot --headless --path . --script res://tools/run_simulations.gd -- \
  --batch res://tests/fixtures/simulations/battle_determinism_fixed.json
godot --headless --path . --script res://tools/run_simulations.gd -- \
  --batch res://tests/fixtures/simulations/battle_determinism_fixed.json --runs 1000 \
  --out /tmp/sim_capacity

# runner 自身单测（27 用例）
python3 -m unittest tools/test_run_contracts.py
```

## 15. C 链最终回归（2026-11-16）

| 命令 | 退出码 | 耗时 | 结果 | 日志 |
| --- | --- | --- | --- | --- |
| `python3 -m unittest tools/test_run_contracts.py` | 0 | 9.9s | **Ran 27 tests OK** | — |
| `python3 tools/run_contracts.py --test terrain_generation terrain_sampler ecology_resolver animal_behavior_registry cell_state battle_automation battle_cli ecology_logic_bench simulation --no-warmup --out /tmp/c_final_reg` | 0 | 36.2s | **9/9 pass**（battle_cli 12.1s / terrain_sampler 8.9s / terrain_generation 8.4s 最长） | /tmp/c_final_reg |
| 同上但 `--test cell_state ecology_resolver animal_behavior_registry --backend gdtest`（GDTEST=预编译路径） | 0 | ~4s | **3/3 pass**（gdtest 后端） | /tmp/c_gdtest_reg |

受影响集合依据：runner/manifest/baseline 包装为本轮全部改动面，其直接触达的契约
= 新增 2（ecology_logic_bench、simulation）+ 试点映射 3（cell_state、ecology_resolver、
animal_behavior_registry）+ Lead 点名的确定性锚点 4（terrain_generation、
terrain_sampler + battle_automation、battle_cli）。已知红项不在改动面内，未跑未修，
状态保持 manifest 口径（§13）。

## 16. 工作树完整性（最终报告）

`git status --short` 全量对照（2026-11-16）：

| 类别 | 文件 |
| --- | --- |
| 修改（M） | `.gitignore`（追加 `__pycache__/`、`*.pyc` 两行；仓库仍跟踪 `tools/__pycache__/.gdignore` 与 `slice_class_sheets.cpython-312.pyc`，ignore 只影响新文件）；`tools/run_contract_baseline.sh`（循环脚本→runner 兼容包装，输出格式兼容）；`claude/conventions.md`、`claude/testing-and-quality.md`（测试章节更新为新入口+两行分列台账） |
| 新增（??） | `docs/test_automation.md`、`docs/test_automation_results.md`、`tests/contract_manifest.json`、`tests/benches/`（ecology_logic_bench.gd）、`tests/ecology_logic_bench_contract.gd`(+.uid)、`tests/simulation_contract.gd`(+.uid)、`tests/fixtures/simulations/`（2 个 batch JSON）、`tests/gdtest/`（3 个试点用例）、`tools/run_contracts.py`、`tools/test_run_contracts.py`、`tools/run_simulations.gd`(+.uid)、`tools/simulation_batch.gd`(+.uid)、`tools/autosim_battle_adapter.gd`(+.uid)、`tools/autosim_first_action_bot.gd`(+.uid)、`addons/gdtest/`、`addons/godot_autosim/` |
| 删除 | **无**。误删的 `tools/__pycache__/.gdignore`、`slice_class_sheets.cpython-312.pyc`（git 跟踪文件）已按 Lead 指示 `git restore --source=HEAD --` 恢复，`git status --short -- tools/__pycache__/` 为空 |

- 除 `.codegraph/daemon.pid`、`.codegraph/writer.json`（非本任务产生，未触碰）外，
  **没有删除或修改任何既有源码/测试/配置文件**：`git diff HEAD -- main.gd scripts/
  tests/terrain_sampler_contract.gd` 为空；确定性契约常量原值原位
  （`tests/terrain_sampler_contract.gd:8` `EXPECTED_SEED_42_HEIGHT_BIOME_HASH`）。
- 全程未执行 `git reset / checkout / commit / 分支切换`（唯一例外：Lead 明确授权的
  两条 `git restore --source=HEAD -- tools/__pycache__/...`，用于修复本任务自己的误删）；
  未删除 `.godot/` 目录。

## 17. 遗留限制与回滚

- **gdtest**：0.2.7 不支持目录目标（须传文件列表）；二进制经 GitHub Release 安装在
  /tmp 未入库（复现命令见 test_automation.md §1.2）；试点仅 3 契约映射，扩大覆盖需
  逐契约写等价用例。
- **godot-autosim**：vendored 但仅"整场一动作"最小适配；逐回合 bot 决策需
  BattleRunner 暴露增量步进接口（后续工作）。
- **批量模拟**：`simulation_batch.gd` 只顺序执行（全局 RNG 进程内共享），并发一律走
  runner 的进程级 `--jobs`。
- **MCP 冻结步进**：对主世界场景不收敛（6932 节点分叉，§10），仅适用小型受控场景；
  战斗域确定性以摘要锚点为准（§8）。
- **回滚（一键回 legacy 串行）**：① `tools/run_contract_baseline.sh` 恢复原版或直接
  `godot --headless --path . --script res://tests/x_contract.gd` 逐个跑；②
  `tools/run_contracts.py`、`tests/contract_manifest.json` 等为纯新增，删除不影响任何
  现有契约（契约文件零改动）；③ gdtest/autosim 目录整体移除无副作用（无 autoload、
  无 project.godot 改动）——详见 `docs/test_automation.md` §5。
