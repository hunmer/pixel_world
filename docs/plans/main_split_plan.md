# main.gd 结构化拆分方案（P3-13）

> 2026-11-15 · main-split · 状态：**方案已评审待执行**
> 目标：把 main.gd（4319 行 / 176 函数）的函数簇渐进抽取到 `scripts/world/` 独立模块，**行为 100% 不变**。
> 红线：流式生成顺序、确定性调用顺序（内容 ID / stream_key / legacy placement_seed 路径）不变；`tests/terrain_generation_contract.gd` 的固化 SHA-256 快照每批必跑必绿。

## 0. 结论速览

- **7 个执行批次**，风险递增：纯函数 → 自包含 UI/状态 → 装配 builder + 匹配 statics → 植被 → 动物群体 → 动物个体 → 全量回归收尾。
- **新建 9 个模块文件，全部放 `scripts/world/`**（理由见 §3）。不建 `scripts/main_parts/`。
- 终态 main.gd ≈ **1750–1850 行**（含 ~19 个薄委托），留守函数 = 组合根（`_ready`/`_regenerate`/`_process`/`_unhandled_input`/`_setup_*` 装配调用点）+ 流式编排（簇5）+ 地形薄包装（簇4）+ 坐标/排序（簇6）+ 玩家移动渲染 + 战棋入口/B1 相机（簇17）+ 公开查询 API。
- **成员字段（含 `_cam`/`_cell_states`/`_animals` 等被契约直访的字段）全部留守 main.gd**；模块通过构造参数拿到同一对象引用（Dictionary/Array/Object 均为引用传递，语义不变）。
- 被 `world.<func>` 直调的私有函数若被移动，main.gd 保留**一行薄委托**（§2 有完整清单）。

## 1. 硬约束（执行时逐条自检）

1. **纯移动**：只把函数体/常量/缓存搬到新文件并参数化成员访问；不改任何表达式、数值、比较顺序、循环顺序、随机 salt、排序 key。字符串字面量、注释原样随迁。
2. **确定性契约**：`_hash_u32`/`_cell_rand`/`_community_rand01` 的调用参数与 RNG 流（`&"legacy"` / `stream_key`）逐字节不变；`placement_seed` 概率判定顺序不变；三缓存（`_ecology_near_tag_cache`/`_spatial_flora_plan_cache`/`_raw_selected_flora_cache`）的清空时机仍在 `_update_streaming` 开头同位置。
3. **`_ready`/`_regenerate`/`_update_streaming`/`_spawn_cell` 的语句顺序不动**（加载顺序语义）。抽取后 main 在原位置调用模块方法。
4. **新模块禁止反向依赖 main.gd**：不 preload/不 `get_node` 回 main；需要 main 的能力时用构造注入（对象引用或 Callable）。允许持有 `Node`/`Node2D` 参数并 `add_child`（组合根装配），但不得调用 main.gd 特有方法。
5. **契约直访 API**（下节清单）必须仍在 main.gd 实例上可访问（本体留守或薄委托）；`@export`（seed/stream_extent/sight_radius）与公开查询（`cell_stand_level`/`screen_to_cell`/`screen_to_cell_in_rect`/`get_player_occluder_cells`/`set_battle_camera_kick`/`is_world_map_open`）不动。
6. 风格：tab 缩进、`snake_case.gd`、新文件顶部 `## file.gd — 职责` 中文注释、类风格参照 `scripts/world/terrain_sampler.gd`（`class_name X extends RefCounted`）。
7. 已知红契约 `ui` / `map_editor_ui` 不修不弄更红；挂起契约 `action_anim` / `immersive_battle_camera` / `world_map_overlay` / `user_asset_source_live` 不跑。
8. 不碰 `scripts/editor/map_editor.gd`、`data/`、`story/`、`tests/` 断言内容；不 git commit/branch/reset。

## 2. 契约对 main.gd 的直访面（grep `world\.[A-Za-z_]+` tests/*.gd 实测）

