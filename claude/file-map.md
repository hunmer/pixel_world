# 文件清单与目录地图

## 顶层结构

```
pixel_world/
├── project.godot          引擎配置（主场景 main.tscn、autoload、input、渲染）
├── main.gd                世界引擎根脚本（3886 行，~90 函数）★ 单文件中枢
├── main.tscn              世界根场景（仅一个挂 main.gd 的 Node2D）
├── main.gd.uid            Godot 4 资源 UID
├── icon.svg(.import)      项目图标
├── README.md / README.zh-CN.md   项目说明（双语，含大量截图）
├── HANDOFF.md             战棋融合交接文档（2026-07-28，给下个 agent）
├── ASSET_LICENSE.md       资产授权说明
├── LICENSE                MIT
├── .editorconfig          仅 charset=utf-8
├── .gitignore / .gitattributes
│
├── scripts/               ★ 全部 GDScript 源码（见下）
├── scenes/                .tscn 场景：Battle / SkillTest / Title
├── tests/                 27 个契约测试 + fixtures/
├── config/                JSON 配置（生态 + 表现层）
├── data/                  战棋 JSON 数据（professions/skills/items）
├── shaders/               .gdshader（水下动物/水深/景深等）
├── addons/breakpoint_mcp/ vendored 调试插件（独立 CLAUDE.md）
├── assets/                战棋素材：bg / markers / ui / units
├── meowa_tiles/           世界像素素材：terrain / animals / plants / trees / decorations / heroes
├── music/                 背景音乐（.mp3）
├── sound_effect/          音效（.mp3）
└── docs/screenshots/      README 截图（.png，21 张）
```

## `scripts/` 详细地图

```
scripts/
├── core/                      【战棋纯逻辑，迁移自 phaserjs，概念零渲染依赖】
│   ├── enums.gd               class_name Enums（Faction 等，StringName）
│   ├── unit.gd                UnitData 构造 + 默认成长率
│   ├── professions.gd         class_name ProfessionData（懒加载 data/professions.json）
│   ├── skills.gd              技能系统（懒加载 data/skills.json）
│   ├── items.gd               物品系统（懒加载 data/items.json）
│   ├── weapons.gd             class_name WeaponData（武器三角 + 经验公式）
│   ├── terrain.gd             class_name TerrainData（地形查表）
│   ├── cmd_args.gd            启动命令行解析（纯静态，零依赖）
│   └── world_to_chapter.gd    ★ 世界 cell → 战棋 chapter 适配层（两子系统唯一耦合）
│
├── systems/                   【战棋战斗子系统】
│   ├── grid_system.gd         网格世界模型（实例：new(w,h,map)）
│   ├── combat_system.gd       战斗结算（全静态）
│   ├── skill_system.gd        技能结算（全静态）
│   ├── item_system.gd         物品结算（全静态）
│   ├── buff_system.gd         buff/属性修正（全静态零依赖）
│   ├── turn_manager.gd        回合调度（实例）
│   ├── enemy_ai.gd            敌方 AI 决策
│   └── player_ai.gd           玩家方托管决策器
│
├── iso/                       【战棋 2D 等距渲染层，从 3D 重写】
│   ├── iso_coords.gd          2D 等距坐标变换（B1/B2 共用）
│   ├── iso_board.gd           等距棋盘控制器（仅 B2 实例化）
│   ├── unit_sprite.gd         单位视觉（加 setup_world/_apply_render_proxy，z_index=10）
│   └── profession_visual.gd   职业立绘/动画加载
│
├── battle/                    【战棋场景助手，从 battle.gd 抽出，setup()+Callable 注入】
│   ├── battle_ui.gd           屏幕空间 UI（HUD + 菜单/选择器/预览/结果横幅）
│   ├── range_overlay.gd       范围/光标层（地形铺底 + 移动/攻击菱形描边 + 金色呼吸框）
│   └── turn_director.gd       回合编排（敌方 AI + 玩家托管 + 偏好数据）
│
├── scenes/                    【场景脚本】
│   ├── battle.gd              ★ 战斗场景编排器（状态机/生命周期/输入/胜负）
│   ├── title.gd               标题屏（"进入世界" → main.tscn）
│   └── scene_args.gd          跨场景传参 autoload（SceneArgs）
│
├── world/                     【世界生成模块】
│   ├── terrain_sampler.gd     地形采样（命名噪声 + Voronoi + 高度场）
│   ├── cell_context.gd        CellContext（格子环境快照）
│   ├── cell_state.gd          CellState（渲染状态）
│   ├── deterministic_rng.gd   确定性 RNG
│   ├── noise_registry.gd      命名噪声缓存
│   ├── terrain_material_registry.gd  地形材质注册
│   ├── terrain_sampler 相关:  cell_context/cell_state
│   ├── map_snapshot_renderer.gd  地图快照渲染
│   └── biomes/                biome 模块（可插拔）
│       ├── biome_module.gd    基类
│       ├── biome_registry.gd  注册表
│       ├── temperate_biome.gd / desert_biome.gd / snow_biome.gd
│
├── ecology/                   【生态 / 群落】
│   ├── ecology_registry.gd    物种/community 注册表
│   ├── ecology_resolver.gd    habitat 匹配 + 冲突权重选择
│   ├── community_runtime.gd   群落运行时
│   ├── community_spawner.gd   群落实例化（数据驱动）
│   ├── community_state_store.gd  群落状态有界缓存
│   ├── member_composer.gd     成员组合
│   ├── ambient_registry.gd    环境生物注册表（鸟/萤火虫）
│   └── ambient_renderers/     bird_renderer.gd, firefly_renderer_adapter.gd
│
├── animals/
│   └── animal_behavior_registry.gd  动物行为栈（水域/避雪/嗜雪/群体/避人）
│
├── tests/                     【战棋自测（extends Node）】
│   ├── test_skills.gd         技能/物品自测 44/44
│   └── debug_test.gd          战斗逻辑自测 35/35
│
└── （世界表现层 + UI，散落 scripts/ 根）
    ├── weather_system.gd          天气（雨/雪/世界空间模拟）
    ├── day_night_system.gd        昼夜 + 月光
    ├── depth_of_field_system.gd   景深（tilt-shift）
    ├── world_audio_system.gd      世界音乐 + 空间音效
    ├── firefly_field.gd           萤火虫
    ├── wandering_animal.gd        游荡动物（行为 + 双轨 y-sort）
    ├── isometric_column_batch.gd  等距地块批量绘制
    ├── isometric_depth_sort.gd    等距深度排序
    ├── game_hud.gd                顶部 HUD + 设置面板（"⚙ 设置"按钮）
    ├── world_map_overlay.gd       大地图叠加
    ├── world_map_overlay_renderer? (见源)
    └── settings.gd                ★ 用户偏好 autoload（Settings，user://settings.cfg）
```

