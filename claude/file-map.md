# 文件清单与目录地图

> 更新：2026-11-18（第四轮增量：scripts +campaign 6/建筑 4/战斗扩展 5/图标 2/编辑器 2/skill_list、ui 组件 22→27、scenes 11→13、tests 86→115、data +campaign.json+shop.json+battlefields 6→8、docs +campaign_loop+building_assets）。

## 顶层结构

```
pixel_world/  (本机 /Users/Zhuanz/Documents/pixel_world；历史路径 G:/ → E:/)
├── project.godot          引擎配置（主场景 scenes/Campaign.tscn〔2026-11-18 改〕、9 autoload、input、Jolt、gl_compatibility）
├── main.gd                世界引擎装配层（2280 行；能力在 scripts/world/ 20 模块）★
├── main.tscn              世界根场景（Node2D "Main" + 子节点 "DebugConsoleCommands"）
├── icon.svg(.import)      项目图标
├── README.md / README.zh-CN.md   项目说明（双语，含截图）
├── AGENTS.md              agent 工作约束（MCP 按会话激活、场景路由表、runtime_assert_*）
├── DESIGN.md              ★ UI 设计规范单一事实来源（token 体系 + 六薄容器 + 禁忌 + 验收）
├── ASSET_LICENSE.md / LICENSE / .editorconfig / .gitignore / .gitattributes
│
├── scripts/               ★ 全部项目 GDScript（~191 .gd，见下）
├── ui/                    ★ 共享 UI 组件库（27 个 Pixel* @tool 控件 + ComponentTheme + README）
├── scenes/                13 个 .tscn：Battle / Campaign★ / DialogueDemo / Game / HomeEntry /
│                          Isometric3DTest / LoadingScreen / MapEditor / PixelFxGallery / SkillList /
│                          SkillTest / Title / UIComponentGallery
├── tests/                 115 .gd（103 项 manifest 契约 + gdtest 试点 3 + benches）+ 5 .tscn（探针/集成）
│                          + fixtures/（模块扩展夹具 + battle_scenarios/ JSON + simulations/）
├── config/                JSON 配置（生态 + 表现层 + sunlight.json + startup.cfg 调试启动配置）
├── data/                  战棋 JSON：professions/skills/items + campaign.json★ + shop.json★
│                          + battlefields/(8) + dialogue/(demo_intro)
├── docs/                  campaign_loop★ / building_assets★ / battle_automation / test_automation /
│                          startup_config / user_assets / gameplay_gap / roadmap / testing_baseline
│                          + feature_map.json/.html（功能依赖图谱）+ screenshots/
├── rules/                 4 篇 agent 规则文档（godot-tools-map、mcp-debugging、autoplay-hosting、skill-item-system）
├── story/                 19 篇设计 bible（目标态：13 职业/27 技能/25 道具；当前 data/ 仅 8/8/8 + campaign 6 关）
├── handoff/               3 篇专题交接：isometric-rotation / game-sfx-system / immersive-battle-presentation
├── plans/                 验证计划与拆分报告（split_report_2026-11-15 等）
├── tools/                 run_contracts.py(+单测) / run_simulations.gd / autosim_* / battle_cli.gd /
│                          build_blocks_manifest.mjs(+test) / prepare_building_demo.gd★ /
│                          prepare_house_demo.gd★ + python 素材切片 + art/audio 生成脚本
├── shaders/               6 个仓库自有 .gdshader（+encounter_warp）
├── addons/                6 个 vendored 插件：breakpoint_mcp / panku_console / at-icons / pixelfx / gdtest / godot_autosim
├── assets/                素材：audio(bgm/sfx/ambience/voice) / bg / markers / ui / units / video /
│                          buildings/{medieval_watchtower,spacious_house}/recipe.json★ /
│                          character_art_registry.json / pixelfx_export /（ui/tmp/ 切片中转，可清）
├── meowa_tiles/           世界像素素材：terrain/animals(24)/plants(39)/trees(25)/decorations/
│                          generated(增量 icon 产物)/heroes(24)
├── music/ sound_effect/   .mp3 ×8
├── .tmp/                  跨机调试工作目录（16+，含 recovered 恢复现场；不入 feature_map）
└── .godot/                引擎生成（gitignore；改码后须删 .godot/editor）
```