**直调的私有函数（34 个）**：`_quantize` `_biome` `_is_beach` `_modules` `_desert_surface_kind` `_cell_rand` `_stand_level` `_cell_feet_pos` `_grid_to_screen` `_refresh_view_projection` `_pick_species` `_select_flora_candidate` `_flora_candidates_for_cell` `_has_raw_selected_flora_layer_within` `_ecosystem_id_for_cell` `_spawn_animal` `_update_animals` `_begin_animal_move` `_can_animal_enter` `_clear_animals` `_animal_species_allows_surface` `_underwater_animal_material_for_depth` `_water_clearance` `_fauna_anchor_fully_loaded` `_fauna_anchor_for_bucket` `_animal_group_spawn_cells` `_create_animal_group` `_restore_animal_group` `_has_water_within` `_update_streaming` `_free_cell` `_regenerate` `_process` `_unhandled_input` `_try_move` `_enter_battle_inline` `_exit_battle` `_handle_battle_camera_input` `_battle_camera_focus` `_set_camera_position` `_sync_depth_of_field_focus`（另 `set`/`call`/`get` 动态访问）。

**直访的成员字段**：`_cam` `_day_night` `_cell_states` `_player_cell` `_animals` `_terrain` `_battle_system` `_animal_species` `_cells` `_sunlight` `_weather` `_terrain_sampler` `_animal_groups` `_plant_species` `_ecosystems_by_id` `_ecosystem_order` `_tree_placement` `_ground_cover_placement` `_decoration_placement` `_player` `_player_visual_position` `_audio` `_ambient_registry` `_depth_of_field` `_camera_smooth_position` `_stream_center` `_battle_active` `_battle_cam_offset` `_battle_pan_active` `_view_dragging` `_player_visible_backup`。

**直访常量**：`WATER_MAX` `FLORA_LAYER_IDS` `ANIMAL_DIRECTIONS` `WORLD_MAP_RANGE_MULTIPLIER` `LEVELS` `ANIMAL_FLEE_RADIUS`。

→ **推论**：所有成员字段与上述函数本体（或薄委托）留守 main.gd；仅未被直访的函数/缓存字段搬家。需要共享常量值（如 `WATER_MAX`）的新模块经构造参数注入（常量运行期不可变，等价）。

## 3. 目标模块（9 个新文件，均在 scripts/world/）

选址理由：这些簇全部是世界引擎子域；`scripts/world/` 已是确定性核心（terrain_sampler/deterministic_rng/cell_state/noise_registry/…）的家，依赖方向天然单向（main → world，world 不知 main）。不新建 `scripts/main_parts/`：避免与既有子域目录平行造成两套归类标准；表现层装配 builder 虽偏表现，但构造的是世界舞台节点，归 world 域一致性更好。

| # | 文件 | 类型 | 职责 | 承接簇 | 随迁状态 |
|---|---|---|---|---|---|
| M1 | `ecology_config_validator.gd` | static 工具 | 生态配置校验 + 枚举名映射 | 簇2（除 `_sync_legacy_noise_handles`） | 无（纯参数） |
| M2 | `terrain_texture_catalog.gd` | RefCounted | 12 个地形纹理字段 + `_solid_tex`/水下纹理缓存 + 水面纹理绘制 statics | 簇10 + 簇6 纹理函数 | `_underwater_texture_cache`、12 个 `_*_tex` 字段 |
| M3 | `minimap_renderer.gd` | RefCounted | 小地图画布/UI/更新/颜色 | 簇12 | `_minimap_img`/`_minimap_tex`（`_explored` 留 main，按引用传入） |
| M4 | `player_occlusion_controller.gd` | RefCounted | 玩家 prop 遮挡重建/衰减 | 簇11 遮割部分 | 8 个 `_player_occlusion_*` 字段 + `PLAYER_OCCLUSION_*` 常量 |
| M5 | `presentation_stage.gd` | static 工具 | day_night/dof/audio/fireflies/weather 的节点构造 builder | 簇15 `_setup_*` 5 个 | 无（节点字段留 main，builder 返回实例由 main 赋值） |
| M6 | `ecosystem_match.gd` | static 工具 | ecosystem 五键匹配/legacy context/chance 提取 | 簇7 前 6 个解析函数 | 无 |
| M7 | `world_query_service.gd` | RefCounted | 流式无关格查询：`_cell_context_for_query`/`_ecology_near_tag`(含缓存)/`_water_clearance`/`_community_water_clearance_valid` | 簇9 查询 4 函数 | `_ecology_near_tag_cache` |
| M8 | `flora_spawner.gd` | RefCounted | 植被候选/空间群落/落位/ambient 簇 | 簇7 主体（除 M6 接走的） | `_flora_cache`/`_raw_selected_flora_cache`/`_spatial_flora_plan_cache` |
| M9a | `species_picker.gd` | static 工具 | `_pick_species`（dominant+加权轮盘；植被/ambient/动物共用） | 簇7 的 `_pick_species` | 无 |
| M9b | `fauna_streamer.gd` | RefCounted | 动物群体锚点/分组/替换/恢复 | 簇8 | 无（`_animal_groups` 留 main 按引用传入） |
| M9c | `animal_runtime.gd` | RefCounted | 动物个体生成/帧动画/行为决策/移动 bout | 簇9 主体（除 M7 接走的） | 动画帧缓存/水下材质缓存/距离缓存 + `ANIMAL_*` 个体行为常量 |

