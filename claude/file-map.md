# 文件清单与目录地图

> 更新：2026-11-16（三单体拆分 + 深夜优化轮：scripts/world 12→25、scripts/editor 11→26、scripts/battle 10→20（+automation 3）、scripts/iso 11→14、scripts/ecology 9→10；scripts 总 122→164 .gd；tests 80 契约 + gdtest 试点；vendored 4→6）。

## 顶层结构

```
pixel_world/  (本机 /Users/Zhuanz/Documents/pixel_world；历史路径 G:/ → E:/)
├── project.godot          引擎配置（主场景 scenes/Game.tscn、8 autoload、input、Jolt、gl_compatibility）
├── main.gd                世界引擎装配层（2026-11-16 拆分后 2283 行 / 128 函数；能力在 scripts/world/ 23 模块）★
├── main.tscn              世界根场景（Node2D "Main" + 子节点 "DebugConsoleCommands"）
├── icon.svg(.import)      项目图标
├── README.md / README.zh-CN.md   项目说明（双语，含截图）
├── AGENTS.md              agent 工作约束（MCP 按会话激活、场景路由表、runtime_assert_*）
├── DESIGN.md              ★ UI 设计规范单一事实来源（token 体系 + 六薄容器 + 禁忌 + 验收，2026-11-15 新增）
├── ASSET_LICENSE.md / LICENSE / .editorconfig / .gitignore / .gitattributes
│
├── scripts/               ★ 全部项目 GDScript（164 个 .gd，见下）
├── ui/                    ★ 共享 UI 组件库（22 个 Pixel* @tool 控件（+6 布局容器）+ ComponentTheme + README）
├── scenes/                11 个 .tscn：Battle / DialogueDemo / Game / HomeEntry / Isometric3DTest /
│                          LoadingScreen / MapEditor / PixelFxGallery / SkillTest / Title / UIComponentGallery
├── tests/                 86 个 .gd（80 契约 + 2 探针 + gdtest/ 试点 3 + benches/ 1）+ fixtures/（模块扩展夹具 + battle_scenarios/ 4 JSON + simulations/）
├── config/                JSON 配置（生态 + 表现层 + sunlight.json + startup.cfg 调试启动配置）
├── data/                  战棋 JSON：professions/skills/items + battlefields/(6) + dialogue/(demo_intro)
├── docs/                  battle_automation / test_automation / startup_config / user_assets / gameplay_gap /
│                          roadmap / testing_baseline_2026-11-15 + feature_map.json/.html（功能依赖图谱，双击 HTML 可看）+ screenshots/(22)
├── rules/                 4 篇 agent 规则文档（godot-tools-map、mcp-debugging、autoplay-hosting、skill-item-system）
├── story/                 19 篇设计 bible（目标态：13 职业/27 技能/25 道具；当前 data/ 仅 8/8/8）
├── handoff/               3 篇专题交接：isometric-rotation / game-sfx-system / immersive-battle-presentation
├── plans/                 验证计划与拆分报告（split_report_2026-11-15 等）
├── tools/                 run_contracts.py(+单测) / run_simulations.gd / simulation_batch.gd / autosim_* /
│                          battle_cli.gd + build_blocks_manifest.mjs(+test) + python 素材切片 + art/audio 生成脚本
├── shaders/               6 个仓库自有 .gdshader（+encounter_warp）
├── addons/                6 个 vendored 插件：breakpoint_mcp / panku_console / at-icons / pixelfx / gdtest / godot_autosim
├── assets/                素材：audio(bgm/sfx/ambience/voice) / bg / markers / ui / units / video / character_art_registry.json / pixelfx_export
├── meowa_tiles/           世界像素素材 165 png：terrain/animals(24)/plants(39)/trees(25)/decorations/generated(39)/heroes(24)
├── music/ sound_effect/   .mp3 ×8（music 下另有空的 rules/ story/ 占位目录）
└── .godot/                引擎生成（gitignore；改码后须删 .godot/editor）
```

