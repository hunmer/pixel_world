# godot MCP 工具名总表（295 个，其中 49 个常驻）

> `breakpoint-mcp` 源码里的全集名单。**49 个常驻工具表、直接可调**；其余 246 个**没有注入**，调了只会 `tool not found`。
> 用途：**替代 `mcp_connector_session_tools({action:"search"})`**。search 只做单关键词子串匹配，**多词查询必然返回 0**（`"editor_ping runtime_get_log"` → 空），往往搜三四轮才定位一个名字。要什么就看本文件。

- publicName = `mcp__godot__` + 下表名字（**双下划线**）。
- 分组标题已标：**✅ = 已注入，能直接调**（`runtime_*` 30 + `dbg_*` 15 + 知识检索 4）；**❌ = 未注入**（`editor_*` 149、lsp/cslsp、cli、vcs、tabletop、assetgen、netcode、backend、csdap、录制等），看到 ❌ 组别再试名字——那条能力这一轮就是没有，改用 ✅ 组的等价手段。
- 带 ⚠ 的是破坏性操作：调用时**必须在参数里加 `"confirm": true`**，否则触发客户端确认弹窗（DSH 上通常直接被拒，返回 "re-run with confirm: true"）。不带 ⚠ 的都是只读，直接调。
- 想让更多工具常驻：改连接环境变量 `BREAKPOINT_TOOLSETS`（合法组：`cli`/`editor`/`lsp`/`cslsp`/`dap`/`csdap`/`runtime`/`processes`/`knowledge`/`hearing`/`vcs`/`assetgen`/`netcode`/`backend`/`tabletop`/`resources`），代价是每轮常驻 schema 变大。当前值 `runtime,dap,knowledge`。

## 意图 → 工具（先查这张表，别搜）

| 我想… | 用 | 关键参数 |
| --- | --- | --- |
| 自检：项目索引通不通 | `find_symbol` | `{"name":"_battle_active","max_results":1}` |
| 自检：有没有游戏在跑 | `runtime_get_monitors` | — |
| 把游戏跑起来 | `dbg_launch` | `{"scene":"res://main.tscn"}`（**必传**） |
| 重开当前运行实例 | `dbg_restart` | — |
| 看报错 / 警告 | `runtime_get_log` | `{"levels":["error","warning"]}` ← **必须带 levels** |
| 只看新增日志 | `runtime_get_log` | `{"since_seq":<上次 latest_seq>,"levels":["error"]}` |
| 读节点属性 | `runtime_get_property` | `{path,property}` |
| 看整棵运行树 | `runtime_get_tree` | — |
| 读游戏自己注册的状态 | `runtime_read_state` | 省略 `name` 先列出可用的读取器 |
| 调某个方法 | `runtime_call_method` | `{path,method,args,confirm:true}` |
| **表达式求值（GDScript）** | `dbg_evaluate` | `{expression,confirm:true}`；**必须先停在断点上**，否则 `not_stopped` |
| 推进帧 / 改时间流速 | `runtime_step_frames`、`runtime_time_scale` | 两者都要 `confirm:true` |
| 模拟按键 | `runtime_inject_input` | `{event:{kind:"key",keycode,physical_keycode,pressed},confirm:true}` |
| 模拟鼠标 / 指针 | `runtime_inject_input` | `event.kind` = `mouse_motion` / `mouse_button` / `pointer` |
| 断言属性值 | `runtime_assert_node_state` | `{path,expect,tolerance}` |
| 断言节点存在 / 类型 / 已消失 | `runtime_assert_scene_structure` | `{expect:[{path,type?,absent?}]}` |
| 断言屏幕文字 | `runtime_assert_screen_text` | `{text,present,regex,min_count}` |
| 等异步状态到位 | `runtime_await_condition` | `{path,property,value,op,timeout_ms}` |
| 性能 / 帧率 | `runtime_get_monitors`、`runtime_assert_perf` | — |
| 截图（需用户同意） | `runtime_screenshot`、`runtime_screenshot_diff`、`runtime_screenshot_save` | `diff` 带参考图 + tolerance |
| 设断点 | `dbg_set_breakpoints` | `{path,lines}` |
| 停下后看栈 / 变量 / 单步 | `dbg_stack_trace`、`dbg_scopes`、`dbg_variables`、`dbg_step`、`dbg_continue` | — |
| 找符号 / 定义 / 引用（比 grep 准） | `find_symbol`、`find_usages`、`project_search` | 全项目索引，不需要编辑器/LSP |
| 多实例确定性对拍 | `runtime_spawn_peers` → `runtime_peers_digest` | 见对应 description |
| 编辑器里改节点 / 场景 / 资源 | ❌ 未注入 | 让用户在编辑器里做，或改 `.tscn`/`.tres` 文本后重跑 |