## 关键文件快速索引

| 想做什么 | 看哪里 |
| --- | --- |
| 理解世界生成 | `main.gd`（937–1290 行：`_ready`/`_regenerate`/`_sample_cell_context`/`_spawn_cell`/`_update_streaming`）+ `scripts/world/terrain_sampler.gd` |
| 理解生态规则 | `config/README.md` + `config/ecology/README.md` + `scripts/ecology/ecology_resolver.gd` |
| 加新 biome | `scripts/world/biomes/` + `config/ecology/biomes/catalog.json`（**不要改 main.gd**） |
| 加新群落/物种 | `config/ecology/species/` + `communities/` + `config/ecology/README.md` |
| 改动物行为 | `scripts/animals/animal_behavior_registry.gd` + `main.gd._compile_animal_behavior_stacks`（462） |
| 战棋逻辑 | `scripts/core/` + `scripts/systems/` + `scripts/scenes/battle.gd` |
| 进战斗入口 | `main.gd._enter_battle`（3792）/`_enter_battle_inline`（3815）/`_exit_battle`（3843） |
| 切换 B1/B2 | `scripts/settings.gd` + `Settings.battle_inline_mode` |
| 跑测试 | `tests/*_contract.gd`（headless `--script`）+ `scenes/SkillTest.tscn` |
| 调试桥 | `addons/breakpoint_mcp/`（独立 CLAUDE.md） |

## 文件类型统计（git ls-files, 共 653 文件）

| 类型 | 数量 | 说明 |
| --- | --- | --- |
| `.png` | 197 | 素材 + 截图 |
| `.import` | 180 | Godot 资源导入元数据（含 `"` 转义的 6 个） |
| `.uid` | 108 | Godot 4 资源 UID |
| `.gd` | 104 | GDScript 源码（含 `.uid` 配对） |
| `.json` | 22 | 配置 + 数据 |
| `.md` | 7 | 文档（README×2, HANDOFF, ASSET_LICENSE, config README×2, addons README） |
| `.mp3` | 8（含转义） | 音乐/音效 |
| `.tscn` | 4 | 场景（main, Battle, SkillTest, Title） |
| `.gdshader` | 4 | 着色器 |
| `.obj`/`.mtl` | 2/2 | 3D 网格（疑似参考/未用） |
| `.svg`/`.cfg`/`.godot` 等 | 各 1 | 图标 / 环境配置 / 引擎缓存 |

## 生成物 / 已忽略

- `.godot/`（引擎生成，gitignore）
- `.import` / `.uid`（Godot 自动生成，随素材走）
- `/builds/` `/exports/` `/android/`（导出产物，gitignore）
- 二进制素材（`.png`/`.mp3`）—— 本索引未分析内容，仅统计