> ⚠️ 根目录 `HANDOFF.md` 已删除，交接文档统一在 `handoff/`（3 篇）。`rules/image-viewing.md` 也已移除（rules/ 现存 4 篇）。

## `scripts/` 详细地图（164 .gd）

```
scripts/
├── core/                      【战棋纯逻辑，迁移自 phaserjs，零渲染依赖】14 .gd
│   ├── enums.gd               class_name Enums（Faction/Mode 等，StringName）
│   ├── unit.gd                UnitData 构造 + 默认成长率
│   ├── professions.gd         class_name ProfessionData（懒加载 data/professions.json）
│   ├── skills.gd              技能系统（懒加载 data/skills.json）
│   ├── items.gd               物品系统（懒加载 data/items.json）
│   ├── weapons.gd             class_name WeaponData（武器三角 + 经验公式）
│   ├── terrain.gd             class_name TerrainData（11 地形查表）
│   ├── cmd_args.gd            启动命令行解析（纯静态，零依赖）
│   ├── world_to_chapter.gd    ★ 世界 cell → 战棋 chapter 适配层（两子系统唯一耦合；地形映射 7/11 种）
│   ├── battlefield_loader.gd  ★ JSON 战场加载 + 唯一权威校验（victory/reinforcements 字段；res:// 与 user://battlefields/）
│   ├── battle_save_codec.gd   战旗存档编解码（chapter+state ⇄ 落盘 dict，version=1）
│   ├── battle_save_store.gd   存档原子落盘（tmp+bak 两段写 / index.json 自恢复）
│   ├── block_layout.gd        用户素材方块布局（编辑器素材画布消费）
│   └── reinforcement_spawner.gd ★ 按回合波次增援刷入（spawn_due/pending_units；演出/无头两链路共用）
│
├── systems/                   【战棋战斗子系统】12 .gd
│   ├── grid_system.gd         网格世界模型（实例：new(w,h,map)）
│   ├── combat_system.gd       战斗结算（全静态）
│   ├── skill_system.gd        技能结算（全静态）
│   ├── item_system.gd         物品结算（全静态）
│   ├── buff_system.gd         buff/属性修正（全静态零依赖）
│   ├── turn_manager.gd        回合调度（实例；victory 注入 + check_victory 胜利判定）
│   ├── enemy_ai.gd            敌方 AI 决策
│   ├── player_ai.gd           玩家方托管决策器
│   ├── ai_difficulty.gd       AI 难度分级（设置面板可调）
│   ├── ai_difficulty_scoring.gd  难度评分参数
│   ├── attack_event.gd        攻击事件结构（表现层钩子消费）
│   └── trade_system.gd        相邻友军物品传递（can_trade/adjacent_trade_targets/execute_trade）
│
├── iso/                       【等距渲染层：主世界 3D + 战棋 B1/B2】14 .gd
│   ├── iso_projection_3d.gd   ★ 3D 投影标尺（TILE_PIXELS 32 / TILE_HEIGHT 16 / LEVEL_PIXELS 10）
│   ├── isometric_camera_3d.gd ★ 正交 Camera3D（zoom 0.5–4，旋转只动相机）
│   ├── isometric_terrain_3d.gd ★ chunk 3D 柱地形（CHUNK_SIZE=2，MAX_WATER_RIPPLES=48）
│   ├── isometric_column_texture_batch.gd 柱体贴图 UV 常量+投影批次内类〔深夜优化轮〕
│   ├── isometric_column_terrain_draw.gd  普通柱/贴图/投影网格绘制〔深夜优化轮〕
│   ├── isometric_column_shoreline.gd     岸线泡沫+水波纹（确定性 RNG）〔深夜优化轮〕
│   ├── isometric_view.gd      离散视角（SUPPORTED_ANGLES=[0,90,180,270]）
│   ├── battlefield_renderer.gd ★ JSON 战场等距方块柱渲染（B2+编辑器共用；高度 h1–h5；支持用户素材贴图）
│   ├── iso_coords.gd          2D 等距坐标变换（B1/B2 共用；to_cell 用 roundi）
│   ├── iso_board.gd           等距棋盘控制器（纯相机/坐标）
│   ├── unit_sprite.gd         单位视觉（高度感知站位）
│   ├── profession_visual.gd   职业立绘/动画加载
│   ├── character_sheet.gd     角色详情面板（属性/装备/技能一览）
│   ├── battle_occluder.gd     战斗遮挡剔除（单位被地形柱挡住时的处理）
│   └── world_camera_navigation.gd  世界相机漫游导航（键盘/边缘滚屏统一）
│
├── battle/                    【战棋场景助手，setup()+Callable 注入；2026-11-16 拆分后 20 .gd + automation/】
│   ├── battle_action_resolver.gd ★ 行动结算内核（battle.gd 与 automation 无表现回放共享）
│   ├── battle_ui.gd           屏幕 UI 装配层（467 行；HUD/菜单/详情/横幅已拆出）〔深夜优化轮〕
│   ├── battle_ui_hud.gd       侧栏构建/回合状态/show_info_at/panku 日志〔深夜优化轮〕
│   ├── battle_ui_unit_menu.gd 单位行动菜单 + 技能/物品/交换/攻击 picker〔深夜优化轮〕
│   ├── battle_ui_unit_detail.gd 单位详情面板〔深夜优化轮〕
│   ├── battle_ui_banner.gd    战斗结果横幅〔深夜优化轮〕
│   ├── range_overlay.gd       范围/光标层（只显示，不参与判定）
│   ├── turn_director.gd       回合编排（敌方 AI + 玩家托管 + 偏好数据 + 沉浸演出调度）
│   ├── battle_presentation.gd 战斗表现层（结算 → 动画/特效/音效的桥）
│   ├── battle_settings_tab.gd 战斗设置页（B1/B2、难度、沉浸相机等开关）
│   ├── action_anim.gd         行动动画（移动/攻击的补间演出）
│   ├── encounter_transition.gd 遭遇战转场（encounter_warp shader）
│   ├── result_presentation.gd 胜负结算演出
│   ├── immersive_camera.gd    ★ 沉浸式战斗相机（导演式运镜；见 handoff/2026-11-14）
│   ├── battle_camera_kick.gd  行动演出镜头踢击（ActionAnim 相位驱动的附加位移）〔拆分新增〕
│   ├── battle_fx.gd           战斗演出特效（伤害数字/血条受击/飘字/抖动）+ PixelFx 预热〔拆分新增〕
│   ├── battle_result_stage.gd 结算演出视觉（欢呼/倒地/死亡淡出 + 姿态捕获恢复）〔拆分新增〕
│   ├── battle_sfx.gd          战斗音效（出手/受击 + 结算 cue + 程序化回退波形）〔拆分新增〕
│   ├── battle_save.gd         战旗持久化（完整行动边界提交；演出中退出回退快照）〔拆分新增〕
│   ├── battle_pref_panel.gd   托管偏好面板（每单位配：优先目标 + 策略）〔拆分新增〕
│   └── automation/            【声明式战场 CLI（docs/battle_automation.md）】
│       ├── battle_scenario_loader.gd  场景 JSON → scenario
│       ├── battle_runner.gd            无表现确定性对局执行器
│       └── battle_report.gd            events.jsonl / result.json / summary.txt 战报
│
├── editor/                    【战场编辑器；2026-11-16 拆分后 26 .gd】
│   ├── battlefield_doc.gd     文档模型（generate(seed)/to_json_dict/save_model/quick_validate）
│   ├── editor_canvas.gd       画布（内嵌 BattlefieldRenderer；多高度拾取；cell 信号；平移缩放）
│   ├── tile_preview.gd        地形调色板缩略图（真实柱渲染，4 列）
│   ├── asset_library_panel.gd ★ 用户素材库面板（导入/清单刷新/画布放置）
│   ├── block_selector.gd      方块选择器（素材 Tab）
│   ├── selection_range.gd     区域选择（拖拽框选 + 键盘扩展）
│   ├── region_clipboard.gd    ★ 区域剪贴板内核（五层 payload；extract/paste/move/clear_rect）
│   ├── region_preset_store.gd ★ 区域命名预设持久化（user://editor_presets/presets.json 原子写）
│   ├── editor_block_list.gd   方块画廊列表（GridContainer，三态外观）
│   ├── editor_block_picker_dialog.gd  4 列方块选择弹窗（640×480 Window）
│   ├── shortcut_hints_dialog.gd       快捷键提示浮层（复用 hint_bar 键帽）
│   ├── map_editor_assets.gd         用户素材选择与方块素材网格〔拆分新增〕
│   ├── map_editor_block_palette.gd  方块选择面板（icon gallery / 填充窗口）〔拆分新增〕
│   ├── map_editor_cell_tools.gd      画布交互路由与格子面板同步〔拆分新增〕
│   ├── map_editor_clipboard.gd       区域剪贴板与区域移动〔拆分新增〕
│   ├── map_editor_file_io.gd         保存/加载流程〔拆分新增〕
│   ├── map_editor_generate.gd        种子生成/调尺寸/工具切换〔拆分新增〕
│   ├── map_editor_history.gd         撤销/重做历史〔拆分新增〕
│   ├── map_editor_model_ops.gd       模型写操作原语〔拆分新增〕
│   ├── map_editor_overlays.gd        叠加层/预览 ghost〔拆分新增〕
│   ├── map_editor_paint_ops.gd       画笔/填充/橡皮操作〔拆分新增〕
│   ├── map_editor_panel_tabs.gd      侧栏 Tab 面板装配〔拆分新增〕
│   ├── map_editor_presets.gd         区域预设库（预设 Tab）〔拆分新增〕
│   ├── map_editor_region_select.gd   区域选择与区域填充入口〔拆分新增〕
│   ├── map_editor_replace.gd         条件替换（替换方块工具）〔拆分新增〕
│   └── map_editor_shortcuts.gd       全局快捷键与临时吸管状态机〔拆分新增〕
│
├── scenes/                    【场景脚本】12 .gd
│   ├── battle.gd              ★ 战斗场景编排器（2026-11-16 拆分后 1444 行装配层：状态机/生命周期/输入/胜负）
│   ├── title.gd               标题屏
│   ├── map_editor.gd          ★ 战场编辑器场景（2026-11-16 拆分后 1031 行装配层，能力在 scripts/editor/map_editor_* 15 模块）
│   ├── game_entry.gd          Game.tscn 入口（战场列表 / 冷启动续玩路由）
│   ├── game_session.gd        ★ autoload：战旗会话路由 + 分战场存档（user://battle_saves/）
│   ├── home_entry.gd          HomeEntry.tscn（主页占位入口）
│   ├── dialogue_demo.gd       对话系统演示（data/dialogue/demo_intro.json）
│   ├── startup_config.gd      ★ 调试启动配置（config/startup.cfg：auto_open_last_scene 等）
│   ├── ui_component_gallery.gd  UI 组件画廊（22 组件交互演示）
│   ├── pixelfx_gallery.gd     PixelFx 特效画廊
│   ├── isometric_3d_test.gd   3D 柱网格旋转验证场景
│   └── scene_args.gd          跨场景传参 autoload（SceneArgs）
│
├── assets/                    【用户素材系统（docs/user_assets.md）】3 .gd
│   ├── user_asset_service.gd  ★ 服务核心（本地导入 sha256 去重 / 网络清单拉取校验 / blob 存储）
│   ├── user_asset_catalog.gd  清单协议校验（descriptor 校验 / 宽容解析 / merge 语义）
│   └── user_asset_visual_adapter.gd  素材 → 渲染适配（pivot/scale/footprint → 战场画布）
│
├── audio/
│   └── game_sfx.gd            ★ autoload Sfx：UI/战斗/回合/胜负/脚步音效池（SceneTree.node_added 自动挂按钮声）
│
├── ui/                        【UI 基础设施】3 .gd
│   ├── ui_theme.gd            老主题（配色/StyleBox）
│   ├── ui_factory.gd          UI 工厂方法（17 个业务文件消费；新 UI 优先 ui/ Pixel* 组件）
│   └── loading_screen.gd      全局加载遮罩（autoload LoadingScreen 场景的脚本，幂等 show/hide）
│
├── world/                     【世界生成模块；2026-11-16 拆分后 23 .gd（新 11 件全部 RefCounted/静态，Callable 注入、无反向依赖）】
│   ├── terrain_sampler.gd     地形采样（命名噪声 + Voronoi + 高度场）
│   ├── cell_context.gd        CellContext（格子环境快照）
│   ├── cell_state.gd          CellState（渲染状态）
│   ├── deterministic_rng.gd   确定性 RNG
│   ├── noise_registry.gd      命名噪声缓存
│   ├── terrain_material_registry.gd  地形材质注册装配层（472 行；解析拆出）〔深夜优化轮〕
│   ├── terrain_material_parser.gd    材质定义解析/规范化（static+回调注入，809 行）〔深夜优化轮〕
│   ├── map_snapshot_renderer.gd  地图快照渲染
│   ├── biomes/                biome 模块（可插拔）：biome_module.gd / biome_registry.gd
│   │                          + temperate / desert / snow 实现
│   ├── ecology_config_validator.gd  生态配置结构校验（纯函数集）〔拆分新增〕
│   ├── terrain_texture_catalog.gd   方块贴图目录与纹理工具〔拆分新增〕
│   ├── minimap_renderer.gd          小地图（UI 挂载/着色缓存/全图重绘）〔拆分新增〕
│   ├── player_occlusion_controller.gd  玩家植被遮挡（门控/相交收集/alpha 精测）〔拆分新增〕
│   ├── presentation_stage.gd        表现层系统装配 builder（昼夜/阳光/景深/音频/萤火虫/天气）〔拆分新增〕
│   ├── ecosystem_match.gd           生态区匹配（五键规则/legacy 转换/机会值）〔拆分新增〕
│   ├── species_picker.gd            物种池确定性选择（static）〔拆分新增〕
│   ├── world_query_service.gd       与流式生成顺序无关的世界查询〔拆分新增〕
│   ├── flora_spawner.gd             植被/ambient 候选产生、冲突消解与放置〔拆分新增〕
│   ├── fauna_streamer.gd            动物群落流式生成（锚点/群体规划/成员恢复）〔拆分新增〕
│   └── animal_runtime.gd            动物个体生成/外观/逐帧行为〔拆分新增〕
│   ├── ecology_config_compiler.gd   生态/生成配置纯静态编译器（main.gd 薄委托）〔深夜优化轮〕
│
├── ecology/                   【生态 / 群落】10 .gd
│   ├── ecology_registry.gd    物种/community 注册表（984 行；legacy 已外迁）
│   ├── ecology_legacy_codec.gd legacy 包解码与校验（host 注入；迁移后整文件可删）〔深夜优化轮〕
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
├── tests/                     【战棋自测（extends Node）】2 .gd
│   ├── test_skills.gd         技能/物品自测 44/44
│   └── debug_test.gd          战斗逻辑自测 35/35
│
└── （世界表现层 + UI，散落 scripts/ 根）17 .gd
    ├── weather_system.gd          天气（雨/雪/世界空间模拟）
    ├── day_night_system.gd        昼夜 + 月光
    ├── sunlight_system.gd         ★ 3D 阳光+地形阴影（DirectionalLight3D；config/sunlight.json）
    ├── depth_of_field_system.gd   景深（tilt-shift）
    ├── world_audio_system.gd      世界音乐 + 空间音效
    ├── firefly_field.gd           萤火虫
    ├── wandering_animal.gd        游荡动物（AnimatedSprite3D + 行为栈）
    ├── isometric_column_batch.gd  等距地块批量绘制装配层（742 行；绘制通道已拆 scripts/iso/）
    ├── isometric_depth_sort.gd    等距深度排序
    ├── game_hud.gd                左侧图标 HUD + 战场面板 + 设置（⚠️ 契约测试在 HEAD 上坏）
    ├── world_map_overlay.gd       大地图叠加
    ├── side_panel.gd              侧栏面板（世界信息）
    ├── hint_bar.gd                底部操作提示条
    ├── game_cursor.gd             autoload GameCursor：全局游戏光标（纹理切换/战斗态）
    ├── debug_console_commands.gd  Panku dbg.* 命令集（help/list_battlefields/editor/enter_battle...）
    └── settings.gd                ★ 用户偏好 autoload（Settings，user://settings.cfg）
```

