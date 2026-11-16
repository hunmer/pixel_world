# 测试自动化指南：统一 runner、gdtest 持久 worker 与批量模拟（2026-11-16）

> 结果台账（每条命令/退出码/耗时/日志路径）见 `docs/test_automation_results.md`；
> 本文是设计与使用指南。§3-§5 为统一契约 runner（A 链交付），§1 gdtest 试点与
> §2 批量模拟为 B 链交付。legacy 单契约命令继续可用（§3.1 对照表）。

## 3. 统一契约 runner（tools/run_contracts.py）

### 3.1 新旧命令对照

| 目的 | 旧（legacy，仍然可用） | 新（默认入口） |
| --- | --- | --- |
| 跑单个契约 | `godot --headless --path . --script res://tests/x_contract.gd` | `python3 tools/run_contracts.py --test x` |
| 全量基线 | `tools/run_contract_baseline.sh <out>` | `tools/run_contract_baseline.sh <out>`（内部已改为调 runner，`--all --run-env-skip --jobs 1`，输出格式兼容） |
| 按组/标签 | 无 | `--group ecology` / `--group pure` |
| 只跑受影响 | 人工判断 | `--changed`（无参=自动取 git 变更；见 §3.5） |
| 预览不执行 | 无 | `--dry-run` |
| 并发 | 无（串行） | `--jobs 1-4`（仅 parallel_safe 并发，见 §3.4） |
| 机器可读报告 | 自行解析 tsv | `summary.tsv`（旧 4 列）/ `summary.json` / `--junit` |

legacy 命令保留原因：单契约调试时它仍是最短路径；`--script` 模式行为与 runner 的
native 后端完全一致（runner 就是包装该命令）。

### 3.2 全参数

```
python3 tools/run_contracts.py [--test NAME ...] [--group GROUP|TAG ...] [--changed [FILE ...]]
                                [--all] [--list [子串]] [--dry-run]
                                [--jobs N(1-4)] [--timeout 秒] [--out 目录]
                                [--fast-fps N] [--disable-render-loop] [--run-env-skip]
                                [--junit] [--no-warmup] [--verbose]
                                [--backend native|gdtest] [--gdtest 路径]
                                [--godot 路径] [--repo 目录]
```

- 选择类：`--test`（契约名，`--list` 查询）、`--group`（组名或标签）、`--changed`
  （文件路径列表；**无参数时自动取 `git diff HEAD` + 未跟踪文件**）、`--all`。
  四者必须恰好给一个，否则退出码 2。
- `--list [子串]`：列 manifest 全部契约（名称/组/known_status/parallel_safe），不执行。
- `--timeout`：单契约秒数，默认 `CONTRACT_TIMEOUT` 环境变量或 900。
- `--out`：日志与汇总目录（默认 `/tmp/contract_run_<时间戳>`），每契约一份 `<name>.log`。
- `--fast-fps N` / `--disable-render-loop`：**只作用于 manifest `fast_flag_safe=true`
  的白名单契约**（其余契约忽略并注明），见 §3.6。
- `--run-env-skip`：实际执行 manifest 标记 environment-skip 的项（默认不执行直接标记）。
- `--backend gdtest`：带 `gdtest` 映射的契约改走 gdtest 持久 worker；无映射自动回落
  native 并在 reason 注明；`--gdtest` 指定可执行（默认 `GDTEST` 环境变量或 PATH）。
- `--no-warmup`：跳过跑前 `godot --headless --import` 预热（~9s；冷仓必跑，热仓可省）。

### 3.3 五种状态与退出码

| 状态 | 判定 |
| --- | --- |
| `pass` | 进程退出码 0（对 environment-skip 项：`--run-env-skip` 下跑过也记 pass 并提示更新 manifest） |
| `fail` | 进程退出码非 0（含已知红项——保持 fail 可见，不静默） |
| `timeout` | 超过 `--timeout`，进程组被 SIGKILL 整组杀掉，exit_code 记 124 |
| `environment-skip` | manifest `known_status=environment-skip` 且未加 `--run-env-skip`（不执行，exit_code 记 -1）；或 `--run-env-skip` 下跑挂/超时 |
| `executor-error` | runner 自身无法启动/执行命令（如 godot 路径不存在、OSError） |

退出码：**0** = 全部 pass 或仅 environment-skip；**1** = 存在 fail / timeout /
executor-error；**2** = 用法错误（无选择、jobs 越界、未知名/组、backend=gdtest 但
找不到 gdtest 可执行）。

### 3.4 并发规则