## 这些名字**不存在**，别浪费时间搜

- `runtime_evaluate` / `runtime_eval` / `runtime_exec` ✖ —— 运行时**没有**求值工具。要求值：`dbg_set_breakpoints` + `dbg_launch` 停住，再 `dbg_evaluate`；否则用 `runtime_get_property` / `runtime_read_state` / `runtime_call_method`。
- `cursor` / `mouse` / `keyboard` ✖ —— 输入统一走 `runtime_inject_input`。
- 裸 `screenshot` ✖ —— 全名是 `runtime_screenshot` / `runtime_screenshot_diff` / `runtime_screenshot_save` / `screenshot_editor`。
- `print` / `console` ✖ —— 用 `runtime_get_log`。

## 全量名单（⚠ = 需 `confirm:true`）

### ❌ 编辑器 · 核心 / 状态 / 项目（7）
`editor_get_state` · `editor_ping` · `editor_redo` · `editor_undo`
`project_get_info` · `project_get_setting` · ⚠ `project_set_setting`

### ❌ 编辑器 · 场景（10）
⚠ `scene_close` · `scene_get_dependencies` · `scene_get_tree` · `scene_list_open`
⚠ `scene_new` · `scene_open` · ⚠ `scene_pack` · ⚠ `scene_reload`
`scene_save` · ⚠ `scene_save_as`

### ❌ 编辑器 · 节点（20）
`node_add` · `node_add_to_group` · ⚠ `node_call_method` · `node_change_type`
⚠ `node_delete` · `node_duplicate` · `node_find` · `node_get_children`
`node_get_path` · `node_get_property` · `node_instantiate_scene` · `node_list_groups`
`node_list_properties` · `node_move_child` · `node_remove_from_group` · `node_rename`
`node_reparent` · `node_set_editable_instance` · `node_set_owner` · `node_set_property`

### ❌ 编辑器 · 资源（8）
⚠ `resource_create` · ⚠ `resource_duplicate` · `resource_get_import_settings` · `resource_get_property`
`resource_load` · ⚠ `resource_save` · ⚠ `resource_set_import_settings` · ⚠ `resource_set_property`

### ❌ 编辑器 · 文件系统（4）
`filesystem_create_dir` · `filesystem_list` · ⚠ `filesystem_move` · `filesystem_scan`

### ❌ 编辑器 · 内省 / 文档 / 选择 / 截图（8）
`class_reference` · `classdb_get_class` · `docs_search` · `main_screen_get`
`main_screen_set` · `screenshot_editor` · `selection_get` · `selection_set`

### ❌ 编辑器 · 项目设置 / InputMap / 导出 / 测试（12）
⚠ `editorsettings_get_set` · ⚠ `inputmap_add_action` · ⚠ `inputmap_add_event` · ⚠ `inputmap_erase_action`
`inputmap_list` · ⚠ `project_add_autoload` · ⚠ `project_add_export_preset` · `project_list_settings`
⚠ `project_remove_autoload` · ⚠ `project_set_main_scene` · `test_detect` · `test_list`