## `ui/` 组件库（2026-11-14 新增，详见 `ui/README.md`）

```
ui/
├── README.md                 304 行使用文档（ComponentTheme / 组件清单 / 画廊说明）
├── theme/component_theme.gd  class_name ComponentTheme：每次 create() 新建独立 Theme；语义→Type Variation
└── components/               22 个 @tool 控件（16 功能控件 + 6 薄布局容器 VBox/HBox/Grid/Margin/Center/Scroll；
                              token 走 ComponentTheme/DESIGN.md，全部复用 scripts/ui/ui_theme + ui_factory）
    ├── pixel_button.gd / pixel_check_button.gd / pixel_option_button.gd / pixel_dropdown.gd
    ├── pixel_line_edit.gd / pixel_text_area.gd / pixel_slider.gd / pixel_spin_box.gd
    ├── pixel_progress_bar.gd / pixel_tabs.gd / pixel_panel.gd(+.tscn) / pixel_popup.gd
    ├── pixel_image.gd / pixel_icon.gd
    └── pixel_audio_player.gd / pixel_video_player.gd（真实 .ogv 样例在 assets/video/ui/）
```

交互画廊 `scenes/UIComponentGallery.tscn`（F6 独立运行、ESC 退出、不依赖战斗参数）；契约 `tests/ui_components_contract.gd`。**目前只有画廊使用，现有业务 UI 尚未迁移**。

