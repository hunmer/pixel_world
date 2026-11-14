# macOS 全量契约测试基线 — 2026-11-15

> 执行：`tools/run_contract_baseline.sh`（单测试超时 900s；Godot `/Applications/Godot.app/Contents/MacOS/Godot`，headless `--script` 模式）。
> HEAD：`3a08327`（feat(assets): configurable asset source url with graceful degradation）。前置四卡（game_hud 修复 `e8fda38`、单位交换 `2a501c7`、胜利条件 `2ec8acb`、素材源 `3a08327`）均已在 HEAD，基线按该 HEAD 执行。
> 前置卡产物已反映在本基线：`game_hud` 通过、新增 `battle_trade` / `victory_conditions` / `editor_selection` 三个契约。

## 总表

| 结果 | 数量 |
| --- | --- |
| 通过 | **62** |
| 失败 | **6** |
| 超时（900s） | **4** |
| 合计 | **72** |

> 任务卡描述写"69 个契约"，实际 `tests/*_contract.gd` 为 **72 个**（前三张卡各新增 1 个）；`claude/testing-and-quality.md` 的 69 口径待后续索引更新同步。另 2 个 `*_probe.gd` 非契约，未跑。

### 失败清单（6，报错首行）

| 测试 | 首行报错 | 备注 |
| --- | --- | --- |
| `battle_action_chain` | `ERROR: B1 普攻 impact/飘字数量不一致，可能重复或漏播: floats=2 impacts=1` | B1/B2 两条同错 |
| `battle_presentation_hooks` | `ERROR: 名牌 cue 未生成程序化音频` | 共 3 条：名牌 cue 未生成/未播放、结果 cue 未进固定波形缓存 |
| `isometric_view` | `ERROR: 角度 0.0 的鼠标拾取偏移: (0, 0) != (1, 1)` | 多角度范围/鼠标拾取偏移断言失败 |
| `map_editor_ui` | `ERROR: 10 选择模式菜单存在且默认隐藏` | 选择模式/异高度虚线框/素材填充历史等断言失败 |
| `sunlight_3d_gl` | `ERROR: SUNLIGHT_GL_CONTRACT 需要非 headless 的 gl_compatibility 运行` | 环境限制：headless 下必然失败，非回归 |
| `ui` | `ERROR: res://scripts/scenes/map_editor.gd 不应再包含 Button.new(` | 契约禁止 map_editor.gd 直建 Button/OptionButton |

### 超时清单（4）

| 测试 | 日志关键信息 | 判断 |
| --- | --- | --- |
| `action_anim` | `SCRIPT ERROR: Compile Error: Identifier not found: Sfx`（依赖脚本编译失败，脚本未退出） | headless `--script` 模式不加载 autoload（`Sfx`），契约脚本未处理编译失败即挂起；与 game_hud 旧病同型 |
| `immersive_battle_camera` | `SCRIPT ERROR: Compile Error: Identifier not found: Settings`，`Failed to load script ... Compilation failed` | 同上（`Settings` autoload 依赖） |
| `world_map_overlay` | `SCRIPT ERROR: Compile Error: Identifier not found: Sfx` | 同上 |
| `user_asset_source_live` | `WARNING: [UserAsset] 清单拉取失败（源 http://127.0.0.1:8076/blocks.json）` → `ERROR: Index p_idx = 0 is out of bounds (items.size() = 0)` | 依赖本机回环素材源（8076 未启），失败路径里索引越界导致挂起；环境依赖 + 代码缺陷 |

> 超时的 3 个（action_anim / immersive_battle_camera / world_map_overlay）本质是 **autoload 依赖导致契约脚本无法编译**（`--script` 模式不加载 autoload），挂起直到 900s 被杀；归入"失败（阻塞）"更准确，但本表按退出码如实记为 timeout。

## 分类计数（对齐 claude/testing-and-quality.md 分类；✗=失败 ⏱=超时）

| 类别 | 通过/总数 | 明细 |
| --- | --- | --- |
| 地形 / 流式 | 5/5 | 全过（terrain_generation SHA-256 快照通过） |
| 群系模块 | 2/2 | 全过 |
| 生态 / 群落 | 6/6 | 全过 |
| 动物 | 4/4 | 全过 |
| 环境生物 | 2/2 | 全过 |
| Cell 状态 | 2/2 | 全过 |
| 配置 | 2/2 | 全过 |
| 表现层 / 世界 UI | 6/7 | ⏱ world_map_overlay；**game_hud 已修复并通过** |
| 世界 3D 渲染 | 3/5 | ✗ isometric_view、✗ sunlight_3d_gl（环境限制，headless 必败） |
| 世界相机/导航 | 1/1 | 过 |
| 战棋 3D / 战场 / 编辑器 | 8/8 | 含新增 editor_selection；map_editor_ui 归 UI 见下 |
| 战棋玩法逻辑 | 8/9 | ✗ battle_action_chain；含新增 battle_trade、victory_conditions（均过） |
| 战棋表现 / 沉浸演出 | 4/6 | ✗ battle_presentation_hooks、⏱ immersive_battle_camera |
| 战棋持久化 / 会话 | 2/2 | 全过 |
| 战棋自动化 CLI | 2/2 | 全过 |
| 战棋动画 | 0/1 | ⏱ action_anim（Sfx 编译失败挂起） |
| 对话系统 | 1/1 | 过 |
| 用户素材 | 4/5 | ⏱ user_asset_source_live（本机 8076 源未启动 + 越界挂起） |
| UI 组件库 | 1/2 | ✗ ui（map_editor.gd 直建 Button/OptionButton 违约）；map_editor_ui 的失败属编辑器 UI 断言 |
| 音效 | 1/1 | 过 |
| 特效库 | 1/1 | pixelfx 过 |

（map_editor_ui 在旧分类表属"战棋 3D / 战场 / 编辑器"，此处其失败已在 UI 行说明；两处口径以旧表为准时：编辑器 7/8、UI 组件库 2/3。）

## 整体结论

- **62/72（86%）通过**。确定性核心（地形 SHA-256、生态、Cell 状态、战棋结算/存档/自动化 CLI）在 macOS headless 下全部健康；`game_hud` 旧坏项已被前置卡修复。
- 真实回归/缺陷 5 项：battle_action_chain、battle_presentation_hooks、isometric_view、map_editor_ui、ui（+ user_asset_source_live 的越界缺陷）。
- 环境限制 2 类：sunlight_3d_gl 需非 headless GL；user_asset_source_live 依赖本机 8076 素材源。
- 系统性问题：**3 个契约脚本隐式依赖 autoload（Sfx/Settings）**，在 `--script` 模式编译失败后不退出而挂满 900s——建议按 game_hud 的修法（e8fda38）改造或给契约加显式 preload/退出保护。
- 首跑含资源导入，总耗时约 64 分钟；后续复跑会明显更快（单测普遍 0–10s，flora_layers/pixelfx ~40s）。