## `scripts/` 详细地图

```
scripts/
├── core/                      【战棋纯逻辑，零渲染依赖】18 .gd
│   ├── enums.gd               class_name Enums（Faction/Mode 等，StringName）
│   ├── unit.gd                UnitData 构造 + 默认成长率
│   ├── professions.gd         class_name ProfessionData：8 职业 + 九键成长 growths_for()
│   │                          （hp,mp,str,mag,skl,spd,luk,def,res；缺键回退 _GROWTH_FALLBACK；
│   │                          power→str/mag、agility→spd 映射）
│   ├── skills.gd              技能系统（懒加载 data/skills.json；图标走 skill_icons）
│   ├── items.gd               物品系统（懒加载 data/items.json）
│   ├── weapons.gd             class_name WeaponData（武器三角 + 经验公式）
│   ├── terrain.gd             class_name TerrainData（11 地形查表）
│   ├── cmd_args.gd            启动命令行解析（纯静态，零依赖）
│   ├── world_to_chapter.gd    ★ 世界 cell → 战棋 chapter 适配层（两子系统唯一耦合；7/11 地形）
│   ├── battlefield_loader.gd  ★ JSON 战场加载 + 唯一权威校验（victory/reinforcements/buildings）
│   ├── battle_save_codec.gd   战旗存档编解码（chapter+state ⇄ 落盘 dict）
│   ├── battle_save_store.gd   存档原子落盘（tmp+bak 两段写 / index.json 自恢复）
│   ├── block_layout.gd        用户素材方块布局
│   ├── reinforcement_spawner.gd 按回合波次增援刷入（演出/无头两链路共用）
│   ├── skill_icons.gd         ★ 技能图标稳定 ID（'01'..'53'→纹理；未知回退+push_warning）
│   ├── status_icons.gd        状态图标（buff 属性→图标 ID 推导）
│   ├── building_layout.gd     ★ class_name BuildingLayout：建筑占用格派生（奇旋转换 w/h）
│   │                          + 重叠校验（编辑器保存与 loader 共用唯一实现，194 行）
│   └── building_interior.gd   室内战场布局（建筑内格子/出生点，93 行）
│
├── systems/                   【战棋战斗子系统】14 .gd
│   ├── grid_system.gd         网格世界模型（含建筑占用查询）
│   ├── combat_system.gd       战斗结算（全静态）
│   ├── skill_system.gd / item_system.gd / buff_system.gd
│   ├── turn_manager.gd        回合调度（victory 注入 + check_victory）
│   ├── enemy_ai.gd / player_ai.gd / ai_difficulty.gd / ai_difficulty_scoring.gd
│   ├── attack_event.gd        攻击事件结构（表现层钩子消费）
│   ├── trade_system.gd        相邻友军物品传递
│   ├── facing_rules.gd        ★ 背击判定（受击者朝向·指向攻击者 点积<0；
│   │                          Vector2i.ZERO=无朝向永不判背击，兼容旧档）
│   └── pincer_rules.gd        ★ 夹击追击（对侧相邻格同阵营友军→追击半伤；仅正交攻击线）
│
├── iso/                       【等距渲染层：主世界 3D + 战棋 B1/B2】17 .gd
│   ├── iso_projection_3d.gd   ★ 3D 投影标尺（TILE_PIXELS 32 / TILE_HEIGHT 16 / LEVEL_PIXELS 10）
│   ├── isometric_camera_3d.gd ★ 正交 Camera3D（zoom 0.5–4，旋转只动相机）
│   ├── isometric_terrain_3d.gd ★ chunk 3D 柱地形
│   ├── isometric_column_texture_batch/terrain_draw/shoreline.gd  柱体三绘制通道
│   ├── isometric_view.gd      离散视角（SUPPORTED_ANGLES=[0,90,180,270]；camera_quadrant）
│   ├── battlefield_renderer.gd ★ JSON 战场等距方块柱渲染（1058 行；B2+编辑器共用；
│   │                          建筑四方向帧 posmod(camera_quadrant-rotation,4)）
│   ├── iso_coords.gd / iso_board.gd / unit_sprite.gd / profession_visual.gd
│   ├── character_sheet.gd     角色详情面板
│   ├── battle_occluder.gd     战斗遮挡剔除
│   ├── unit_status_badges.gd  ★ 单位状态徽章（UnitSprite3D 子模块；buff→图标）
│   ├── building_interior_view.gd    ★ 建筑室内视图（97 行）
│   ├── building_occlusion_controller.gd 建筑遮挡控制（89 行）
│   └── world_camera_navigation.gd  世界相机漫游导航
│
├── battle/                    【战棋场景助手，setup()+Callable 注入】26 .gd + automation/
│   ├── battle_action_resolver.gd ★ 行动结算内核（battle.gd/automation/契约测试三方共享；
│   │                          背击/夹击/击杀掉落判定在内）
│   ├── battle_ui.gd           屏幕 UI 装配层（HUD/菜单/详情/横幅/预览/状态徽章已拆出）
│   ├── battle_ui_hud.gd / battle_ui_unit_menu.gd / battle_ui_unit_detail.gd
│   ├── battle_ui_banner.gd / battle_ui_preview.gd★ / battle_ui_status_widgets.gd★
│   ├── range_overlay.gd       范围/光标层（只显示不判定）
│   ├── turn_director.gd       回合编排（AI+托管+沉浸演出调度）
│   ├── battle_presentation.gd 结算→动画/特效/音效的桥
│   ├── battle_settings_tab.gd / battle_pref_panel.gd
│   ├── action_anim.gd / encounter_transition.gd / result_presentation.gd
│   ├── immersive_camera.gd    沉浸式战斗相机
│   ├── battle_camera_kick.gd / battle_fx.gd / battle_result_stage.gd / battle_sfx.gd / battle_save.gd
│   ├── battle_threat_data.gd  ★ class_name BattleThreatData（只读威胁预测，AI/预览消费）
│   ├── battle_action_history.gd ★ class_name BattleActionHistory（整场行动快照/跨回合回退）
│   ├── level_up_presentation.gd ★ 战斗内升级演出（纯表现；sound_requested 信号不直连 Sfx）
│   ├── campaign_battle_bridge.gd ★ 冒险出征桥接（SceneArgs.campaign_token ⇄ settle）
│   └── automation/            battle_scenario_loader / battle_runner / battle_report
│
├── campaign/                  【冒险模式核心，2026-11-18 新增】6 .gd
│   ├── campaign_session.gd    ★ autoload CampaignSession（973 行）：档案/关卡/商店/出征令牌/
│   │                          settle 幂等结算/掉落独立 RNG/升级差分；signal changed(reason)
│   ├── campaign_config.gd     data/campaign.json 加载与校验（6 关卡+奖励+loot_table，340 行）
│   ├── campaign_profile_codec.gd 档案编解码 + 校验（435 行）
│   ├── campaign_profile_store.gd 档案原子落盘（user://campaign_saves/，329 行）
│   ├── campaign_roster.gd     固定队伍管理（297 行）
│   └── shop_catalog.gd        data/shop.json 目录（{id,price,limit_per_clear}，106 行）
│
├── editor/                    【战场编辑器】28 .gd
│   ├── battlefield_doc.gd     文档模型（generate/to_json_dict/quick_validate）
│   ├── editor_canvas.gd       画布（内嵌 BattlefieldRenderer；多高度拾取）
│   ├── tile_preview.gd / block_selector.gd / editor_block_list.gd / editor_block_picker_dialog.gd
│   ├── asset_library_panel.gd ★ 用户素材库面板（983 行）
│   ├── selection_range.gd / region_clipboard.gd / region_preset_store.gd
│   ├── shortcut_hints_dialog.gd
│   ├── map_editor_*.gd ×15    assets/block_palette/cell_tools/clipboard/file_io/generate/
│   │                          history/model_ops/overlays/paint_ops/panel_tabs/presets/
│   │                          region_select/replace/shortcuts（装配层薄委托模式）
│   ├── map_editor_buildings.gd ★ 建筑摆放工具（footprint 预览/校验，120 行）
│   └── map_editor_units.gd    ★ 角色选中/资料回显/可撤销编辑（接 ProfessionData）
│
├── scenes/                    【场景脚本】20 .gd
│   ├── battle.gd              ★ 战斗场景编排器（2186 行装配层：状态机/输入/胜负/行动历史/
│   │                          campaign 结算接线；记录 Tab@619,651）
│   ├── campaign_main.gd       ★ Campaign.tscn 装配层（173 行；battle_requested 信号）
│   ├── campaign_save_select.gd 存档选择屏（437 行）
│   ├── campaign_hub.gd        营地 Hub（416 行：金币/库存/roster/进度）
│   ├── campaign_levels.gd     关卡列表（245 行）
│   ├── campaign_shop.gd       营地商店（249 行）
│   ├── campaign_format.gd     屏格式化基类（267 行）
│   ├── campaign_modal.gd      模态层（214 行）
│   ├── title.gd               标题屏（SkillListButton → 图鉴）
│   ├── skill_list.gd          技能图鉴（190 行）
│   ├── map_editor.gd          编辑器装配层（1088 行）
│   ├── game_entry.gd / game_session.gd / startup_config.gd / home_entry.gd
│   ├── dialogue_demo.gd / ui_component_gallery.gd / pixelfx_gallery.gd
│   ├── isometric_3d_test.gd / scene_args.gd（跨场景传参 autoload）
│
├── assets/                    【用户素材 + 内置建筑素材】5 .gd
│   ├── user_asset_service.gd  ★ 本地导入 sha 去重 / 网络清单拉取 / blob 存储
│   ├── user_asset_catalog.gd / user_asset_visual_adapter.gd
│   ├── builtin_building_assets.gd 内置建筑素材目录（watchtower，87 行）
│   └── builtin_house_assets.gd   内置房屋素材目录（house，75 行）
│
├── audio/game_sfx.gd          ★ autoload Sfx
├── ui/                        ui_theme.gd（老主题）/ ui_factory.gd（工厂）/ loading_screen.gd
├── ui_gallery/                组件画廊 6 模块（basic_pages/battle_page/cursor_page/
│                              frame_pages/layout_page/widgets；自 ui_component_gallery.gd 拆出）
├── world/                     【世界生成模块】20 .gd（RefCounted/静态，Callable 注入）
│   ├── terrain_sampler.gd / cell_context.gd / cell_state.gd / deterministic_rng.gd
│   ├── noise_registry.gd / terrain_material_registry.gd / terrain_material_parser.gd
│   ├── map_snapshot_renderer.gd / minimap_renderer.gd
│   ├── biomes/                biome_module / biome_registry + temperate/desert/snow
│   ├── ecology_config_compiler.gd / ecology_config_validator.gd
│   ├── terrain_texture_catalog.gd / player_occlusion_controller.gd
│   ├── presentation_stage.gd / ecosystem_match.gd / species_picker.gd
│   ├── world_query_service.gd / flora_spawner.gd / fauna_streamer.gd / animal_runtime.gd
│
├── ecology/                   【生态/群落】8 .gd（registry 984 / runtime 943 / legacy_codec / resolver /
│                              spawner / state_store / member_composer / ambient_registry + renderers/）
├── animals/animal_behavior_registry.gd
├── tests/                     test_skills.gd（44/44）/ debug_test.gd（35/35）
├── tools/battle_cli.gd 之外的 tools 侧脚本
└── （世界表现层 + UI，散落 scripts/ 根）17 .gd：weather/day_night/sunlight/depth_of_field/
    world_audio/firefly_field/wandering_animal/isometric_column_batch/isometric_depth_sort/
    game_hud(178)+hud/2/world_map_overlay/side_panel/hint_bar/game_cursor(autoload)/
    debug_console_commands/settings.gd(autoload)
```