## `tools/`（2026-11-16 大扩充：测试 runner + 批量模拟）

| 文件 | 用途 |
| --- | --- |
| `run_contracts.py` | ★ 统一契约 runner（manifest 驱动 80 契约+2 探针；单测/并发/--changed 影响闭包/JUnit；`docs/test_automation.md`） |
| `test_run_contracts.py` | runner 自身单测（27 test，`python3 -m unittest`） |
| `run_simulations.gd` | 批量战斗模拟 CLI 入口（`--batch/--runs/--out`；1000 局实测 3.6s） |
| `simulation_batch.gd` | 批量模拟核心（RefCounted；CLI / autosim adapter / 契约三方共用） |
| `autosim_battle_adapter.gd` / `autosim_first_action_bot.gd` | `addons/godot_autosim` 最小接入示例（adapter+bot） |
| `battle_cli.gd` | 声明式战场 CLI 入口（`--scenario/--seed/--out`；见 `docs/battle_automation.md`） |
| `build_blocks_manifest.mjs`(+`.test.mjs`) | 用户素材清单生成/校验（node --test 7 项；`docs/user_assets.md`） |
| `slice_class_sheets.py` / `slice_ui_sheet.py` | 素材图集切片（配合 `tools/art`、`tools/audio` 的生成脚本） |