- `--jobs 1-4`，默认 1。执行分两阶段：阶段一并发跑 `parallel_safe=true` 的契约，
  阶段二**串行**跑 `parallel_safe=false` 的契约（首行打印串行阶段提示）。
- `parallel_safe=false` 的判定依据（manifest evidence 字段）：共享 `user://battlefields`
  等用户目录的契约（map_editor 系、game_session、battlefields 等）、计时敏感契约
  （weather_performance、streaming_input_latency 等）、4 个已知 hang 项。
- 每个契约一个独立 godot 进程 + 独立进程组（`os.setsid`），超时 `killpg` 整组杀，
  实测无残留进程；并发安全实测见 results §2.1。

### 3.5 只跑受影响测试（--changed 影响分析）

- `--changed` 无参数时自动取 `git diff HEAD --name-only` + `git ls-files --others`
  （即工作树全部变更）。
- 影响分析：runner 构建全仓 `res://`/`uid://` 引用图（含 macOS `/var`→`/private/var`
  symlink 归一），对每个契约求"它能到达的文件集合"（依赖闭包）；改动文件落在闭包内
  → 该契约受影响。
- 保守回退：改动落在源码根（scripts/、tests/、ui/、scenes/、config/、data/、addons/、
  tools/、main.gd、project.godot）但映射不到任何契约 → **全选**并打印理由（宁可多跑）；
  改动在源码根之外（docs/、.codegraph/ 等）→ 不选任何契约并说明。
- 习惯用法：改完代码 `python3 tools/run_contracts.py --changed --no-warmup`，预览先加
  `--dry-run`。

### 3.6 fast flag 白名单

- manifest `fast_flag_safe=true`（38 项，纯逻辑系）才接受 `--fixed-fps` /
  `--disable-render-loop`；其余 42 项为 false：计时/渲染/帧时序依赖的契约加 flag 会
  改变被测行为（A/B 实测 `--fixed-fps 10` 对帧等待契约有 6 倍减速风险，见 results §4）。
- A/B 结论：纯逻辑契约加 flag 无收益也无害；渲染特效类（pixelfx）`--disable-render-loop`
  中位数 -8%。白名单维持现状即可。

### 3.7 报告字段解读

- `summary.tsv`（旧 4 列，baseline 兼容）：`name / exit_code / seconds / status`
  （未执行的 skip 记 -1，timeout 记 124）。
- `summary.json`：每契约含 `command`（实际 argv）、`reason`（skip/回落/加速说明）、
  `log`（日志文件路径）、`status`、`exit_code`、`seconds`；头部 meta 含 godot 路径、
  backend、超时、并发等运行参数。
- `junit.xml`（`--junit`）：testsuites/testcase 结构，failure/skipped 按状态映射，
  供 CI 消费。
- 终端行格式：`[status] name (exit=N, Ns)`。

## 4. 已知红项与已知 hang 的处置

- **known-fail（4，真实回归，跑出来保持 fail 可见）**：battle_action_chain、
  battle_presentation_hooks、isometric_view、map_editor_ui。
  runner 不修绿不掩盖；修复后应更新 manifest 的 `known_status` 并在 evidence 记录依据
  （ui 契约 2026-11-16 复绿即此流程，见 results §1）。
- **environment-skip（5）**：sunlight_3d_gl（需非 headless GPU）、user_asset_source_live
  （需本机 8076 live 源）、action_anim / immersive_battle_camera / world_map_overlay
  （--script 模式下 autoload 编译失败挂起，known-hang）。默认不执行、直接标记；
  `--run-env-skip` 下跑挂仍记 environment-skip，跑过记 pass（环境恢复信号）。
- manifest 是唯一事实源：`tests/contract_manifest.json`（80 契约 = known-fail 4 +
  environment-skip 5 + pass 71；每条含
  name/path/group/tags/known_status/parallel_safe/fast_flag_safe/evidence，可选 gdtest
  映射）；盘上多出未收录的 `tests/*_contract.gd` 时 runner 会告警。
- 注：2026-11-15 基线文档把 sunlight_3d_gl 计为"失败"（6 红之一）；本 manifest 按根因
  （headless 环境缺 GPU）归入 environment-skip；历史文档不改写，两处口径并列。

## 5. 回滚方式（一键回到 legacy 串行）

1. runner 是纯新增包装层：`git checkout -- tools/run_contract_baseline.sh` 恢复原
   35 行串行脚本（它不依赖 run_contracts.py），或直接继续用
   `godot --headless --path . --script res://tests/x_contract.gd` 逐个跑。