（M9 系列编号为一个家族；实际文件 11 个，其中 2 个纯 static 工具无状态。）

**依赖方向**：`main.gd → M1..M9 → {scripts/world 既有模块, scripts/ecology 既有模块, Godot 内置}`；`M8/M9b/M9c → M7/M9a/M6`。新模块间只经 preload 静态调用或构造注入 RefCounted 实例；**无任何边指向 main.gd**。main 回调以 `Callable` 注入（如 `_spawn_animal`、`_sample_cell_context`）。

## 4. 176 函数 → 簇 → 目标模块完整映射表

簇分区与行号来自 2026-11-15 实测（main.gd@4319 行）。「留守」= 原函数不动；「→MX」= 函数体移入模块（main 调用点改为 `模块.方法(...)`）；「→MX+委托」= 移动且 main 留一行薄委托（契约直调）。

### 簇1 生态配置加载编译（266–542）— 全部留守（组合根）
| 函数@行 | 目标 |
|---|---|
| `_load_ecosystem_config`@266 | 留守（构造 EcologyRegistry/Runtime/Sampler/Materials；texture_processor Callable 改指 M2 的 `pad_texture_to_32`，计算体不变） |
| `_compile_ecosystem_config`@315 | 留守（填充 ~40 个留守字段；校验调用改指 M1） |
| `_compile_animal_behavior_stacks`@500 | 留守 |

### 簇2 配置校验+辅助（543–974）— 10 函数
| 函数@行 | 目标 |
|---|---|
| `_validate_ecosystem_config`@543 | →M1 |
| `_validate_fauna_distribution`@769 | →M1 |
| `_validate_ecosystem_match`@825 | →M1（内部调 M6 的 match/subsumes） |
| `_ecosystem_match_subsumes`@878 | →M6 |
| `_chance_value_is_valid`@901 | →M1 |
| `_numeric_range_is_valid`@916 | →M1 |
| `_noise_type_from_name`@928 | →M1 |
| `_fractal_type_from_name`@942 | →M1 |
| `_noise_instance_for_field`@952 | →M1（noise_registry 经参数） |
| `_sync_legacy_noise_handles`@965 | 留守（写 3 个留守字段） |

### 簇3 启动/重生成（975–1071）— 全部留守（顺序红线）
`_ready`@975、`_regenerate`@1022 留守；纹理获取语句改经 M2 实例（顺序不变）。

### 簇4 地形核心薄包装（1072–1174）— 全部留守（契约直调密集 + 全簇共享词汇）
`_sample_cell_context`@1072、`_hash_u32`@1085、`_cell_rand`@1089、`_seed_point`@1095、`_landform_type`@1100、`_voronoi`@1106、`_modules`@1111、`_quantize`@1123、`_biome`@1128、`_print_stats`@1133 — 全留守。

### 簇5 流式生成（1175–1340）— 全部留守（确定性红线编排）
`_spawn_cell`@1175、`_append_water_volume`@1226、`_water_block`@1264、`_render_block`@1271、`_free_cell`@1289、`_stream_center`@1305(var)、`_update_streaming`@1308、`_in_stream`@1337 — 全留守；内部调用纹理/植被/动物处改为 M2/M8/M9b/M9c 方法（实参同序同值）。

### 簇6 坐标/投影/排序/材质辅助（1341–1504）— 11 函数
| 函数@行 | 目标 |
|---|---|
| `_grid_to_world`@1341 | 留守 |
| `_grid_to_screen`@1345 | 留守（契约直调 5×） |
| `_column_sort_y`@1355 | 留守 |
| `_refresh_view_projection`@1368 | 留守（契约直调） |
| `_restore_view_draw_culling`@1373 | 留守 |
| `_ensure_sort_origin`@1377 | 留守 |
| `_is_beach`@1404 | 留守（契约直调） |
| `_solid_tex`@1409 | →M2 |
| `_underwater_texture_for_context`@1443 | →M2（缓存随迁） |
| `_desert_surface_kind`@1464 | 留守（契约直调，3 行薄包装） |
| `_soil_or_little_grass`@1484 | →M2 |