## 关键文件快速索引

| 想做什么 | 看哪里 |
| --- | --- |
| 理解世界生成 | `main.gd` 函数簇分区表（`module-responsibilities.md`）+ `scripts/world/` 23 模块（装配点 `_configure_generation_services`@594） |
| 理解生态规则 | `config/README.md` + `config/ecology/README.md` + `scripts/ecology/ecology_resolver.gd` |
| 加新 biome | `scripts/world/biomes/` + `config/ecology/biomes/catalog.json`（**不要改 main.gd**） |
| 加新群落/物种 | `config/ecology/species/` + `communities/` + `config/ecology/README.md` |
| 改动物行为 | `scripts/animals/animal_behavior_registry.gd` + `main.gd._compile_animal_behavior_stacks` |
| 战棋逻辑 | `scripts/core/` + `scripts/systems/` + `scripts/scenes/battle.gd` |
| 加 JSON 战场 | 抄 `data/battlefields/arena_1v1.json` → 改 rows/legend/units（loader 全量校验）；或编辑器生成 |
| 改编辑器 | `scripts/scenes/map_editor.gd`（1031 行装配层）+ `scripts/editor/` 26 模块 |
| 用户素材（导入/清单/回滚） | `docs/user_assets.md`（运维手册）+ `scripts/assets/` |
| 查功能↔文件归属 | `docs/feature_map.html`（知识图谱，双击打开）+ `docs/feature_map.json` |
| 查可复用组件/函数 / 结构·重复·可读性自检 | `claude/report.md`（§1–3 自检 + §4 UI 三层链 / 共享内核 / world 模块 / 编辑器组件 / autoload） |
| 用新 UI 组件 | `ui/README.md` + 画廊 `scenes/UIComponentGallery.tscn` |
| 跑无表现战斗模拟 | `docs/battle_automation.md` + `tools/battle_cli.gd` + `tests/fixtures/battle_scenarios/` |
| 3D 渲染/相机/阴影 | `scripts/iso/iso_projection_3d.gd` / `isometric_camera_3d.gd` / `isometric_terrain_3d.gd` / `sunlight_system.gd` |
| 进战斗入口 | `main.gd._enter_battle` / `_enter_battlefield` / `_enter_battle_inline` / `_exit_battle` |
| 跑测试 | `python3 tools/run_contracts.py`（默认入口）+ `tests/*_contract.gd`（headless `--script` 直跑）+ `scenes/SkillTest.tscn` |
| 调试桥 | `addons/breakpoint_mcp/`（独立 CLAUDE.md）+ `rules/mcp-debugging.md` |
| 踩坑清单 | `handoff/` 3 篇专题交接（2D 旋转史 / 音效系统 / 沉浸演出） |
| 设计规划 | `story/`（目标态 bible，勿当运行时事实） |