### ❌ 编辑器 · 信号（6）
`signal_add_user_signal` · `signal_connect` · `signal_disconnect` · ⚠ `signal_emit`
`signal_list` · `signal_list_connections`

### ❌ 编辑器 · UI / Control / 主题（11）
`container_add_child` · `control_create` · `control_set_anchors` · `control_set_layout_preset`
`control_set_size_flags` · `control_set_theme` · ⚠ `theme_create` · ⚠ `theme_set_color`
⚠ `theme_set_constant` · ⚠ `theme_set_font` · ⚠ `theme_set_stylebox`

### ❌ 编辑器 · 动画 / AnimationTree（14）
`anim_add_track` · `anim_create` · ⚠ `anim_delete` · `anim_get_track_keys`
`anim_insert_key` · `anim_list` · `anim_player_create` · `anim_remove_key`
`anim_set_length` · `anim_set_loop` · `anim_statemachine_add_state` · `anim_statemachine_add_transition`
`anim_tree_add_node` · `anim_tree_create`

### ❌ 编辑器 · 音频总线（6）
⚠ `audio_bus_add` · ⚠ `audio_bus_add_effect` · ⚠ `audio_bus_set_volume` · `audio_player_create`
⚠ `audio_set_bus_layout` · `audio_set_stream`

### ❌ 编辑器 · 物理 / Body / 关节（12）
`area_set_gravity` · `area_set_monitoring` · `body_create` · `body_set_collision_layer`
`body_set_collision_mask` · `body_set_physics_material` · `collisionpolygon_add` · `collisionshape_add`
`joint_create` · `joint_set_bodies` · ⚠ `physics_set_gravity` · `rigidbody_set_properties`

### ❌ 编辑器 · 3D 空间 / 光照 / 环境（10）
`camera_create` · `csg_create` · ⚠ `environment_create` · ⚠ `environment_set_sky`
`light_create` · `mesh_set_surface_material` · `meshinstance_create` · `navagent_configure`
`navregion_create` · ⚠ `primitive_mesh_create`

### ❌ 编辑器 · Shader / 材质（5）
⚠ `shader_create` · ⚠ `shader_set_code` · `shadermaterial_create` · `shadermaterial_set_param`
`shadermaterial_set_shader`

### ❌ 编辑器 · TileMap / TileSet（9）
`tilemap_clear` · `tilemap_get_cell` · `tilemap_set_cell` · `tilemap_set_cells_rect`
`tilemaplayer_create` · ⚠ `tileset_add_source` · ⚠ `tileset_add_tile` · ⚠ `tileset_create`
⚠ `tileset_set_tile_collision`

### ❌ 编辑器 · 粒子（6）
`particles_create` · `particles_set_amount` · `particles_set_emitting` · `particles_set_lifetime`
`particles_set_process_material` · `particles_set_texture`

### ✅ 运行时 · 日志 / 状态 / 断言 / 输入 / 截图（30）
`runtime_anim_get_state` · ⚠ `runtime_anim_play` · ⚠ `runtime_anim_stop` · `runtime_assert_node_state`
`runtime_assert_perf` · `runtime_assert_scene_structure` · `runtime_assert_screen_text` · `runtime_audio_capture`
`runtime_await_condition` · ⚠ `runtime_call_method` · ⚠ `runtime_emit_signal` · `runtime_get_log`
`runtime_get_monitors` · `runtime_get_property` · `runtime_get_tree` · ⚠ `runtime_inject_input`
⚠ `runtime_node_add` · ⚠ `runtime_node_remove` · `runtime_peer_stop` · `runtime_peers_digest`
`runtime_read_state` · `runtime_screenshot` · `runtime_screenshot_diff` · `runtime_screenshot_save`
⚠ `runtime_seed_rng` · ⚠ `runtime_set_property` · `runtime_spawn_peers` · `runtime_state_digest`
⚠ `runtime_step_frames` · ⚠ `runtime_time_scale`