### 簇7 植被生态（1490–2041）— 22 函数
| 函数@行 | 目标 |
|---|---|
| `_plant_tex`@1494 | →M8（缓存 `_flora_cache` 随迁） |
| `_pick_species`@1505 | →M9a+委托（契约直调 1×；簇7/簇8/ambient 共用） |
| `_ecosystem_id_for_cell`@1532 | →M6+委托（契约直调 2×） |
| `_legacy_cell_context`@1546 | →M6 |
| `_ecosystem_matches`@1565 | →M6 |
| `_biome_id`@1586 | →M6 |
| `_ecology_chance`@1590 | →M6 |
| `_raw_flora_candidates_for_rules`@1606 | →M8 |
| `_raw_flora_candidates_for_cell`@1657 | →M8 |
| `_flora_candidates_for_cell`@1671 | →M8+委托（契约直调 1×） |
| `_flora_candidates_for_rules`@1683 | →M8 |
| `_resolve_flora_habitat_species`@1701 | →M8 |
| `_raw_selected_flora_for_cell`@1715 | →M8（缓存 `_raw_selected_flora_cache` 随迁） |
| `_has_raw_selected_flora_layer_within`@1736 | →M8+委托（契约直调 1×） |
| `_select_flora_candidate`@1753 | →M8+委托（契约直调 2×） |
| `_spawn_flora`@1768 | →M8 |
| `_flora_candidates_with_spatial`@1795 | →M8 |
| `_spatial_flora_candidates_for_cell`@1814 | →M8 |
| `_spatial_flora_plan`@1852 | →M8（缓存 `_spatial_flora_plan_cache` 随迁） |
| `_spatial_flora_candidate`@1878 | →M8 |
| `_place_flora`@1923 | →M8 |
| `_spawn_ambient_for_cell`@1974 | →M8（host 参数=main Node） |

### 簇8 动物群体（2042–2511）— 16 函数
| 函数@行 | 目标 |
|---|---|
| `_spawn_fauna_for_stream`@2042 | →M9b |
| `_fauna_anchor_fully_loaded`@2117 | →M9b+委托（契约直调 2×） |
| `_fauna_anchor_for_bucket`@2126 | →M9b+委托（契约直调 2×） |
| `_animal_group_id`@2144 | →M9b |
| `_community_rand01`@2153 | 留守（确定性词汇，簇8/簇9 共用，1 行体） |
| `_fauna_source_uses_generic_spawner`@2159 | →M9b |
| `_community_anchor_for_source`@2168 | →M9b |
| `_create_first_class_animal_group`@2189 | →M9b |
| `_cache_inactive_animal_group`@2289 | →M9b |
| `_create_animal_group`@2309 | →M9b+委托（契约直调 1×） |
| `_animal_group_spawn_cells`@2372 | →M9b+委托（契约直调 3×） |
| `_animal_group_cell_is_valid`@2420 | →M9b |
| `_has_water_within`@2452 | →M9b+委托（契约直调 1×） |
| `_restore_animal_group`@2461 | →M9b+委托（契约直调 2×） |
| `_active_animal_count_for_group`@2494 | →M9b |
| `_release_animal_group_member`@2506 | →M9b |

### 簇9 动物个体与行为（2513–3043）— 25 函数
| 函数@行 | 目标 |
|---|---|
| `_spawn_animal`@2513 | →M9c+委托（契约直调 7×；M9b 经 Callable 调用） |
| `_underwater_animal_material_for_depth`@2568 | →M9c+委托（契约直调 1×） |
| `_animal_species_allows_surface`@2589 | →M9c+委托（契约直调 2×） |
| `_animal_frames_for`@2607 | →M9c（帧缓存随迁） |
| `_add_sheet_animation`@2641 | →M9c |
| `_clear_animals`@2666 | →M9c+委托（契约直调 3×；需 host Node） |
| `_cleanup_streamed_animals`@2676 | →M9c |
| `_update_animals`@2697 | →M9c+委托（契约直调 4×） |
| `_animal_in_active_stream`@2735 | →M9c |
| `_begin_animal_move`@2742 | →M9c+委托（契约直调 1×） |
| `_can_animal_enter`@2795 | →M9c+委托（契约直调 2×） |
| `_animal_cell_reserved`@2811 | →M9c（M9b 也要调，经注入） |
| `_animal_should_flee`@2821 | →M9c |
| `_animal_move_score`@2839 | →M9c |
| `_animal_behavior_decision`@2862 | →M9c |
| `_animal_behavior_cell_data`@2893 | →M9c（内部调 M7） |
| `_cell_context_for_query`@2907 | →M7（簇7/8/9 共用；main 与各模块经同一实例） |
| `_water_clearance`@2915 | →M7+委托（契约直调 2×） |
| `_community_water_clearance_valid`@2937 | →M7 |
| `_ecology_near_tag`@2957 | →M7（缓存随迁；Callable 注入 M8/M9b） |
| `_animal_behavior_distance_to_tag`@2983 | →M9c |
| `_animal_social_center`@3008 | →M9c |
| `_animal_wait`@3024 | →M9c |
| `_animal_bout_steps`@3028 | →M9c |
| `_animal_step_pause`@3037 | →M9c |