## 文件类型统计（git ls-files）

| 类型 | 数量 | 说明 |
| --- | --- | --- |
| 总文件 | **11560** | 含 addons vendored 与全部素材 |
| `.gd` | **~711** | scripts 164 / tests 86 / ui 23 / addons ~430（+gdtest/godot_autosim）/ tools 等 |
| `.md` | 223 | story 19 + rules 4 + claude/ + docs/ + handoff/ + addons 文档 |
| `.tscn` | 自有 16 | main + scenes/11 + ui/pixel_panel + tests 探针 + addons |
| `.png` | 566 | meowa_tiles 165 + assets + docs/screenshots 22 等 |
| `.json` | 41（不含 addons） | config 17 + data 8 + tests fixtures 等 |
| `.gdshader` | 自有 6 | day_night_overlay / encounter_warp / isometric_terrain_rotate / tilt_shift_dof / underwater_animal / weather_overlay |
| `.mp3`/`.ogg`/`.ogv` | 若干 | music / sound_effect / assets/audio / assets/video |
| `.import` / `.uid` | 引擎生成 | 随素材/脚本走，不手编 |

## 生成物 / 已忽略

- `.godot/`（引擎生成，gitignore；**改码后须删 `.godot/editor` 再重启编辑器**，否则跑旧脚本）
- `.import` / `.uid`（Godot 自动生成；`tests/zz_align_probe.gd.uid` 为孤儿 uid，对应 .gd 已删）
- `/builds/` `/exports/` `/android/`（导出产物，gitignore）
- `.codegraph/` / `.dsh/` / `.claude/` / `.libtv/`（本地工具目录）
- 二进制素材（`.png`/`.mp3`）—— 本索引未分析内容，仅统计
- `b1_debug.png` / `b1_depth_probe.png` / `b1_fixed.png` 等根目录调试截图（未入 git 也可清理）