2. 删除（或忽略）`tools/run_contracts.py`、`tools/test_run_contracts.py`、
   `tests/contract_manifest.json` 不影响任何现有契约——契约文件本身零改动
   （`git diff HEAD -- tests/terrain_sampler_contract.gd` 为空）。
3. gdtest/autosim 是可选后端：`--backend native`（默认）完全不触碰它们；
   `addons/gdtest/`、`addons/godot_autosim/` 目录整体移除亦无副作用（无 autoload、
   无 project.godot 改动）。

## 1. gdtest 试点（S4）

### 1.1 版本与许可证（核实于 crates.io API + GitHub Releases API，2026-11-16）

| 项 | 值 | 来源 |
| --- | --- | --- |
| 包 | `gdtest`（crates.io，Rust CLI + GDScript harness） | https://crates.io/api/v1/crates/gdtest |
| 版本 | **0.2.7**（2026-11-12 发布，9 个版本中的最新） | crates.io versions |
| 许可证 | **MIT OR Apache-2.0**（双许可，任选） | crates.io license 字段 |
| 仓库 | https://github.com/q-rault/gdtest | crates.io repository |
| 下载量 | 154 总 / 121 近 90 天（小众早期项目） | crates.io |
| Rust 要求 | **rustc ≥ 1.96**（本机 1.92.0，`cargo install` 会拒装） | crates.io rust_version |

### 1.2 安装方式（可复现）

- **首选（本机实际采用）**：GitHub Release 预编译二进制
  `gdtest-v0.2.7-aarch64-apple-darwin.tar.gz`（1.86MB）。
  本机 `raw.githubusercontent.com`/`github.com` 直连被墙，但 `api.github.com` 及其资产
  302（`objects.githubusercontent.com`）可达：
  `curl -L -H "Accept: application/octet-stream" https://api.github.com/repos/q-rault/gdtest/releases/assets/739857787`
  （资产 id 从 `/releases/latest` 的 JSON 取）。解压得 `gdtest` 二进制 + `addons/` harness。
- **备选**：`cargo install gdtest`——需要先升级 Rust ≥ 1.96（本机未升级，故未走此路）。
- 版本核对：`gdtest --version` → `gdtest 0.2.7`。

### 1.3 项目接入与冲突评估

- `gdtest init --no-editor`（在项目根执行）：写入 `addons/gdtest/`（`gd_test.gd` 即
  `class_name GdTest`、`gdt.gd`、`gdtest_worker.gd`、gdunit4 兼容层、scene_runner）。
- **不碰 `project.godot`**（`--no-editor` 跳过编辑器插件，不注册 plugin/autoload）。
- 与现有 4 个 vendored addon（breakpoint_mcp / panku_console / at-icons / pixelfx）
  **零冲突**：目录名不同、无 autoload、无全局类名碰撞（GdTest/Gdt 为新增全局类名）。
- gdtest worker 是常驻 Godot 进程（持久 worker），会加载项目 autoload（Panku 打印等，
  无害；BreakpointRuntimeBridge 各 worker 抢绑 9081，输一条 error 后继续，无害）。
- 测试文件放 `tests/gdtest/test_*.gd`（`extends GdTest`，`func test_*`）。
  **目录目标不被支持**（`gdtest tests/gdtest` 报 "no test functions found"），必须传
  显式文件列表或逐文件目标——这是 0.2.7 的一个使用限制。

### 1.4 试点结论：**通过（go）**

等价最小用例（断言镜像原生契约核心路径）：
`tests/gdtest/test_cell_state.gd`（3 test）、`test_ecology_resolver.gd`（2 test）、
`test_animal_behavior_registry.gd`（3 test），共 8 test。
验证：-j1 与 -j4 结果一致（8/8 pass）；A→B→A 三段（native 3/3 → gdtest 8/8 →
native 3/3）稳定，native 不回归。runner 已加 `--backend {native,gdtest}`（默认
native，旧命令不变；gdtest 模式下无 `gdtest` 映射的契约自动回落 native 并注明）。

### 1.5 后续注意

- gdtest 0.2.7 尚不支持目录目标（传文件列表）；per-test 默认超时 5s（runner 侧已
  映射为契约秒级超时 ×1000 传入）。
- 二进制未入库（仅 /tmp），CI 或他人复现按 §1.2 命令下载；manifest 中 3 个契约
  （cell_state / ecology_resolver / animal_behavior_registry）带 `gdtest` 字段指向
  等价用例，是后续扩大试点的锚点。

## 2. 批量模拟入口（S5）