### ✅ 调试器 DAP · GDScript（15）
`dbg_attach` · `dbg_continue` · `dbg_data_breakpoints` · ⚠ `dbg_evaluate`
⚠ `dbg_goto` · `dbg_launch` · `dbg_restart` · `dbg_scopes`
`dbg_set_breakpoints` · `dbg_set_exception_breakpoints` · ⚠ `dbg_set_variable` · `dbg_stack_trace`
`dbg_step` · `dbg_variables` · `dbg_watch`

### ❌ 调试器 DAP · C#（13）
`cs_dbg_attach` · `cs_dbg_continue` · ⚠ `cs_dbg_evaluate` · `cs_dbg_launch`
`cs_dbg_restart` · `cs_dbg_scopes` · `cs_dbg_set_breakpoints` · `cs_dbg_set_exception_breakpoints`
⚠ `cs_dbg_set_variable` · `cs_dbg_stack_trace` · `cs_dbg_step` · `cs_dbg_variables`
`cs_dbg_watch`

### ❌ 语言服务 LSP · GDScript（20）
`gd_call_hierarchy` · `gd_code_action` · `gd_completion` · `gd_declaration`
`gd_definition` · `gd_diagnostics` · `gd_document_color` · `gd_document_highlight`
`gd_document_link` · `gd_document_symbols` · `gd_folding_ranges` · `gd_formatting`
`gd_hover` · `gd_implementation` · `gd_references` · ⚠ `gd_rename`
`gd_semantic_tokens` · `gd_signature_help` · `gd_type_definition` · `gd_workspace_symbols`

### ❌ 语言服务 LSP · C#（10）
`cs_code_action` · `cs_completion` · `cs_definition` · `cs_diagnostics`
`cs_document_symbols` · `cs_hover` · `cs_references` · ⚠ `cs_rename`
`cs_signature_help` · `cs_workspace_symbols`

### ✅ 知识检索 · 符号 / 用法 / 文档（4）
`example_snippet` · `find_symbol` · `find_usages` · `project_search`

### ❌ 进程 / CLI / 诊断（8）
`breakpoint_doctor` · `breakpoint_ports` · `godot_launch_editor` · `godot_output`
`godot_run_managed` · `godot_run_project` · `godot_stop` · `godot_version`

### ❌ 版本控制（12）
`vcs_add` · `vcs_blame` · `vcs_branch_create` · `vcs_branch_list`
`vcs_commit` · `vcs_diff` · `vcs_log` · ⚠ `vcs_restore`
`vcs_show` · ⚠ `vcs_stash` · `vcs_status` · `vcs_switch`

### ❌ 桌游 · 棋盘 / 卡牌 / 棋块（14）
⚠ `board_create` · `board_place` · ⚠ `board_tile_create` · `board_tile_place`
`card_deck_from_table` · `card_hand_layout` · `card_instance` · `card_set_face`
⚠ `card_template_create` · ⚠ `interact_add_drop_zone` · ⚠ `interact_make_draggable` · `piece_instance`
`piece_move` · ⚠ `piece_template_create`

### ❌ 资源生成 · 贴图 / 图标 / 模型 / 音效（7）
⚠ `asset_gen_audio_sfx` · `asset_gen_configure` · `asset_gen_icon` · ⚠ `asset_gen_model`
⚠ `asset_gen_placeholder` · `asset_gen_sprite` · `asset_gen_texture`

### ❌ 网络 · 联机脚手架（7）
`mp_add_spawner` · `mp_add_synchronizer` · ⚠ `mp_scaffold_lobby` · `mp_set_authority`
⚠ `mp_setup_enet_peer` · ⚠ `mp_setup_webrtc_peer` · ⚠ `mp_wire_rpc`

### ❌ 后端 · 脚手架（5）
⚠ `auth_scaffold` · ⚠ `backend_configure` · `backend_detect` · ⚠ `cloudsave_scaffold`
⚠ `leaderboard_scaffold`

### ❌ 录制 / 音频分析（2）
`audio_analyze` · `godot_record`