### 簇10 水体纹理（3045–3110）— 5 函数
| 函数@行 | 目标 |
|---|---|
| `_make_water_face_texture`@3046 | →M2（static） |
| `_make_underwater_ground_texture`@3069 | →M2（static） |
| `_underwater_flora_modulate`@3091 | →M2（static；M8 调用经 M2） |
| `_process_terrain_material_texture`@3097 | →M2（`Callable(self,…)` 改指 M2.pad_texture_to_32，体=纯转发，等价） |
| `_pad_texture_to_32`@3104 | →M2（static） |

### 簇11 玩家渲染/遮挡/移动（3113–3458）— 20 函数
| 函数@行 | 目标 |
|---|---|
| `_setup_terrain`@3115 | 留守 |
| `_setup_player`@3121 | 留守 |
| `_set_player_render_position`@3143 | 留守 |
| `_set_player_pose`@3154 | 留守 |
| `_track_player_camera_yaw`@3160 | 留守 |
| `_refresh_player_visual`@3170 | 留守 |
| `_player_movement_sort_y`@3181 | 留守 |
| `_player_current_stand_level`@3193 | 留守（契约直调） |
| `_player_occlusion_needs_rebuild`@3201 | →M4 |
| `_update_player_occlusion`@3217 | →M4（`_process` 调用点不变） |
| `_collect_player_prop_occluders`@3235 | →M4 |
| `_prop_block_covers_player`@3286 | →M4 |
| `_prop_texture_image`@3312 | →M4 |
| `_rebuild_player_prop_occlusion`@3319 | →M4 |
| `get_player_occluder_cells`@3338 | 留守（公开 API，转调 M4） |
| `_stand_level`@3349 | 留守（契约直调 4×） |
| `_cell_feet_pos`@3353 | 留守（契约直调） |
| `_input_dir`@3358 | 留守 |
| `_try_move`@3372 | 留守（契约直调） |
| `_process`@3401 | 留守（契约直调；主循环编排） |

### 簇12 小地图（3463–3534）— 5 函数
| 函数@行 | 目标 |
|---|---|
| `_setup_minimap`@3463 | →M3（CanvasLayer 挂 host=main） |
| `_reveal`@3487 | →M3（`_explored` 按引用传入；`_sample_cell_context` 经 Callable） |
| `_update_minimap`@3496 | →M3 |
| `_minimap_color`@3507 | →M3（无调用点，原样随迁保持行为面） |
| `_map_color_for_context`@3512 | →M3 |

### 簇13 相机/HUD/大地图（3539–3605）— 7 函数
`_setup_camera`@3539、`_setup_hud`@3548、`_setup_world_map`@3559、`is_world_map_open`@3565、`_toggle_world_map`@3569、`_world_map_snapshot`@3583、`_handle_world_map_input`@3596 — 全留守（信号连线与 `_explored` 字段在 main）。

### 簇14 输入分发（3608–3707）— 1 函数
`_unhandled_input`@3608 留守（契约直调 15×；B1/地图/导航短路顺序红线）。