### 2.1 交付物

| 文件 | 职责 |
| --- | --- |
| `tools/simulation_batch.gd` | 批量模拟核心（RefCounted）：batch JSON 解析校验、顺序执行 N 次、逐次 JSON 指标、不变量评估；不写盘不打印 |
| `tools/run_simulations.gd` | CLI 包装（SceneTree --script）：`--batch/--runs/--out/--help`；退出码 0=不变量全过 1=不变量失败 2=输入错误 4=运行/输出失败 |
| `tests/fixtures/simulations/battle_determinism_fixed.json` | fixed 批（quick_duel seed=7 × 6 次，5 条不变量） |
| `tests/fixtures/simulations/battle_smoke_sequential.json` | sequential 批（deterministic_replay seed 42..46 × 5 次） |
| `tests/simulation_contract.gd` | 契约：fixtures schema、非法拒绝、指标形态、不变量、A→B→A 同进程 RNG 隔离证据；已入 manifest（group `simulation`，80 项之一） |

batch schema：`{version:1, id, mode:"battle", scenario:<路径>, runs:5-20, seed:{strategy:fixed|sequential, base}, invariants:[...]}`；
不变量位：`deterministic_events` / `stop_reason_in{allowed}` / `steps_bound` / `assertions_pass` / `exit_code_zero`。
默认次数必须在 5-20（batch 文件越界即拒），大容量（如 1000）只能经 CLI `--runs` 显式指定。

### 2.2 战斗侧 RNG 隔离结论（S5.2）

`BattleRunner._run` 每次执行开头 `seed(scenario.seed)` 重播种全局 RNG（battle_runner.gd L52-53），
因此**同进程顺序多次 run 天然隔离**；实测证据（见 results 台账 §8）：
- 同进程 A→B→A：两次 A 的事件 SHA-256 摘要逐字节一致；
- 容量模式 1000 次：唯一摘要=1（quick_duel seed=7 全部一致）；
- 跨进程：契约进程与 CLI 进程对同一场景/seed 算出相同摘要 `8f66c63971ec`。
并发同理只能进程级隔离（全局 RNG 是进程内共享流）——`simulation_batch.gd` 只顺序执行，
并发由 `tools/run_contracts.py --jobs`（每契约一个 godot 进程）承担。

### 2.3 godot-autosim 0.2.0 核实与最小接入（S5.3）

- 来源：Godot Asset Library #5002（applesnort，MIT，2026-04-07），声明 **Godot 4.6+**。
- 核实：源码 665 行（core+cli），API 面为 `AutoSimGameAdapter`/`AutoSimBotStrategy`/`AutoSimConfig`/`AutoSimRunner`/`AutoSimBalanceReport`，无 4.7 不兼容 API；与现有全局类名零冲突。
- 接入：vendored 到 `addons/godot_autosim/`（core+cli+LICENSE，examples 不拷贝）；
  `tools/autosim_battle_adapter.gd`（单动作适配器：一场战斗=一次 auto_play，顺序 seed 42+）+ `tools/autosim_first_action_bot.gd`。
- 实测（Godot 4.7.1 headless CLI）：8 iterations / seed=42 → exit=0，报告 JSON 落盘，win rate 100%（quick_duel seed 42-49 全 player 胜，与固定 seed=7 结果一致方向）。
- **坑**：新 class_name 需先 `godot --headless --import` 注册进 `.godot/global_script_class_cache.cfg`，否则 `--script` 模式 Parse Error（runner 的 warmup 已覆盖该步骤）。
- 结论：**兼容（go）**。当前适配器是"整场一动作"最小模型；逐回合 bot 决策需要 BattleRunner 暴露增量步进接口，属后续工作。

### 2.4 MCP 冻结+固定步进确定性（S5.4，可选）

尝试了 purpose-built 的 headless 双 peer 收敛配方（runtime_spawn_peers → 双端 time_scale=0 冻结
→ 双端 seed 20261116 → 各步进 120 physics 帧 → runtime_peers_digest）：
**converged=false，6932 个节点分叉**。与工具文档记录的前置条件坑一致——冻结期间
idle 帧回调仍消耗全局 RNG、且两个 peer 启动期自由运行时长不同导致起始世界状态不同
（对 7000+ 节点的活世界无法用 set_property 等价对齐）。结论：该配方适用于小型受控
测试场景，不适用于本项目主世界场景；战斗域无帧驱动（BattleRunner 为同步纯逻辑），
确定性以 §2.2 的摘要锚点为准。已记入 results 台账，不阻塞交付。
