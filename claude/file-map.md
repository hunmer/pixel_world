# 文件清单与目录地图

## 顶层结构

```
pixel_world/  (E:/pixel_world)
├── project.godot          引擎配置（主场景 main.tscn、4 autoload、input、Jolt、gl_compatibility）
├── main.gd                世界引擎根脚本（4099 行 / 174 函数）★ 单文件中枢
├── main.tscn              世界根场景（Node2D "Main" + 子节点 "DebugConsoleCommands"）
├── icon.svg(.import)      项目图标
├── README.md / README.zh-CN.md   项目说明（双语，含截图）
├── HANDOFF.md             战棋融合交接文档（2026-11-11 更新：需求→入口索引 + 坑列表）★ 改战棋前必读
├── AGENTS.md              agent 工作约束（MCP 按会话激活、场景路由表、runtime_assert_*）
├── ASSET_LICENSE.md / LICENSE / .editorconfig / .gitignore / .gitattributes
│
├── scripts/               ★ 全部项目 GDScript（75 个 .gd，见下）
├── scenes/                5 个 .tscn：Battle / Isometric3DTest / MapEditor / SkillTest / Title
├── tests/                 37 个契约测试 + flat_rotation_probe + fixtures/(18 文件)
├── config/                JSON 配置（生态 + 表现层 + sunlight.json）
├── data/                  战棋 JSON：professions/skills/items + battlefields/(4 战场)
├── rules/                 5 篇 agent 规则文档（godot-tools-map 295 工具/49 可激活、mcp-debugging、image-viewing、autoplay-hosting、skill-item-system）
├── story/                 19 篇设计 bible（目标态：13 职业/27 技能/25 道具/15 章；当前 data/ 仅 8/8/8）
├── handoff/               2026-11-11-isometric-rotation.md（2D 旋转踩坑，已被 3D 迁移取代）
├── docs/screenshots/      README 截图（22 张）
├── shaders/               5 个仓库自有 .gdshader
├── addons/                3 个 vendored 插件：breakpoint_mcp / panku_console / at-icons
├── assets/                战棋素材：bg / markers / ui / units
├── meowa_tiles/           世界像素素材 126 png：terrain / animals(13 种) / plants / trees / decorations / heroes(待映射)
├── music/ sound_effect/   .mp3 ×8
└── .godot/                引擎生成（gitignore；改码后须删 .godot/editor）
```

## `scripts/` 详细地图（75 .gd）

```
scripts/
├── core/                      【战棋纯逻辑，迁移自 phaserjs，零渲染依赖】
│   ├── enums.gd               class_name Enums（Faction/Mode 等，StringName）
│   ├── unit.gd                UnitData 构造 + 默认成长率
│   ├── professions.gd         class_name ProfessionData（懒加载 data/professions.json）
│   ├── skills.gd              技能系统（懒加载 data/skills.json）
│   ├── items.gd               物品系统（懒加载 data/items.json）
│   ├── weapons.gd             class_name WeaponData（武器三角 + 经验公式）
│   ├── terrain.gd             class_name TerrainData（11 地形查表）
│   ├── cmd_args.gd            启动命令行解析（纯静态，零依赖）
│   ├── world_to_chapter.gd    ★ 世界 cell → 战棋 chapter 适配层（两子系统唯一耦合）
│   └── battlefield_loader.gd  ★ JSON 战场加载 + 唯一权威校验（res:// 与 user://battlefields/）
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
├── iso/                       【等距渲染层：主世界 3D + 战棋 B1/B2】
│   ├── iso_projection_3d.gd   ★ 3D 投影标尺（TILE_PIXELS 32 / TILE_HEIGHT 16 / LEVEL_PIXELS 10）
│   ├── isometric_camera_3d.gd ★ 正交 Camera3D（zoom 0.5–4，旋转只动相机）
│   ├── isometric_terrain_3d.gd ★ chunk 3D 柱地形（CHUNK_SIZE=2，MAX_WATER_RIPPLES=48）
│   ├── isometric_view.gd      离散视角（SUPPORTED_ANGLES=[0,90,180,270]）
│   ├── battlefield_renderer.gd ★ JSON 战场等距方块柱渲染（B2+编辑器共用；高度 h1–h5）
│   ├── iso_coords.gd          2D 等距坐标变换（B1/B2 共用；to_cell 用 roundi）
│   ├── iso_board.gd           等距棋盘控制器（纯相机/坐标）
│   ├── unit_sprite.gd         单位视觉（高度感知站位）
│   └── profession_visual.gd   职业立绘/动画加载
│
├── battle/                    【战棋场景助手，setup()+Callable 注入】
│   ├── battle_ui.gd           屏幕空间 UI（HUD + 菜单/选择器/预览/结果横幅）
│   ├── range_overlay.gd       范围/光标层（只显示，不参与判定）
│   └── turn_director.gd       回合编排（敌方 AI + 玩家托管 + 偏好数据）
│
├── editor/                    【战场编辑器（2026-11-11 新增）】
│   ├── battlefield_doc.gd     文档模型（generate(seed)/to_json_dict/save_model/quick_validate）
│   ├── editor_canvas.gd       画布（内嵌 BattlefieldRenderer；多高度拾取；cell 信号；平移缩放）
│   └── tile_preview.gd        地形调色板缩略图（真实柱渲染，4 列）
│
├── scenes/                    【场景脚本】
│   ├── battle.gd              ★ 战斗场景编排器（状态机/生命周期/输入/胜负）
│   ├── title.gd               标题屏（"进入世界" → main.tscn）
│   ├── map_editor.gd          ★ 战场编辑器场景（四工具；🛠 按钮 + E 键）
│   ├── isometric_3d_test.gd   3D 柱网格旋转验证场景
│   └── scene_args.gd          跨场景传参 autoload（SceneArgs）
│
├── world/                     【世界生成模块】
│   ├── terrain_sampler.gd     地形采样（命名噪声 + Voronoi + 高度场）
│   ├── cell_context.gd        CellContext（格子环境快照）
│   ├── cell_state.gd          CellState（渲染状态）
│   ├── deterministic_rng.gd   确定性 RNG
│   ├── noise_registry.gd      命名噪声缓存
│   ├── terrain_material_registry.gd  地形材质注册（set_texture_processor 两参！）
│   ├── map_snapshot_renderer.gd  地图快照渲染
│   └── biomes/                biome 模块（可插拔）：biome_module.gd / biome_registry.gd
│                              + temperate / desert / snow 等实现
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
    ├── sunlight_system.gd         ★ 3D 阳光+地形阴影（DirectionalLight3D；config/sunlight.json）
    ├── depth_of_field_system.gd   景深（tilt-shift）
    ├── world_audio_system.gd      世界音乐 + 空间音效
    ├── firefly_field.gd           萤火虫
    ├── wandering_animal.gd        游荡动物（AnimatedSprite3D + 行为栈）
    ├── isometric_column_batch.gd  等距地块批量绘制
    ├── isometric_depth_sort.gd    等距深度排序
    ├── game_hud.gd                左侧图标 HUD + 战场面板 + 设置（⚠️ 契约测试在 HEAD 上坏）
    ├── world_map_overlay.gd       大地图叠加
    ├── debug_console_commands.gd  Panku dbg.* 命令集（help/list_battlefields/editor/enter_battle...）
    └── settings.gd                ★ 用户偏好 autoload（Settings，user://settings.cfg）
```