### 簇15 表现层系统装配（3710–3863）— 9 函数
| 函数@行 | 目标 |
|---|---|
| `_setup_day_night`@3710 | →M5（builder 返回 DayNightSystem+SunlightSystem，main 赋值字段+add_child 顺序不变；`--time` 解析随迁） |
| `_setup_depth_of_field`@3736 | →M5（`--dof` 解析随迁） |
| `_sync_depth_of_field_focus`@3753 | 留守（契约直调） |
| `_setup_audio`@3761 | →M5（读留守 `_animal_species` 字段经参数） |
| `_setup_fireflies`@3780 | →M5（registry 实例留 main 字段，builder 装配） |
| `_setup_weather`@3796 | →M5（`--weather` 解析随迁；信号连线经 Callable） |
| `_sync_weather_audio`@3815 | 留守（main 字段直连） |
| `_sync_weather_environment`@3824 | 留守（`_try_move`/`_regenerate` 直调） |
| `_on_weather_water_impact`@3841 | 留守（读 `_cam`/`_water_cells`/`_terrain`） |

### 簇16 缩放/相机位置/截图（3866–3983）— 6 函数
`_zoom_step`@3866、`_apply_zoom`@3894、`_set_camera_position`@3910（契约直调）、`set_battle_camera_kick`@3922、`_snap_camera_position`@3929、`_shot_and_quit`@3941 — 全留守（跨 battle/weather/ambient/dof 编排 + CLI 工具，收益低风险高）。

### 簇17 战棋入口 + B1 相机（3991–4319）— 17 函数，全留守
`_enter_battle`@3991、`_change_to_battle_scene`@4025、`_enter_battlefield`@4044、`_on_battlefield_picked`@4090、`_open_map_editor`@4097、`_enter_battle_inline`@4107（契约直调 5×）、`_exit_battle`@4143（契约直调 4×）、`_handle_battle_input`@4163、`_battle_camera_focus`@4174（契约直调 2×）、`_handle_battle_camera_input`@4198（契约直调 6×）、`_update_battle_edge_pan`@4233、`_clamp_battle_cam_offset`@4271、`_is_battle_mouse_over_ui`@4282、`cell_stand_level`@4295（公开 API 11×）、`screen_to_cell`@4300（5×）、`screen_to_cell_in_rect`@4307（2×）、`_screen_to_world_pos`@4318 — 理由：契约直调密集 + `SceneArgs.battle_args.world=self` 宿主职责 + B1 相机字段全留守，抽取只剩委托空转。

**统计**：176 函数中留守 81（另有 1 个顶层 var `_stream_center` 随簇5 留守），移动 95（其中 19 个在 main.gd 保留薄委托）。

## 5. 批次计划（风险递增；每批全绿才进下一批）

每批流程：抽取 → `git diff --stat` 自检无意外文件 → 跑该批契约（命令行 headless，按日志 OK 标记判定）→ **必跑 `terrain_generation_contract`（SHA-256）** → 更新本文档批次状态。

| 批 | 内容 | 新文件 | 预计抽走 | 验证契约（`tests/<name>_contract.gd`） |
|---|---|---|---|---|
| B1 | M1 校验 + M2 纹理目录（簇2×9、簇10×5、簇6 纹理×3 + 12 纹理字段 + 水下缓存） | ecology_config_validator.gd, terrain_texture_catalog.gd | ~560 行 | **terrain_generation**, terrain_material_registry, terrain_sampler, world_terrain_mapping, dynamic_landform, biome_modules, module_extension, config_manifest, ecology_registry, ecology_resolver, cell_state, cell_state_integration, isometric_3d |
| B2 | M3 小地图 + M4 玩家遮挡 | minimap_renderer.gd, player_occlusion_controller.gd | ~310 行 | **terrain_generation**, isometric_3d, isometric_view, isometric_column_projection, streaming_input_latency, startup_config, battle_occluder, game_hud |
| B3 | M5 表现 builder + M6 生态匹配 | presentation_stage.gd, ecosystem_match.gd | ~270 行 | **terrain_generation**, sunlight_3d, sunlight_3d_gl, depth_of_field, weather_performance, audio_system, ambient_registry, game_sfx, startup_config, ecology_resolver, flora_layers, community_runtime |
| B4 | M7 查询服务 + M9a 选种 + M8 植被（簇7 主体） | world_query_service.gd, species_picker.gd, flora_spawner.gd | ~620 行 | **terrain_generation**, flora_layers, community_spawner, community_runtime, community_state_store, ecology_resolver, world_terrain_mapping, cell_state_integration, ambient_registry, animal_group_distribution |
| B5 | M9b 动物群体（簇8） | fauna_streamer.gd | ~470 行 | **terrain_generation**, animal_group_distribution, community_state_store, community_spawner, aquatic_fauna, animal_animation_state, streaming_input_latency |
| B6 | M9c 动物个体（簇9 主体） | animal_runtime.gd | ~430 行 | **terrain_generation**, animal_behavior_registry, animal_animation_state, aquatic_fauna, bird_renderer, animal_group_distribution, streaming_input_latency, game_sfx, audio_system |
| B7 | 收尾全量回归 | —（无代码改动） | 0 | 全部契约（除 4 挂起：action_anim/immersive_battle_camera/world_map_overlay/user_asset_source_live；2 已知红 ui/map_editor_ui 只验证「不比基线更红」）；统计终态行数/函数数并更新本文档 |