## `ui/` 组件库（详见 `ui/README.md`）

```
ui/
├── README.md                 使用文档（ComponentTheme / 组件清单 / 画廊说明）
├── theme/component_theme.gd  class_name ComponentTheme：token 唯一实现
└── components/               27 个 @tool 控件（21 功能 + 6 薄布局容器）
    ├── pixel_button / check_button / option_button / dropdown
    ├── pixel_line_edit / text_area / slider / spin_box
    ├── pixel_progress_bar / tabs / panel(+tscn) / popup
    ├── pixel_image / icon / audio_player / video_player
    └── pixel_avatar_frame★ / pixel_frame★ / pixel_nameplate★ /
        pixel_ninepatch_frame★ / pixel_tabs_vertical★（2026-11-18 新增 5）
```

业务消费者：**campaign_*.gd 七屏全量使用 Pixel* + ComponentTheme**（首个正经业务消费者）；map_editor 部分迁移；画廊 `scenes/UIComponentGallery.tscn`（F6/ESC）。契约 `tests/ui_components_contract.gd`（1404 行）+ `tests/ui_contract.gd`（静态扫描禁直建控件）。

## `tools/`（关键件）

| 文件 | 用途 |
| --- | --- |
| `run_contracts.py`(+`test_run_contracts.py` 27 test) | ★ 统一契约 runner（manifest 103 项；--test/--group/--changed/--jobs/--junit/--backend） |
| `run_simulations.gd` / `simulation_batch.gd` | 批量战斗模拟（1000 局 3.6s） |
| `autosim_battle_adapter.gd` / `autosim_first_action_bot.gd` | godot_autosim 接入 |
| `battle_cli.gd` | 声明式战场 CLI（--scenario/--seed/--out） |
| `build_blocks_manifest.mjs`(+`.test.mjs` 7 test) | 用户素材清单生成/校验 |
| `prepare_building_demo.gd` / `prepare_house_demo.gd`★ | 建筑/房屋演示战场生成（产出 data/battlefields/*_demo.json） |
| `slice_class_sheets.py` / `slice_ui_sheet.py` | 素材图集切片 |

## 关键文件快速索引

| 想做什么 | 看哪里 |
| --- | --- |
| 理解世界生成 | `main.gd` 函数簇分区表 + `scripts/world/` 20 模块（装配点 `_configure_generation_services`@485） |
| 理解冒险模式 | `docs/campaign_loop.md`（权威）+ `scripts/campaign/` + `campaign_session.gd` API |
| 改职业/成长 | `scripts/core/professions.gd`（九键 growths_for）+ `data/professions.json` |
| 加技能图标 | `scripts/core/skill_icons.gd`（稳定 ID '01'..'53'，**勿重排**） |
| 加建筑素材 | `docs/building_assets.md`（四方向 4:1 sheet 契约）+ `builtin_*_assets.gd` + recipe.json |
| 改编辑器 | `scripts/scenes/map_editor.gd`（1088 行装配层）+ `scripts/editor/` 28 模块 |
| 用户素材 | `docs/user_assets.md` + `scripts/assets/` |
| 查功能↔文件归属 | `docs/feature_map.html`（知识图谱）+ `docs/feature_map.json` |
| 查可复用组件/自检 | `claude/report.md` |
| 用新 UI 组件 | `ui/README.md` + `DESIGN.md` + 画廊 |
| 跑无表现战斗模拟 | `docs/battle_automation.md` + `tools/battle_cli.gd` |
| 跑测试 | `python3 tools/run_contracts.py`（默认入口） |

## 文件类型统计（git ls-files）

| 类型 | 数量 | 说明 |
| --- | --- | --- |
| 总文件 | **12318** | 含 addons vendored 与全部素材 |
| `.gd` | **~791**（自有） | scripts ~191 / tests 115 / ui 28 / addons ~430 / tools 等 |
| `.tscn` | 自有 18 | main + scenes/13 + ui/pixel_panel + tests 5（探针/集成） |
| `.json` | 45+（不含 addons） | config + data（+campaign/shop）+ fixtures |
| `.md` | 230+ | story 19 + rules 4 + claude/ + docs/ + handoff/ |
| `.png` | 600+ | meowa_tiles + assets + docs/screenshots |
| `.gdshader` | 自有 6 | day_night_overlay / encounter_warp / isometric_terrain_rotate / tilt_shift_dof / underwater_animal / weather_overlay |

## 生成物 / 已忽略

- `.godot/`（引擎生成，gitignore；**改码后须删 `.godot/editor` 再重启编辑器**）
- `.import` / `.uid`（引擎自动生成）
- `/builds/ /exports/ /android/`（导出产物，gitignore）
- `.codegraph/ / .dsh/ / .claude/ / .libtv/`（本地工具目录）；`.tmp/`（跨机调试工作目录，unmapped 18 条）
- `data/battlefields/*.bak`（编辑器保存残留脏文件——已知清理项）、`assets/ui/tmp/`（切片中转）
- 二进制素材（`.png`/`.mp3`）—— 未分析内容，仅统计