## 关键文件快速索引

| 想做什么 | 看哪里 |
| --- | --- |
| 理解世界生成 | `main.gd` 函数簇分区表（`module-responsibilities.md`）+ `scripts/world/terrain_sampler.gd` |
| 理解生态规则 | `config/README.md` + `config/ecology/README.md` + `scripts/ecology/ecology_resolver.gd` |
| 加新 biome | `scripts/world/biomes/` + `config/ecology/biomes/catalog.json`（**不要改 main.gd**） |
| 加新群落/物种 | `config/ecology/species/` + `communities/` + `config/ecology/README.md` |
| 改动物行为 | `scripts/animals/animal_behavior_registry.gd` + `main.gd._compile_animal_behavior_stacks` |
| 战棋逻辑 | `scripts/core/` + `scripts/systems/` + `scripts/scenes/battle.gd` |
| 加 JSON 战场 | 抄 `data/battlefields/arena_1v1.json` → 改 rows/legend/units（loader 全量校验）；或编辑器生成 |
| 改编辑器 | `scripts/scenes/map_editor.gd` + `scripts/editor/`；UI 扩展参考 `D:/phaserjs/godot/scripts/scenes/map_editor.gd` |
| 3D 渲染/相机/阴影 | `scripts/iso/iso_projection_3d.gd` / `isometric_camera_3d.gd` / `isometric_terrain_3d.gd` / `sunlight_system.gd` |
| 进战斗入口 | `main.gd._enter_battle` / `_enter_battlefield` / `_enter_battle_inline` / `_exit_battle` |
| 跑测试 | `tests/*_contract.gd`（headless `--script`）+ `scenes/SkillTest.tscn` |
| 调试桥 | `addons/breakpoint_mcp/`（独立 CLAUDE.md）+ `rules/mcp-debugging.md` |
| 踩坑清单 | `HANDOFF.md`（坑列表）+ `handoff/2026-11-11-isometric-rotation.md`（2D 旋转史） |
| 设计规划 | `story/`（目标态 bible，勿当运行时事实） |

## 文件类型统计（git ls-files）

| 类型 | 数量 | 说明 |
| --- | --- | --- |
| `.gd` | **229** | scripts 75 / tests 45 / addons 108 / 根 1 |
| `.png` | 198 | meowa_tiles 126 + assets + docs/screenshots 22 等 |
| `.md` | 96 | story 19 + rules 5 + claude/ + addons 文档等 |
| `.tscn` | 51 | 仓库自有 6（main + scenes/5）+ addons |
| `.json` | 29 | config 12 + data 3 + battlefields 4 + tests fixtures 等 |
| `.gdshader` | 7 | 仓库自有 5：day_night_overlay / isometric_terrain_rotate / tilt_shift_dof / underwater_animal / weather_overlay |
| `.mp3` | 8 | music / sound_effect |
| `.import` / `.uid` | 引擎生成 | 随素材/脚本走，不手编 |

## 生成物 / 已忽略

- `.godot/`（引擎生成，gitignore；**改码后须删 `.godot/editor` 再重启编辑器**，否则跑旧脚本）
- `.import` / `.uid`（Godot 自动生成）
- `/builds/` `/exports/` `/android/`（导出产物，gitignore）
- 二进制素材（`.png`/`.mp3`）—— 本索引未分析内容，仅统计