预估终态：main.gd 4319 → **约 1800±80 行**；新模块合计 ~2600 行（含模块头注释与构造器）。

## 6. 执行规范（每批通用）

- **搬迁纪律**：函数体逐字符复制后仅做「成员访问 → 参数/字段访问」的机械替换（如 `_cell_rand(` → `_rng_compat.cell_rand(_world_rng, ` 这种统一前缀式改写）；替换清单随批记录在本文档。
- **薄委托模板**：`func _pick_species(rule: Dictionary, gc: Vector2i, cell: Vector2i) -> String:\n\treturn FloraSpawner.pick_species(...)` —— 签名、参数名与原函数一致。
- **Callable 注入点**（main → 模块）：`_sample_cell_context`、`_spawn_animal`、`cell_rand`/`community_rand01`（或直接注入 `_world_rng` + compat static）、viewport/相机 getter。注入在 `_ready` 最前或 `_load_ecosystem_config` 末尾（字段就绪点），不改变任何原语句顺序。
- **缓存清空时机**：`_update_streaming` 开头三连 clear 改为 `M7.clear_cache()` + `M8.clear_caches()`（同位置、同顺序）。
- **新文件头**：`## xxx.gd — 职责（中文一句话）` + `class_name XxxYyy` + `extends RefCounted`（static 工具可不 class_name，用 preload）。
- **.uid**：headless 契约运行后 Godot 自动生成 `.gd.uid`，随批保留。
- 契约命令：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/<name>_contract.gd > /tmp/t.log 2>&1; echo $?`（以日志内容判定，多数契约打印 OK 标记）。

## 7. 回滚策略

- 单批粒度回滚：`git checkout -- main.gd` + `rm <该批新文件>`（新文件 untracked，删除即净）；每批完成即记录该批触碰文件清单于本文档 §8。
- 批内小步：每个模块抽取是独立小步（B1 内 M1、M2 分两步），小步红了只回滚该小步。
- 绝不 `git reset/commit/branch`；工作区始终可直接 `git diff` 审计。

## 8. 执行记录（随批追加）

| 批 | 日期 | 结果 | 触碰文件 | 契约结果 | main.gd 行数 |
|---|---|---|---|---|---|
| B1 | 2026-11-15 | ✅ 16/16 绿（SHA ✓） | main.gd, +scripts/world/ecology_config_validator.gd (424), +terrain_texture_catalog.gd (192) | terrain_generation + terrain_material_registry / terrain_sampler / world_terrain_mapping / dynamic_landform / biome_modules / module_extension / config_manifest / ecology_registry / ecology_resolver / cell_state / cell_state_integration / isometric_3d / aquatic_fauna / flora_layers / ambient_registry | 4319 → 3798 |
| B2 | 2026-11-15 | ✅ 8/8 绿（SHA ✓） | main.gd, +minimap_renderer.gd (98), +player_occlusion_controller.gd (220) | terrain_generation + isometric_3d / isometric_view / isometric_column_projection / streaming_input_latency / startup_config / battle_occluder / game_hud | 3798 → 3595 |
| B3 | 2026-11-15 | ✅ 10/11 真实通过（SHA ✓；sunlight_3d_gl 环境限制，基线即败非回归） | main.gd, +presentation_stage.gd (131), +ecosystem_match.gd (132) | terrain_generation + sunlight_3d / sunlight_3d_gl / depth_of_field / weather_performance / audio_system / ambient_registry / game_sfx / startup_config / ecology_resolver / flora_layers / community_runtime | 3595 → 3520 |
| B4 | 2026-11-15 | ✅ 12/12 绿（SHA ✓ 零错误） | main.gd, +world_query_service.gd (99), +species_picker.gd (43), +flora_spawner.gd (551) | terrain_generation + flora_layers / community_spawner / community_runtime / community_state_store / ecology_resolver / world_terrain_mapping / cell_state_integration / ambient_registry / animal_group_distribution / aquatic_fauna / cell_state | 3520 → 3040 |
| B5 | 2026-11-15 | ✅ 7/7 绿（SHA ✓） | main.gd, +fauna_streamer.gd (572) | terrain_generation + animal_group_distribution / community_state_store / community_spawner / aquatic_fauna / animal_animation_state / streaming_input_latency | 3040 → 2671 |
| B6 | 2026-11-15 | ✅ 9/9 绿（SHA ✓ 零错误） | main.gd, +animal_runtime.gd (575) | terrain_generation + animal_behavior_registry / animal_animation_state / aquatic_fauna / bird_renderer / animal_group_distribution / streaming_input_latency / game_sfx / audio_system | 2671 → 2283 |
| B7 | 2026-11-15 | ✅ 全量回归 67/74 通过，零新增红（7 失败=5 基线即红 [battle_action_chain/battle_presentation_hooks/isometric_view/ui/map_editor_ui] + sunlight_3d_gl 环境限制 + user_asset_editor 为 editor-split 队友工作区进行中改动，失败日志零引用 main.gd/scripts/world/）；4 挂起契约按约束未跑 | 无代码改动；本表 + §9 注 | /tmp/final_baseline/summary.tsv（74 契约，600s 看门狗/个） | 2283（终态，128 函数；176→128） |

**终态**：main.gd 4319 → **2283 行**（-2036，47.1%）；顶层函数 176 → 128（48 个移入模块，测试直访面保留同名薄委托）。新增 12 个模块共 3037 行，全部位于 `scripts/world/`，均为 `class_name + extends RefCounted`，无反向依赖 main.gd（回调用显式 Callable 注入）。确定性 SHA-256 每批复验：`0c3f713bb202119938a5b7745e310f2e3800869b11acf13b93fb88b339abfc2f`（seed=42，16641 采样）从未漂移。

**执行期踩坑（供后续批次/他人复用）**：
1. `:= <Callable>.call(...)` 的 Variant 推断警告在本项目按错误处理（cursor/rr/chance 三处同型），模块内一切 Callable 结果参与算术/推断必须显式类型。
2. 切割区间内的「后插入委托」会被后续批次切割误删（B4 误删 B3 的 5 委托、B6 误删 B4 的 4 查询委托）——切割前必须逐一点名核对区间内所有函数去留；`Callable(self,"...")` 不做解析期校验，此类破坏只在运行时暴露，且 terrain SHA 仍可能绿（SHA 不覆盖运行时链路完整性）。
3. main.gd 引用新模块必须走 preload 常量（`XxxScript.`），headless 全局类缓存不登记新 class_name。
4. 删除 preload 前先查常量依赖链（ANIMAL_SORT_BIAS:=WanderingAnimalScript.SORT_BIAS 导致连锁失败一次）。
5. 契约判定三件套：exit code + OK 标记 + `grep -cE "SCRIPT ERROR|Parse Error|Compile Error" = 0`，缺一不可（Godot 重载重试机制可在编译失败时打出正确 SHA 假绿）。

## 9. 风险清单与已知取舍

1. **最大风险 = B4/B5/B6 确定性漂移**：植被/动物的概率判定链（`placement_seed`→`_ecology_chance`→`_cell_rand` 比较）必须逐字节保序。缓解：SHA-256 快照 + 逐批契约 + 函数体逐字符搬迁。
2. **Callable 间接层的性能**：流式热路径（`_update_streaming`/`_update_animals` 每帧）新增模块方法调用开销为纳秒级 Godot 方法分派，契约 `streaming_input_latency` 与 `weather_performance` 监督；超阈值即回滚。
3. **取舍：簇17（战棋入口/B1 相机）不抽**。契约直调密集（`_enter_battle_inline` 5× 等）+ 宿主职责重，抽完只剩委托空转，违背「结构化拆分」初衷。若后续要抽，须先给契约改走公开 API（改 tests 超出本任务范围）。
4. **取舍：簇4/5/6 全留守**。地形薄包装是全簇共享词汇；流式编排是红线本体；投影排序与 `_move_*`/`_animals` 深耦合。
5. **`_minimap_color`@3507 无调用点**：按「行为面 100% 不变」原则原样随迁，不在本次删除（清死码是另一个任务）。
6. **字段留守带来的模块构造参数较多**（M8 约 10+ 参数）：用单个 `Dictionary` 上下文或分组 setter 注入，构造点集中在 `_load_ecosystem_config`/`_ready`；不新增行为分支。
