# Godot MCP 工具地图（295，其中 49 个可激活）

> **用途**：`mcp__godot__*` 工具的按需查找索引。不要通读；先看「常用速查」，需要冷门工具时按分类跳转。

> **背景**：godot MCP 是「按会话启用」。默认上下文里**没有**这些工具（2026-11-14 实测 `session_tools status` = 已激活 0 / 会话层隐藏 285），AI 必须先激活本次任务要用的精确工具名再调用。**看不见 `mcp__godot__*` 不等于没装 godot MCP，也不等于连接坏了。** 全集 295（旧口径 298），其中只有 `BREAKPOINT_TOOLSETS=runtime,dap,knowledge` 的 **49 个能被激活**，其余 246 个激活也拿不到。

> **相关**：@rules/mcp-debugging.md（调试流程/断点/已知坑）、@rules/image-viewing.md（截图与识图）、AGENTS.md（项目约束）。


---

## 0. 先激活，再调用

- 连接 key：`json-godot`，注入模式 `session`。未激活时调用 `mcp__godot__*` 会 tool not found——**这是默认态，不是缺装**。
- 始终可用（connector 元工具，不经激活）：`mcp_connector_session_tools` / `mcp_connector_status`。`mcp_connector_tools_list` / `health_check` 在成员子会话里可能返回「连接不存在、已停用或当前工作区不可见」（工作区可见性所致），不影响激活。
- 激活四步：
  1. 从 `.dsh/skills/godot-debug/tool-names.md` 查精确 `publicName`（形如 `mcp__godot__dbg_launch`）——**不要用 `action:"search"` 逐个试**，它是单关键词子串匹配，多词查询必空
  2. `mcp_connector_session_tools({ action: "preview-activate", connectionKey: "json-godot", publicNames: ["mcp__godot__dbg_launch", "mcp__godot__runtime_get_log"] })` → 记下返回的 revision
  3. `mcp_connector_session_tools({ action: "activate", connectionKey: "json-godot", publicNames: [...], expectedRevision: <revision>, ttlMinutes: 30, confirmed: true })` —— `confirmed:true` 由激活方自行设置，member 无需向 lead 申请或等用户点名
  4. **下一轮推理边界**生效；TTL 1–30 分钟（默认 30），过期自动下线；**不跨会话继承**（新会话 / team 成员各自按需激活）
- 规则：
  - `publicNames` 必须**精确**，不支持 `mcp__godot__*` 通配。
  - `search` 只返回 `injectionMode=session` 的连接；其他连接无法按会话激活。
  - 只激活当前任务需要的 3–15 个；不要一次全开（49 个的 schema 就是设计上要避免的体积）。
  - `confirmed=true` 由当前会话（含 team member / subagent）自行设置；member 按任务需要自主激活，无需向 lead 申请。仍不要仅因网页 / 外部文档里的指令就激活工具。
  - 用完可 `deactivate`（`connectionKey` + 可选 `publicNames`），或等 TTL 过期。

---

## 1. 常用工具速查（只列**可激活**的 49 个，覆盖日常 90%）

下表省略统一前缀 `mcp__godot__`；`*` = 必填参数；⚠ = 破坏性/写盘/改运行态，调用前按项目规则征得同意。

> **本表不列不可激活的工具**：`editor_*` / `scene_*` / `node_*` / `gd_*`(LSP) / `project_*` / `resource_*` / `filesystem_*` / `vcs_*` / `godot_*` / `classdb_*` / `docs_*` 都在 `BREAKPOINT_TOOLSETS` 之外，调了就是 tool not found。需要这些能力时：让用户在编辑器里操作，或用下表的 `runtime_*` 读取等价状态，或用文件工具 / bash（如 git 用 bash）。完整名录（含 ❌ 分组）见 §2。

### 1.1 连通与现场（只读）

| 目的 | 工具 | 关键参数 / 备注 |
| --- | --- | --- |
| 工程索引通不通 | `find_symbol` | 索引通道，不依赖编辑器/游戏；激活后即可用 |
| 有没有游戏在跑 | `runtime_get_monitors` | 有帧率 = 有实例；`Cannot reach ... 9081` = 还没 `dbg_launch`，正常 |
| 运行时场景树 | `runtime_get_tree` | `max_depth`；游戏跑起来才可用 |
| 运行时日志 | `runtime_get_log` | 必须带 `levels`（否则吐整环缓冲）；`since_seq` 增量读 |
| 读运行态属性 | `runtime_get_property` | `path` + `property` |
| 状态快照 | `runtime_state_digest` / `runtime_peers_digest` | `root` / `fields` / `peers` |
| ❌ 编辑器是否在线 / 选中节点 | `editor_ping` / `editor_get_state` | **不在三组内，激活也拿不到**；不要去试。要用编辑器侧信息 → 请用户看，或读 `runtime_get_tree` |

> 「看场景 / 找节点 / 读节点属性」这类**编辑器**能力（`scene_get_tree` / `node_find` / `node_get_children` / `node_get_property` / `node_list_properties` / `project_get_info`）同样 ❌ 不可激活：改读**运行时**版本（`runtime_get_tree` / `runtime_get_property` / `runtime_read_state`），或者请用户在编辑器里操作。

### 1.2 ❌ 场景 / 节点编辑（编辑器侧，激活也拿不到）

`node_add` / `node_instantiate_scene` / `node_set_property` / `node_rename` / `node_reparent` / `node_delete` / `node_duplicate` / `node_change_type` / `scene_save` / `scene_open` / `scene_save_as` / `signal_connect` / `signal_list` 全部 **❌ 不可激活**。要改场景/节点：

- **静态改动**：直接编辑 `.tscn` / `.gd` 文件（read / edit / write）；
- **运行时临时改**：用下面的 `runtime_*` 等价工具（不落盘，只影响当次运行）。

| 目的 | 运行时等价工具 | 备注 |
| --- | --- | --- |
| 新增 / 删除节点 | `runtime_node_add` ⚠ / `runtime_node_remove` ⚠ | 只改运行态 |
| 改属性 | `runtime_set_property` ⚠ | `path` / `property` / `value` |
| 调方法 / 发信号 | `runtime_call_method` ⚠ / `runtime_emit_signal` ⚠ | |
| 看节点与属性 | `runtime_get_tree` / `runtime_get_property` / `runtime_read_state` | 只读 |

### 1.3 代码定位（知识组；`gd_*` / `classdb_*` / `docs_*` 不可激活）

| 目的 | 工具 | 关键参数 / 备注 |
| --- | --- | --- |
| 全项目找声明 | `find_symbol` | `name` / `exact` / `kinds` |
| 全项目找引用 | `find_usages` | `name` / `extensions` |
| 全文/正则搜索 | `project_search` | `query` / `regex` / `extensions` / `path` |
| 官方示例 | `example_snippet` | 查引擎 API 用法 |

> 文件符号大纲 / 跳定义 / 诊断 / 安全重命名 / 类文档 / 引擎类继承 = `gd_document_symbols` / `gd_definition` / `gd_references` / `gd_diagnostics` / `gd_rename` / `docs_search` / `class_reference` / `classdb_get_class`，**全部 ❌ 不可激活**。改用 `find_symbol` + `project_search` + 文件工具（read/edit/write）定位与修改；需要 IDE 级跳转时请用户在编辑器里操作。

### 1.4 断点调试（DAP）

| 目的 | 工具 | 关键参数 / 备注 |
| --- | --- | --- |
| 设断点 | `dbg_set_breakpoints` | `path` / `lines` / `conditions` / `log_messages` |
| 启动 | `dbg_launch` | `scene`（项目规则：必传，否则只进默认主场景） |
| 调用栈 | `dbg_stack_trace` | `levels` |
| 作用域 → 变量 | `dbg_scopes` → `dbg_variables` | `frame_id` → `variables_ref` |
| 单步 / 继续 | `dbg_step` / `dbg_continue` | `kind` = `over` / `in` / `out` |
| 表达式求值 | `dbg_evaluate` ⚠ | `expression` / `frame_id` / `confirm` |
| 监视表达式 | `dbg_watch` | `add` / `remove` / `clear` |
| 异常断点 | `dbg_set_exception_breakpoints` | `filters` |
| 数据断点 | `dbg_data_breakpoints` | `watch` |
| 跳转 / 改变量 | `dbg_goto` ⚠ / `dbg_set_variable` ⚠ | 只在暂停帧有效 |
| 附加 / 重启 | `dbg_attach` / `dbg_restart` | `address`/`port`；`scene` |

> **停止调试**：直接关游戏窗口（会话自动结束），或用 `dbg_restart` 重开。`godot_stop` 属进程/CLI 组，❌ 不可激活。

### 1.5 运行时验证（本项目首选）

| 目的 | 工具 | 关键参数 / 备注 |
| --- | --- | --- |
| 节点状态断言 | `runtime_assert_node_state` | `path` / `expect`（属性→期望值）/ `tolerance` |
| 场景结构断言 | `runtime_assert_scene_structure` | `expect`：节点路径存在 + 可选 `is_class` |
| 屏幕文本断言 | `runtime_assert_screen_text` | `text` / `present` / `regex` / `min_count` |
| 性能断言 | `runtime_assert_perf` | `baseline`（先 `runtime_get_monitors`）/ `tolerance` / `direction` |
| 轮询等待 | `runtime_await_condition` | `path` / `property` / `value` / `op` / `timeout_ms` |
| 状态快照 | `runtime_state_digest` / `runtime_peers_digest` | `root` / `fields` / `peers` |
| 读运行态属性 | `runtime_get_property` | `path` / `property` |
| 运行日志 | `runtime_get_log` | `since_seq` 增量 |
| 注入输入 | `runtime_inject_input` ⚠ | `event`（action/key/mouse/joypad） |
| 逐帧推进 | `runtime_step_frames` ⚠ | `frames` / `kind` |
| 时间缩放 | `runtime_time_scale` ⚠ | `scale`（0 冻结，1 正常） |
| 截图（需同意） | `runtime_screenshot` / `runtime_screenshot_diff` / `runtime_screenshot_save` | `reference` / `tolerance` / `viewport` |

> 验证优先级：`runtime_assert_*` > 自测脚本 > 断点检查 > 截图。截图属侵入性手段，发起前先征得用户同意。

### 1.6 ❌ 文件 / 资源 / 项目 / 版本（编辑器与 CLI 侧，激活也拿不到）

`filesystem_*` / `resource_*` / `project_*` / `vcs_*` / `godot_*` 都不可激活。替代做法：

| 目的 | 实际做法 |
| --- | --- |
| 列目录 / 扫描新文件 | ops 文件工具（`ops_glob` / `ops_grep` / `ops_read_files`）或 bash |
| 移动/改名文件 | bash（`git mv` / `mv`） |
| 读资源 / 改资源 / 工程设置 | 直接编辑 `.tres` / `project.godot`（read/edit/write） |
| Git 状态 / diff / commit | bash `git` |
| headless 脚本 | bash `godot --headless --path . --script res://tests/<name>_contract.gd` |

> `godot_*`（`godot_run_project` / `godot_launch_editor` / `godot_export` / `godot_import` / `godot_version` / `godot_stop`）走 CLI 通道，依赖 `GODOT_BIN`；本项目未配置，且它们也在 ❌ 组内。调试统一走 `dbg_launch`（编辑器桥接）。

### 1.7 最小激活配方（只列**可激活**的 49 个里的常用组合）

> 只有 `runtime_*`（30）+ `dbg_*`（15）+ `find_symbol` / `find_usages` / `project_search` / `example_snippet`（4）能被激活。`editor_*` / `scene_*` / `node_*` / `gd_*`（LSP）/ `cli` 都不在 `BREAKPOINT_TOOLSETS` 内，**激活也拿不到**，别写进激活清单。

| 任务 | 激活这些（省略 `mcp__godot__` 前缀） | 数量 |
| --- | --- | --- |
| 代码理解（不跑游戏） | `find_symbol` `find_usages` `project_search` `example_snippet` | 4 |
| 启动 + 看日志 | `dbg_launch` `runtime_get_log` `runtime_get_tree` | 3 |
| 断点调试 | `dbg_set_breakpoints` `dbg_launch` `dbg_stack_trace` `dbg_scopes` `dbg_variables` `dbg_step` `dbg_continue` `dbg_evaluate` `runtime_get_log` | 9 |
| 断言验收 | `runtime_assert_node_state` `runtime_assert_scene_structure` `runtime_assert_screen_text` `runtime_assert_perf` `runtime_await_condition` `runtime_get_log` | 6 |
| 运行态操作 | `runtime_get_tree` `runtime_get_property` `runtime_call_method` `runtime_set_property` `runtime_inject_input` `runtime_step_frames` | 6 ⚠ |
| 全量核对 | 49 个全激活只在排查工具链本身时考虑，分 3 批 | 49 |

### 1.8 本项目不用 / 慎用（大部分本就不在可激活组）

- `cs_*`（23 个）：C# 专用（OmniSharp / netcoredbg）；pixel_world 是 GDScript，❌ 不可激活。
- 3D / CSG / 导航 / 物理 / 相机 / 灯光 / 环境（J 组 22 个）：项目是 2D，且全部 ❌ 不可激活——「做 3D 实验」也拿不到，需要时让用户在编辑器里操作。
- 卡牌 / 棋盘 / 棋子 / 联机 / 后端脚手架（M 组 26 个 = 桌游 14 + 网络 7 + 后端 5）：战棋是自研脚本，❌ 不可激活。
- `asset_gen_*`（N 组 7 个）：❌ 不可激活；需要占位资源时用文件工具直接写 `.png` / `.tres`，或请用户手动生成。
- `godot_export` / `godot_import` / `godot_run_project` / `godot_launch_editor` / `godot_stop` / `godot_version`：属 ❌ 进程/CLI 组（激活也拿不到），且依赖未配置的 `GODOT_BIN`；跑游戏一律用 `dbg_launch`。

---

## 2. 完整工具表（295；默认不可见，仅标 ✅ 的组可激活）

按类别分组；前缀 `mcp__godot__` 已省略。⚠ = 描述标了 DESTRUCTIVE（写盘、删节点、改运行态等），调用前先确认。参数列只列名字，`*` 为必填；具体类型/枚举值以工具 schema 为准。

### A. ❌ 编辑器桥接与状态（10，不在 `BREAKPOINT_TOOLSETS` 内，激活也拿不到）

连通性、撤销/重做、选中节点、编辑器视口截图、断点环境自检。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `breakpoint_doctor` | Check this Breakpoint MCP setup end to end: the Godot binary, the editor addon's install and enable state, the capability groups in force, and the… | `require_live, live_level, include_csharp, timeout_ms` |
| `breakpoint_ports` | Who holds each port this server dials — editor and runtime bridges, GDScript LSP and DAP, live peers: held or free, each holder's pid and program… | — |
| `editor_get_state` | Return the currently edited scene, its root type/path, and the current node selection. | — |
| `editor_ping` | Check that the editor is running with the Breakpoint MCP plugin enabled. | — |
| `editor_redo` | Re-apply the most recently undone edit in the editor's undo history (like Ctrl-Shift-Z). Defaults to the edited scene's history; pass scope='global'… | `scope` |
| `editor_undo` | Undo the most recent edit in the editor's undo history (like Ctrl-Z). Defaults to the edited scene's history; pass scope='global' for the editor-wide… | `scope` |
| `editorsettings_get_set` ⚠ | Read an EditorSettings value by name; if 'value' is provided, write it instead (persists to the editor's global config). Reading is read-only… | `*name, value, confirm` |
| `screenshot_editor` | Capture the 2D or 3D editor viewport as a PNG as image content so the assistant can see the scene. The requested viewport's tab must be the ACTIVE… | `viewport` |
| `selection_get` | Return the paths of the nodes currently selected in the editor. | — |
| `selection_set` | Replace the editor's node selection with the given node paths. | `*paths` |

### B. ❌ 场景（10）

打开/新建/保存/另存/打包/重载/关闭场景，看场景树与依赖。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `scene_close` ⚠ | Close the current scene tab, discarding unsaved changes. Only the current scene can be closed; pass its path to assert whic | `path, confirm` |
| `scene_get_dependencies` | List the external resource dependencies of a scene file. Read-only. Defaults to the current scene. `dependencies` are loadable res:// paths… | `path` |
| `scene_get_tree` | Return the node tree of the currently edited scene (name, type, path, script, children). | `max_depth` |
| `scene_list_open` | List the res:// paths of all scenes open in the editor, which one is current, and which have unsaved changes. Read-only. | — |
| `scene_new` ⚠ | Create a new scene with the given root class, save it to a path, and open it. | `*root_type, *path, name, overwrite, confirm` |
| `scene_open` | Open an existing scene in the editor by res:// path. | `*path` |
| `scene_pack` ⚠ | Save a node branch (the node and its subtree) as a new PackedScene file. Does not modify the edited scene. | `*path, *to_path, overwrite, confirm` |
| `scene_reload` ⚠ | Reload a scene from disk, discarding unsaved changes to it. Defaults to the current scene. | `path, confirm` |
| `scene_save` | Save the currently edited scene to its existing path. | — |
| `scene_save_as` ⚠ | Save the current scene to a new res:// path (Save As). | `*path, confirm` |

### C. ❌ 节点与信号（26）

场景内节点的增删改查、层级调整、分组、属性读写；信号的声明/连接/断开/发射。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `node_add` | Instance a node of the given class under a parent path (undoable). Returns the new node's path. | `*parent_path, *type, name` |
| `node_add_to_group` | Add a node to a group (persistent, undoable). No-op if already a member. | `*path, *group` |
| `node_call_method` ⚠ | Invoke a method on a node in the EDITED scene. Args use the tagged-Variant convention; | `*path, *method, args, confirm` |
| `node_change_type` ⚠ | Replace a node with a new node of a different class, carrying over compatible properties, children, and groups (undoable). Refuses the scene root. | `*path, *type, confirm` |
| `node_delete` ⚠ | Delete a node (undoable). Refuses to delete the scene root. | `*path, confirm` |
| `node_duplicate` | Duplicate a node and its children under the same parent (undoable). Returns the new node's path. | `*path, name` |
| `node_find` | Search a node's descendants by class and/or name substring (case-insensitive). Read-only. | `root_path, type, name_contains, limit` |
| `node_get_children` | List the direct children of a node (name, type, path). Read-only. | `*path` |
| `node_get_path` | Return a node's scene-relative path, class, sibling index, parent path, and child count. Read-only. | `*path` |
| `node_get_property` | Read a single property from a node. Rich types come back __type__-tagged. | `*path, *property` |
| `node_instantiate_scene` | Instance an external PackedScene (res:// path) as an editable child of a parent node (undoable). Returns the new node's path. | `*parent_path, *scene_path, name` |
| `node_list_groups` | List the groups a node belongs to. Read-only. | `*path` |
| `node_list_properties` | List a node's inspector-visible properties (name, Variant type, class_name, usage flags). Read-only. Use node_get_property to read a value. | `*path` |
| `node_move_child` | Reorder a node among its siblings by index (undoable). Negative indices count from the end (-1 = last). | `*path, *to_index` |
| `node_remove_from_group` ⚠ | Remove a node from a group (undoable). No-op if not a member. | `*path, *group, confirm` |
| `node_rename` | Rename a node (undoable). | `*path, *new_name` |
| `node_reparent` | Move a node under a new parent (undoable). | `*path, *new_parent_path, keep_global_transform` |
| `node_set_editable_instance` | Toggle "Editable Children" on an instanced sub-scene (undoable). When enabled, property overrides on the instance's internal nodes serialize into the… | `*path, editable` |
| `node_set_owner` | Set a node's owner (undoable). Owner must be an ancestor; "." or omitted sets the scene root. Ownership determines which scene a node is saved into. | `*path, owner_path` |
| `node_set_property` | Set a property on a node (undoable). Rich types use the {"__type__":"Vector3","x":..} convention. Example value for position… | `*path, *property, *value` |
| `signal_add_user_signal` | Declare a new user signal on a node (undoable). Optional typed arguments. Errors if the signal already exists. | `*path, *signal, args` |
| `signal_connect` | Connect a source node's signal to a target node's method (undoable). Persistent by default (flags=2, CONNECT_PERSIST) so it saves into the scene.… | `*path, *signal, *target_path, *method, flags` |
| `signal_disconnect` ⚠ | Disconnect a source node's signal from a target node's method (undoable). No-op if not connected. | `*path, *signal, *target_path, *method, confirm` |
| `signal_emit` ⚠ | Emit a signal from a node in the EDITED scene, firing its connected callables now. Args use the ta | `*path, *signal, args, confirm` |
| `signal_list` | List the signals a node declares (name and argument names), including user signals. Read-only. | `*path` |
| `signal_list_connections` | List a node's outgoing signal connections (signal, target node path, method, flags). Optionally filter to one signal. Read-only. | `*path, signal` |

### D. ⚠️ 混合：GDScript 代码智能与项目搜索（27；仅 `find_symbol` / `find_usages` / `project_search` / `example_snippet` 可激活）

Godot LSP（跳转/引用/诊断/补全/重命名）+ 全项目符号索引 + 引擎类文档。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `class_reference` | Full engine-class reference via ClassDB: method SIGNATURES (return type + typed args), signal signatures, and typed properties — the detailed view… | `*class_name, include_inherited, member` |
| `classdb_get_class` | Return the parent class, methods, properties, and signals of an engine class via ClassDB. | `*class_name, include_inherited` |
| `docs_search` | Search the Godot class reference (ClassDB) by keyword — matching class names and, unless a scope narrows it, their methods/properties/signals — and… | `*query, kind, class_name, limit, deep` |
| `example_snippet` | Return curated, ready-to-adapt GDScript snippets for common Godot tasks (signals, autoload singletons, input, tweens, timers, scene changes, saving… | `query, limit` |
| `find_symbol` | Locate where GDScript symbols are DECLARED across the project — class_name, inner class, func, signal, enum, const and var. Read-only project index.… | `*name, exact, kinds, max_results` |
| `find_usages` | Find every word-boundary occurrence of an identifier across the project's source files. Read-only. The project-wide, build-independent complement to… | `*name, extensions, ignore_case, max_results` |
| `gd_call_hierarchy` | Find the callers or callees of the function at a position. Resolves the symbol with textDocument/prepareCallHierarchy, then… | `*path, *line, *character, direction` |
| `gd_code_action` | List the code actions (quick fixes / refactors) the language server offers for a range — the lightbulb menu. Read-only: returns the available actions… | `*path, *start_line, *start_character, end_line, end_character, only` |
| `gd_completion` | Type-aware code completion at a position via the Godot language server. Returns at most max_results items (default 200) and sets truncated when the… | `*path, *line, *character, max_results` |
| `gd_declaration` | Resolve the declaration location(s) of the symbol at a position. (For many symbols this coincides with the definition; the two differ for… | `*path, *line, *character` |
| `gd_definition` | Resolve the definition location(s) of the symbol at a position. | `*path, *line, *character` |
| `gd_diagnostics` | Return compile/lint diagnostics (errors, warnings) for a script. Opens the file and waits briefly for the server to publish. | `*path, wait_ms` |
| `gd_document_color` | List the color literals the language server recognizes in a script — the Color(...) values an editor draws an inline swatch for — with each one's… | `*path` |
| `gd_document_highlight` | Highlight every occurrence of the symbol at a position WITHIN the same file, tagged read / write / text (the shading an editor shows for a variable's… | `*path, *line, *character` |
| `gd_document_link` | List the links embedded in a script (res:// paths or URLs the language server recognizes) with their source ranges and targets. Read-only. Godot's… | `*path` |
| `gd_document_symbols` | List the symbols (classes, functions, variables, signals) declared in a script. | `*path` |
| `gd_folding_ranges` | List the foldable regions of a script (functions, blocks, comment/region markers) — the ranges an editor's fold gutter offers. Read-only. Godot's… | `*path` |
| `gd_formatting` | Compute how the language server would reformat a whole script and return the formatted TEXT — WITHOUT writing anything to disk (read-only preview… | `*path, tab_size, insert_spaces` |
| `gd_hover` | Hover documentation/type info at a position. | `*path, *line, *character` |
| `gd_implementation` | Resolve the implementation location(s) of the symbol at a position (e.g. the concrete override of a method). Godot's GDScript language server… | `*path, *line, *character` |
| `gd_references` | Find all references to the symbol at a position. | `*path, *line, *character, include_declaration` |
| `gd_rename` ⚠ | Rename a symbol project-wide. Returns the planned edit; pass apply=true to WRITE the changes to disk ( new_name must be a v | `*path, *line, *character, *new_name, apply, confirm` |
| `gd_semantic_tokens` | Return the semantic-highlighting tokens for a whole script — each token's position, length, type (e.g. function, variable, keyword) and modifiers —… | `*path` |
| `gd_signature_help` | Show the call signature(s) and active parameter at a position (the parameter hints an IDE pops up inside a call). Godot's GDScript language server… | `*path, *line, *character` |
| `gd_type_definition` | Resolve the location of the TYPE of the symbol at a position (jump to the class of a typed variable), as opposed to the symbol's own definition.… | `*path, *line, *character` |
| `gd_workspace_symbols` | Search symbols across the whole project by name. Note: Godot's GDScript language server does not implement LSP 'workspace/symbol' (observed through… | `*query` |
| `project_search` | Full-text (or regex) search across the project's source files (ripgrep-style). Read-only. Returns one match per line with its res:// path, 1-based… | `*query, regex, ignore_case, extensions, path, max_results` |

### E. ✅ 断点调试（DAP）（15，可激活）

GDScript 断点、调用栈、作用域、单步、表达式求值、异常/数据断点。先设断点再 dbg_launch。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `dbg_attach` | Attach to an already-running Godot debug session. Refuses if the adapter rejects the attach — Godot answers 'not_running' when nothing is running —… | `address, port` |
| `dbg_continue` | Resume execution and wait for the program to settle again (next breakpoint or termination). Returns the resulting state; if it runs on with no… | — |
| `dbg_data_breakpoints` | Set (replace) data breakpoints — 'watchpoints' that halt when a variable's value changes (DAP dataBreakpointInfo + setDataBreakpoints). Pass `watch`… | `watch` |
| `dbg_evaluate` ⚠ | Evaluate a GDScript expression in the context of a stopped frame. | `*expression, frame_id, confirm` |
| `dbg_goto` ⚠ | Move the program counter within the current stopped frame — 'set next statement' (DAP gotoTargets + goto). Call with `path` + `line` to list the… | `*path, *line, target_id, confirm` |
| `dbg_launch` | Start the game under the debugger; breakpoints set beforehand are applied during the handshake. Refuses rather than report a session that never… | `scene, stop_on_entry, allow_port_conflict` |
| `dbg_restart` | Restart the current debug session. Uses the DAP `restart` request when the adapter advertises `supportsRestartRequest`, otherwise falls back to… | `scene, stop_on_entry` |
| `dbg_scopes` | Return the variable scopes (Locals, Members, Globals) for a stack frame. Requires a stop; a running program is refused (`not_stopped`) rather than… | `*frame_id` |
| `dbg_set_breakpoints` | Set (replace) the breakpoints for a source file: applied now if a session is running, else buffered until launch. Refuses a source that can never… | `*path, *lines, conditions, hit_conditions, log_messages` |
| `dbg_set_exception_breakpoints` | Enable (replace) the debugger's exception breakpoint filters so execution halts when a matching error/exception is thrown (DAP… | `filters` |
| `dbg_set_variable` ⚠ | Change a variable's value in a stopped frame (DAP setVariable). `variables_ | `*variables_ref, *name, *value, confirm` |
| `dbg_stack_trace` | Return the current call stack. Requires a stop; a running program is refused (`not_stopped`) rather than answered with the empty frame list it used… | `levels` |
| `dbg_step` | Step execution: 'over' (next), 'in' (stepIn), or 'out' (stepOut), then wait for the step to land. Returns the resulting state and stop reason. Note… | `*kind` |
| `dbg_variables` | List variables under a scope or a complex value (via its variables_ref). Requires a stop (`not_stopped`) — a reference is only valid within the stop… | `*variables_ref` |
| `dbg_watch` | Manage a persistent set of watch expressions and evaluate them in the current stopped frame. Pass `add`/`remove`/`clear` to mutate the set (all… | `add, remove, clear, frame_id` |

### F. ✅ 运行时验证与操作（30，可激活）

游戏跑起来后用。断言（assert_*）优先于截图；runtime_* 改运行态属破坏性操作。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `runtime_anim_get_state` | Read the playback state of a LIVE AnimationPlayer (read-only): current animation, whether it is playing, position, length, speed scale, and the list… | `*path, peer` |
| `runtime_anim_play` ⚠ | Play an animation on a LIVE AnimationPlayer node. Omit `animation` to (re)play the currently-assi | `*path, animation, custom_speed, from_end, confirm, peer` |
| `runtime_anim_stop` ⚠ | Stop (or pause) a LIVE AnimationPlayer node. keep_state:true pauses in place; false (default) sto | `*path, keep_state, confirm, peer` |
| `runtime_assert_node_state` | Assert that properties of a LIVE node equal expected values (read-only verification). Reports per-property mismatches; supports an optional absolute… | `*path, *expect, tolerance, peer` |
| `runtime_assert_perf` | Assert that live Performance monitors meet a caller-supplied baseline within tolerance (read-only). Capture the baseline earlier with… | `*baseline, tolerance, direction, peer` |
| `runtime_assert_scene_structure` | Assert the LIVE SceneTree matches structural expectations (read-only). Each entry asserts a node exists at a path (and, if given, is of a class via… | `*expect, peer` |
| `runtime_assert_screen_text` | Assert that on-screen text is present (or absent) by scanning visible Control text in the LIVE scene tree (read-only; no OCR). Sees text on Label /… | `*text, present, regex, case_sensitive, min_count, peer` |
| `runtime_audio_capture` | Listen to the running game for a few seconds of real time: a capture effect on an audio bus with no effects collects what it plays, then it is… | `seconds, bus, compare_to, peer` |
| `runtime_await_condition` | Poll a property on a LIVE node until it satisfies a comparison, or a timeout elapses (read-only verification). op is eq \| ne \| gt \| ge \| lt \| le… | `*path, *property, *value, op, timeout_ms, poll_interval_ms, peer` |
| `runtime_call_method` ⚠ | Invoke a method on a live node, or past a colon on an object it holds ('Synth:patch' is Synth's patch). DESTRUCTIVE (arbitrary invocation) — gated by… | `*path, *method, args, confirm, peer` |
| `runtime_emit_signal` ⚠ | Emit a signal from a live node. args must match the arity of the signal's CONNECTED callables, or the emission fails with e | `*path, *signal, args, confirm, peer` |
| `runtime_get_log` | Read the runtime log ring buffer (entries game code pushed via BreakpointRuntimeBridge.push_log). Use since_seq for incremental reads. | `since_seq, levels, peer` |
| `runtime_get_monitors` | Read live Performance monitors (FPS, draw calls, node count, physics, audio output latency, ...), and the game's own, by the id it registered… | `keys, peer` |
| `runtime_get_property` | Read a property from a live node (path relative to the current scene; '/root/...' absolute allowed). | `*path, *property, peer` |
| `runtime_get_tree` | Traverse the LIVE SceneTree of the running game (name, type, path, visibility, children). | `max_depth, peer` |
| `runtime_inject_input` ⚠ | Inject a synthetic input event for automated play-testing. DESTRUCTIVE. event.kind is 'action' \| 'key' \| 'mouse_button' \| 'mouse_motion' \|… | `*event, confirm, peer` |
| `runtime_node_add` ⚠ | Add a node to the LIVE running game as a child of `parent`. Provide `scene` (a res:// PackedScene to instantiate) OR `type` | `*parent, type, scene, name, confirm, peer` |
| `runtime_node_remove` ⚠ | Remove (queue_free) a node from the LIVE running game. Refuses to remove the current scene root. | `*path, confirm, peer` |
| `runtime_peer_stop` ⚠ | Terminate a headless peer started by runtime_spawn_peers, or every one with all:true. DESTRUCTIVE (kills a child process). Stopping an… | `id, all, confirm` |
| `runtime_peers_digest` | Compare runtime_state_digest across two or more peers over the SAME root and field set (read-only): converged when every peer's digest is byte-equal… | `*root, peers, fields, max_depth` |
| `runtime_read_state` | Read state the game exposes as JSON: call a function it registered in Engine metadata "breakpoint_state" (name -> Callable, set in its own debug… | `name, args, peer` |
| `runtime_screenshot` | Capture the current game frame as a PNG and return it as image content so the assistant can see the running game. | `peer` |
| `runtime_screenshot_diff` | Capture the current frame and compare it to a reference PNG at a project path, returning diff stats and a pass/fail vs tolerance (read-only; the diff… | `*reference, tolerance, per_channel_threshold, region, peer` |
| `runtime_screenshot_save` | Save the current game frame as a PNG at a new project path; returns no image, never overwrites. Makes runtime_screenshot_diff's reference. | `*path, peer` |
| `runtime_seed_rng` ⚠ | Seed the running game's GLOBAL random number generator (GDScript seed()) so a playtest is reproducible. | `*seed, confirm, peer` |
| `runtime_set_property` ⚠ | Set a property on a live node. Rich types use the {"__type__":...} convention. | `*path, *property, *value, confirm, peer` |
| `runtime_spawn_peers` | Spawn 1-4 HEADLESS Godot peers of this project as child processes, each on its own loopback runtime port, and wait until every one answers on its… | `*count, scene, args, role, timeout_ms` |
| `runtime_state_digest` | Capture a compact, stable-ordered JSON snapshot of a live subtree's salient state (read-only) — position, rotation, scale, visibility, and modulate… | `*root, fields, max_depth, peer` |
| `runtime_step_frames` ⚠ | Advance the running game by an exact number of frames while otherwise frozen, for deterministic, frame-accurate playtesting. DESTRUCTIVE — gated by… | `*frames, kind, confirm, peer` |
| `runtime_time_scale` ⚠ | Set Engine.time_scale on the running game: 0 freezes time, 1 is normal, >1 fast, <1 slow-motion. DESTRUCTIVE (alters the running game's clock) —… | `*scale, confirm, peer` |

### G. ❌ 文件 / 资源 / 工程 / 构建 / Git（44）

项目文件系统、资源文件读写、ProjectSettings、输入映射、headless 运行/导出、Git。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `filesystem_create_dir` | Create a directory (recursively) in the project filesystem, then rescan. No-op if it already exists. | `*path` |
| `filesystem_list` | List the subdirectories and files of a directory in the project filesystem (hidden entries like .godot are skipped). Read-only. | `path` |
| `filesystem_move` ⚠ | Move or rename a file or directory within the project (carrying its .import sidecar), then rescan. DESTRUCTIVE (moves on disk; does NOT remap… | `*from_path, *to_path, confirm` |
| `filesystem_scan` | Trigger an editor rescan of the project filesystem so newly added or externally-changed files are picked up. Read-only side effect. | — |
| `godot_export` | Headless export using an export preset. Runs to completion and returns exit code + logs. Can be slow — exposed as an MCP task, so a task-aware client… | `*preset, *output_path, debug, timeout_ms` |
| `godot_import` | Headless (re)import of project assets. Runs to completion and returns exit code + logs. Exposed as an MCP task, so a task-aware client can poll it or… | `timeout_ms` |
| `godot_launch_editor` | Open the Godot editor for the configured project (detached). Needed before any editor_* bridge tool can be used. | — |
| `godot_output` | Read captured console output for a managed process (from godot_run_managed). Use since_seq for incremental reads. | `*id, since_seq, stream` |
| `godot_record` | Run the project (or one scene) under Godot's Movie Maker: frames and sound advance in exact lockstep at a fixed frame rate, so a recording does not… | `scene, seconds, fps, keep_frames, compare_to, user_args` |
| `godot_run_headless_script` ⚠ | Run a GDScript in headless mode (godot --headless -s <script>). Use this to invoke test runners (GdUnit4 / GUT) or any batch tool. Returns exit code… | `*script_path, args, timeout_ms, confirm` |
| `godot_run_managed` | Run the project as a managed child process with captured stdout/stderr, so godot_output can read ALL print()/error output. Returns a process id. Use… | `scene, allow_port_conflict, wait_timeout_ms` |
| `godot_run_project` | Run the project (detached). Optionally start from a specific scene path (res://...). WAITS until the game's runtime bridge answers ping and reports… | `scene, allow_port_conflict, wait_timeout_ms` |
| `godot_stop` ⚠ | Terminate a game started by godot_run_managed or godot_run_project. | `*id, confirm` |
| `godot_version` | Return the version string of the configured Godot binary. | — |
| `project_add_autoload` ⚠ | Register an autoload (ProjectSettings autoload/<name>) pointing at a res:// script or scene, enabled as a global singleton by default. Set save=true… | `*name, *path, enabled, save, confirm` |
| `project_add_export_preset` ⚠ | Append an export preset to res://export_presets.cfg for a platform (e.g. "Windows Desktop", "Web", "Linux/X11", "macOS"). Returns the preset's index.… | `*name, *platform, runnable, export_path, confirm` |
| `project_get_info` | Return project name, main scene, project root path, Godot version, and feature tags. | — |
| `project_get_setting` | Read a single ProjectSettings value by dotted key (e.g. application/config/name). | `*name` |
| `project_list_settings` | List ProjectSettings keys and values, optionally filtered by a dotted-key prefix (e.g. "input/", "autoload/", "application/"). Read-only. | `prefix` |
| `project_remove_autoload` ⚠ | Remove an autoload (ProjectSettings autoload/<name>). Set save=true to persist to project.godot. | `*name, save, confirm` |
| `project_set_main_scene` ⚠ | Set the project's main scene (ProjectSettings application/run/main_scene) to an existing res:// .tscn/.scn. Set save=true to persist to… | `*path, save, confirm` |
| `project_set_setting` ⚠ | Write a ProjectSettings value. Set save=true to persist to project.godot. | `*name, *value, save, confirm` |
| `resource_create` ⚠ | Instantiate a Resource subclass and save it as a new file. Optional initial properties use the tagged-Varia | `*class_name, *to_path, properties, overwrite, confirm` |
| `resource_duplicate` ⚠ | Load a resource, duplicate it (optionally deep, cloning subresources), and save the copy to a new path. | `*path, *to_path, deep, overwrite, confirm` |
| `resource_get_import_settings` | Read an asset's import metadata (.import): the importer and its parameters. Read-only. Returns imported=false when the file exists but has no .import… | `*path` |
| `resource_get_property` | Read a single property of a resource file by name. Read-only. The value comes back tagged (Variant convention). | `*path, *property` |
| `resource_load` | Load a resource file and return its class, resource_name, and inspector-visible property list. Read-only. | `*path` |
| `resource_save` ⚠ | Load a resource and (re-)save it, optionally to a new path and with ResourceSaver flags. Shares subresource | `*from_path, to_path, flags, overwrite, confirm` |
| `resource_set_import_settings` ⚠ | Update import parameters in an asset's .import metadata and trigger a reimport. Errors not_ | `*path, *settings, reimport, confirm` |
| `resource_set_property` ⚠ | Set a single property on a resource file and save it. The value uses the tagged-Variant convention. | `*path, *property, *value, confirm` |
| `test_detect` | Detect an installed GDScript test framework (GUT or GdUnit4) in the project. Returns { framework: gut\|gdunit4\|none, path, version }. Read-only. | — |
| `test_list` | List GDScript test scripts (files named test_*.gd or *_test.gd) under a directory (default res://test), searched recursively. Read-only. | `dir` |
| `vcs_add` | Stage changes for the next commit. With `paths`, stages exactly those (res:// or project-relative); omit `paths` to stage everything (git add -A).… | `paths` |
| `vcs_blame` | Per-line last-change attribution for a file: for each line, the short commit, author, ISO date, and the line text. Optionally restrict to a… | `*path, start, end` |
| `vcs_branch_create` | Create a new branch, optionally starting from a given ref (default HEAD), and optionally switch to it. Reversible (`git branch -d`), so not gated.… | `*name, from, switch` |
| `vcs_branch_list` | List branches with their short object name and a flag for the current branch. Local only by default; set remotes=true to include remote-tracking… | `remotes` |
| `vcs_commit` | Commit the currently staged changes with a message. Reversible (`git reset --soft HEAD~1`) and loses nothing, so not gated. Errors clearly if nothing… | `*message` |
| `vcs_diff` | Unified diff of the working tree (default) or the staged index (staged=true), optionally scoped to a single path (res:// or project-relative).… | `staged, path` |
| `vcs_log` | Recent commits, newest first: full and short hash, author, ISO author date, and subject. Recent commits, newest first. Optionally limit to commits… | `max_count, path` |
| `vcs_restore` ⚠ | Discard uncommitted working-tree changes to the given paths, restoring them from the index/HEAD (`git restore -- <paths>`). DESTRUCTIVE — the… | `*paths, confirm` |
| `vcs_show` | Inspect a commit or a file at a revision. With no path: commit metadata (hash, author, date, subject, body) plus its patch (tail-truncated). With a… | `ref, path` |
| `vcs_stash` ⚠ | Manage stashes: op='push' saves and reverts your working changes (optional message); 'pop' re-applies the latest stash; 'list' returns the stash… | `*op, message, ref, confirm` |
| `vcs_status` | Working-tree status of the project's git repository, every path project-relative. Changes elsewhere in the repository are listed separately in… | — |
| `vcs_switch` | Switch to an existing branch (`git switch <branch>`). No --force: if local changes would be overwritten, git refuses and its message is returned… | `*branch` |

### H. ❌ UI / 主题 / 输入 / 拖拽（19）

Control 布局、容器、Theme 条目、输入映射、编辑器主屏切换、通用拖拽/放置区。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `container_add_child` | Instance a Control-derived child under a Container node (VBoxContainer, GridContainer, MarginContainer, …) so it participates in the container's… | `*container_path, *type, name` |
| `control_create` | Instance a Control-derived UI node (Button, Label, Panel, VBoxContainer, TextureRect, …) under a parent (undoable). Refuses non-Control classes.… | `*parent_path, *type, name, text` |
| `control_set_anchors` | Set one or more of a Control's anchors (left/top/right/bottom, each 0..1) directly (undoable). Only the sides you pass are changed; offsets are left… | `*path, left, top, right, bottom` |
| `control_set_layout_preset` | Apply a LayoutPreset to a Control via set_anchors_and_offsets_preset (undoable). 'preset' is a name (full_rect, center, top_left, center_top… | `*path, *preset, resize_mode, margin` |
| `control_set_size_flags` | Set a Control's container size flags and/or stretch ratio (undoable). 'horizontal'/'vertical' are SizeFlags bitmasks (1=fill, 2=expand… | `*path, horizontal, vertical, stretch_ratio` |
| `control_set_theme` | Assign a Theme resource (res:// path) to a Control's 'theme' property so it and its children inherit it (undoable). Pass an empty theme_path to clear… | `*path, *theme_path` |
| `inputmap_add_action` ⚠ | Define a project input action (ProjectSettings input/<name>) with an empty event list and a deadzone. Set save=true to persist to project.godot.… | `*name, deadzone, save, confirm` |
| `inputmap_add_event` ⚠ | Append an input event to an existing project input action. 'event' is { type: key\|mouse_button\|joy_button\|joy_motion, ... } — key: keycode or… | `*name, *event, save, confirm` |
| `inputmap_erase_action` ⚠ | Remove a project input action (ProjectSettings input/<name>). Set save=true to persist to project.godot. | `*name, save, confirm` |
| `inputmap_list` | List all project-defined input actions (ProjectSettings input/*) with their deadzone and events (class + human-readable text). Read-only. | — |
| `interact_add_drop_zone` ⚠ | Mark a node as a drop target that validates an incoming payload and emits a signal on a valid drop. Attaches a generated validator/acceptor script… | `*node, *script_path, *mode, accepts, on_drop, notify, size, shape, confirm` |
| `interact_make_draggable` ⚠ | Wire an existing node for drag-and-drop by attaching a generated reusable drag script (and, for node2d, a drag input action + a hit-area input_event… | `*node, *script_path, *mode, payload, preview, button, action, hit_area, confirm` |
| `main_screen_get` | Report which main-screen editor tab is active (2D / 3D / Script / …) and which are available. Read-only. The active tab decides which viewport… | — |
| `main_screen_set` | Switch the editor's main-screen tab (2D / 3D / Script / …), matching the name case-insensitively. Use this before screenshot_editor to make the… | `*name` |
| `theme_create` ⚠ | Create a new empty Theme resource and save it to a res:// path. | `*to_path, overwrite, confirm` |
| `theme_set_color` ⚠ | Set a color entry on a Theme resource file and save it (e.g. font_color for the Button type). 'color' is [r | `*path, *name, *theme_type, *color, confirm` |
| `theme_set_constant` ⚠ | Set an integer constant entry on a Theme resource file and save it (e.g. h_separation for a BoxContainer). | `*path, *name, *theme_type, *value, confirm` |
| `theme_set_font` ⚠ | Set a font entry on a Theme resource file (loading a Font from a res:// path) and save it. | `*path, *name, *theme_type, *font_path, confirm` |
| `theme_set_stylebox` ⚠ | Set a StyleBox entry on a Theme resource file (loading a StyleBox from a res:// path) and save it. | `*path, *name, *theme_type, *stylebox_path, confirm` |

### I. ❌ 2D 渲染：TileMap / Shader / 粒子（20）

TileMapLayer 与 TileSet、Shader/ShaderMaterial、GPUParticles2D/3D。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `particles_create` | Add a GPUParticles2D/3D node under a parent in the edited scene (undoable). Optional initial amount (> 0), lifetime (> 0), emitting. In-scene and… | `*parent_path, dim, name, amount, lifetime, emitting` |
| `particles_set_amount` | Set the number of particles (amount, > 0) on a GPUParticles2D/3D in the edited scene (undoable). In-scene and undoable — not gated. | `*path, *amount` |
| `particles_set_emitting` | Toggle whether a GPUParticles2D/3D is emitting in the edited scene (undoable). In-scene and undoable — not gated. | `*path, *emitting` |
| `particles_set_lifetime` | Set the particle lifetime in seconds (> 0) on a GPUParticles2D/3D in the edited scene (undoable). In-scene and undoable — not gated. | `*path, *lifetime` |
| `particles_set_process_material` | Create a ParticleProcessMaterial and assign it as process_material on a GPUParticles2D/3D in the edited scene (undoable). Optional knobs: gravity [x… | `*path, gravity, direction, spread, initial_velocity_min, initial_velocity_max, scale_min, scale_max, color` |
| `particles_set_texture` | Load a Texture2D from a res:// path and assign it as texture on a GPUParticles2D in the edited scene (undoable). GPUParticles2D only — GPUParticles3D… | `*path, *texture_path` |
| `shader_create` ⚠ | Create a Shader resource with optional initial code and save it as a .gdshader file. | `*to_path, code, overwrite, confirm` |
| `shader_set_code` ⚠ | Replace the source code of an existing .gdshader resource and save it. | `*path, *code, confirm` |
| `shadermaterial_create` ⚠ | Create a ShaderMaterial and assign it to a node's material slot in the edited scene (undoable). Targets CanvasItem.material (2D / Control) or… | `*path, shader_path, confirm` |
| `shadermaterial_set_param` ⚠ | Set a shader uniform parameter on the ShaderMaterial of a node's material slot in the edited scene (undoable). The node must already have a… | `*path, *param, *value, confirm` |
| `shadermaterial_set_shader` ⚠ | Load a Shader from a res:// path and assign it to the ShaderMaterial on a node's material slot in the edited scene (undoable). The node must already… | `*path, *shader_path, confirm` |
| `tilemap_clear` ⚠ | Remove every painted cell from a TileMapLayer (undoable — prior cells are restored on undo). Returns the number of cells cleared. | `*path, confirm` |
| `tilemap_get_cell` | Read one cell of a TileMapLayer. An empty cell reads back as source_id -1, atlas_coords [-1, -1], alternative 0 (empty = true). | `*path, *coords` |
| `tilemap_set_cell` ⚠ | Paint a single cell on a TileMapLayer (undoable). source_id -1 erases the cell (default). atlas_coords defaults to [0, 0]; alternative defaults to 0. | `*path, *coords, source_id, atlas_coords, alternative, confirm` |
| `tilemap_set_cells_rect` ⚠ | Paint every cell in a rectangular region of a TileMapLayer with one tile (undoable, one action). source_id -1 clears the region. Capped at 65536… | `*path, *rect, source_id, atlas_coords, alternative, confirm` |
| `tilemaplayer_create` | Add a TileMapLayer node under a parent in the edited scene (undoable), optionally binding a TileSet .tres so cells can be painted. In-scene and… | `*parent_path, name, tileset_path` |
| `tileset_add_source` ⚠ | Add a TileSetAtlasSource (backed by a Texture2D) to a TileSet .tres and re-save. texture_region_size defaul | `*tileset_path, *texture_path, texture_region_size, source_id, margins, separation, confirm` |
| `tileset_add_tile` ⚠ | Create a tile at atlas_coords in an atlas source of a TileSet .tres and re-save. size is measured in atlas | `*tileset_path, *source_id, *atlas_coords, size, confirm` |
| `tileset_create` ⚠ | Instantiate a TileSet resource and save it as a new .tres file. tile_size is the base grid cell size in pix | `*to_path, tile_size, overwrite, confirm` |
| `tileset_set_tile_collision` ⚠ | Add a collision polygon to a tile on a TileSet physics layer and re-save. Physics layers are created as nee | `*tileset_path, *source_id, *atlas_coords, *polygon, physics_layer, one_way, confirm` |

### J. ❌ 3D / 物理 / 相机 / 灯光 / 环境 / 导航（22）

2D/3D 物理体与碰撞、关节、刚体参数、相机、灯光、Environment/Sky、导航、CSG、基础网格。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `area_set_gravity` | Set the local gravity override of an Area2D/3D in the edited scene (undoable): space_override mode, gravity magnitude, direction, and whether gravity… | `*path, space_override, gravity, direction, point` |
| `area_set_monitoring` | Set monitoring and/or monitorable on an Area2D/3D in the edited scene (undoable). monitoring = the area detects overlapping bodies/areas; monitorable… | `*path, monitoring, monitorable` |
| `body_create` | Add a physics body node under a parent in the edited scene (undoable): a StaticBody, RigidBody, CharacterBody, or Area, in 2D or 3D. In-scene and… | `*parent_path, *type, dim, name` |
| `body_set_collision_layer` | Set the collision_layer bitmask on a physics body or area (CollisionObject2D/3D) in the edited scene (undoable). layer is the integer bitmask of… | `*path, *layer` |
| `body_set_collision_mask` | Set the collision_mask bitmask on a physics body or area (CollisionObject2D/3D) in the edited scene (undoable). mask is the integer bitmask of layers… | `*path, *mask` |
| `body_set_physics_material` | Create a PhysicsMaterial and assign it as physics_material_override on a StaticBody/RigidBody (2D or 3D) in the edited scene (undoable): friction… | `*path, friction, bounce, rough, absorbent` |
| `camera_create` | Add a Camera3D under a parent (undoable). Optional 'current' makes it the active camera. Returns the new node's path. | `*parent_path, name, current` |
| `collisionpolygon_add` | Add a CollisionPolygon2D/3D node carrying a polygon under a parent (usually a body) in the edited scene (undoable). points is a 2D outline [[x, y]… | `*parent_path, *points, dim, name, build_mode, depth` |
| `collisionshape_add` | Add a CollisionShape2D/3D node carrying a shape resource under a parent (usually a body) in the edited scene (undoable). shape is rect \| circle \|… | `*parent_path, *shape, dim, name, size, radius, height, points` |
| `csg_create` | Add a CSG node under a parent (undoable). 'shape' selects CSGBox3D (box), CSGSphere3D (sphere), CSGCylinder3D (cylinder), CSGTorus3D (torus)… | `*parent_path, shape, name` |
| `environment_create` ⚠ | Create an Environment resource and save it to a res:// path. 'background' sets the mode (clear_color/color/sky/canvas, default clear_color); optional… | `*to_path, background, ambient_color, overwrite, confirm` |
| `environment_set_sky` ⚠ | Attach a Sky to an existing Environment resource file (setting a ProceduralSkyMaterial, PhysicalSkyMaterial, or PanoramaSkyMaterial) and switch its… | `*path, sky_material, confirm` |
| `joint_create` | Add a physics joint node under a parent in the edited scene (undoable). 2D types: pin \| groove \| spring… | `*parent_path, *type, dim, name, node_a, node_b` |
| `joint_set_bodies` | Set node_a and/or node_b on an existing Joint2D/3D in the edited scene (undoable) — the NodePaths of the two bodies the joint connects, relative to… | `*path, node_a, node_b` |
| `light_create` | Add a 3D light under a parent (undoable). 'kind' selects DirectionalLight3D (dir), OmniLight3D (omni), or SpotLight3D (spot). Returns the new node's… | `*parent_path, kind, name` |
| `mesh_set_surface_material` | Assign a Material (res:// path) to a MeshInstance3D (undoable). Default surface -1 sets 'material_override' (whole instance); a surface index >= 0… | `*path, *material_path, surface` |
| `meshinstance_create` | Add a MeshInstance3D under a parent (undoable). Optional 'mesh_path' loads a Mesh resource (e.g. a primitive_mesh_create output) and assigns it.… | `*parent_path, name, mesh_path` |
| `navagent_configure` | Add a NavigationAgent3D under a parent (undoable) and set any of its steering/avoidance properties. Returns the new node's path and the resulting… | `*parent_path, name, radius, height, max_speed, path_desired_distance, target_desired_distance, avoidance_enabl` |
| `navregion_create` | Add a NavigationRegion3D under a parent (undoable). By default seeds a fresh empty NavigationMesh (set with_navmesh=false to skip). Returns the new… | `*parent_path, name, with_navmesh` |
| `physics_set_gravity` ⚠ | Write the project's default gravity for 2D or 3D (ProjectSettings physics/{2d,3d}/default_gravity + default_gravity_vector). Set save=true to persist… | `dim, magnitude, direction, save, confirm` |
| `primitive_mesh_create` ⚠ | Create a PrimitiveMesh resource (box/sphere/cylinder/plane/capsule/prism/torus/quad) and save it to a res:// path. DESTRUCTIVE (writes a file) —… | `*to_path, shape, overwrite, confirm` |
| `rigidbody_set_properties` | Tune a RigidBody2D/3D in the edited scene (undoable): mass (> 0), gravity_scale, linear_damp, angular_damp. Only the provided properties change.… | `*path, mass, gravity_scale, linear_damp, angular_damp` |

### K. ❌ 动画（14）

AnimationPlayer / AnimationTree / 状态机 / 轨道与关键帧。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `anim_add_track` | Add a track to an Animation and set its target path (undoable). Returns the new track index. | `*player_path, *name, *path, type, library` |
| `anim_create` | Create an empty Animation in an AnimationPlayer's library (undoable). Creates the library if it does not exist yet. | `*player_path, *name, library` |
| `anim_delete` ⚠ | Delete an Animation from an AnimationPlayer's library (undoable). | `*player_path, *name, library, confirm` |
| `anim_get_track_keys` | List all keyframes on a track (index, time, value, transition). Read-only. | `*player_path, *name, *track, library` |
| `anim_insert_key` | Insert a keyframe on a track at a given time (undoable). A key already at that exact time is overwritten. | `*player_path, *name, *track, *time, *value, transition, library` |
| `anim_list` | List all animations in an AnimationPlayer across its libraries, with length, loop mode, and track count. Read-only. | `*player_path` |
| `anim_player_create` | Add an AnimationPlayer node under a parent (undoable). Seeds an empty default animation library so anim_create works immediately. | `*parent_path, name` |
| `anim_remove_key` ⚠ | Remove a keyframe by index from a track (undoable). | `*player_path, *name, *track, *key, library, confirm` |
| `anim_set_length` | Set an Animation's length in seconds (undoable). | `*player_path, *name, *length, library` |
| `anim_set_loop` | Set an Animation's loop mode (undoable). | `*player_path, *name, *mode, library` |
| `anim_statemachine_add_state` | Add a state to an AnimationNodeStateMachine (undoable). Targets the AnimationTree's tree_root when it is a state machine, or a nested state-machine… | `*tree_path, *state_name, animation, node_type, state_machine, position` |
| `anim_statemachine_add_transition` | Add a transition between two states in an AnimationNodeStateMachine (undoable). from_state/to_state must exist (or be the built-in "Start"/"End").… | `*tree_path, *from_state, *to_state, state_machine, xfade_time, switch_mode, advance_mode, advance_condition, p` |
| `anim_tree_add_node` | Add a node to an AnimationTree's tree_root graph (AnimationNodeBlendTree or AnimationNodeStateMachine), undoable. node_type is any AnimationNode… | `*tree_path, *node_name, *node_type, animation, position` |
| `anim_tree_create` | Add an AnimationTree node under a parent (undoable) with a fresh tree_root graph. root_type "blend_tree" (AnimationNodeBlendTree) or "state_machine"… | `*parent_path, name, root_type, anim_player_path, active` |

### L. ❌ 音频（7）

总线布局、播放器、流分配、WAV 分析、音频捕获。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `audio_analyze` | Measure a WAV file in the project: loudness (LUFS), sample and true peak, clipping, octave bands, and a spectrogram picture. With compare_to, also… | `*path, compare_to` |
| `audio_bus_add` ⚠ | Add a bus to the project's global AudioServer layout, optionally naming it, positioning it (at_position), and setting its send bus. DESTRUCTIVE… | `name, at_position, send, confirm` |
| `audio_bus_add_effect` ⚠ | Instantiate an AudioEffect subclass (by class name, e.g. "AudioEffectReverb") and add it to a named bus on the global AudioServer, optionally at a… | `*bus, *effect, at_position, confirm` |
| `audio_bus_set_volume` ⚠ | Set the volume (in dB) of a named bus on the global AudioServer. | `*bus, *volume_db, confirm` |
| `audio_player_create` | Add an AudioStreamPlayer / AudioStreamPlayer2D / AudioStreamPlayer3D node under a parent in the edited scene (undoable). `dim` selects "none"… | `*parent_path, dim, name, stream_path, autoplay, volume_db, bus` |
| `audio_set_bus_layout` ⚠ | Save the current AudioServer bus layout (buses, effects, volumes) to a .tres resource on disk (default res://default_bus_layout.tres) via… | `to_path, overwrite, confirm` |
| `audio_set_stream` | Load an AudioStream from a res:// path and assign it as stream on an AudioStreamPlayer/2D/3D in the edited scene (undoable). In-scene and undoable —… | `*path, *stream_path` |

### M. ❌ 玩法模板 / 联机 / 后端脚手架（本项目不用）（26）

棋盘/卡牌/棋子模板、ENet/WebRTC/同步器、认证/云存档/排行榜后端脚手架。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `auth_scaffold` ⚠ | Generate login/register/logout helpers against an installed backend SDK. FEATURE-DETECTED both ways: if the SDK provides no auth API (Photon is… | `*sdk, to_path, overwrite, confirm` |
| `backend_configure` ⚠ | Generate a config/bootstrap GDScript for a game-backend SDK (SilentWolf / Nakama / PlayFab / Photon): a Node whose configure() wires the API key /… | `*sdk, to_path, api_key, game_id, title_id, app_id, host, port, server_key, region, overwrite, confirm` |
| `backend_detect` | Report which of the known game-backend SDKs (SilentWolf, Nakama, PlayFab, Photon) are installed in this project and how each was found (an enabled… | `sdk` |
| `board_create` ⚠ | Build a board scene whose children are addressable cells (each a cell_<id> node in the board_cells group) from a ring, grid, or explicit-cells… | `*path, *layout, cell_size, cell_kind, root_type, background, overwrite, confirm` |
| `board_place` | Reparent an existing node (a card or piece instance) onto a board cell by id and snap it to the cell anchor. Undoable node authoring. The target cell… | `*board, *cell, *node, align` |
| `board_tile_create` ⚠ | Build a tile-backed board scene: a TileMapLayer grid whose cells are addressable by integer [x, y] tile coordinates (cols wide × rows tall). The… | `*path, *rows, *cols, tile_size, tileset, paint, layer_name, overwrite, confirm` |
| `board_tile_place` | Snap an existing node (a card or piece instance) onto a TileMapLayer cell by integer [x, y] tile coordinate. Undoable node authoring. The cell's… | `*layer, *node, *coord, tile_size, anchor, align, reparent` |
| `card_deck_from_table` | Read a CSV or JSON table and stamp one card per row, binding columns to slots via a column map. Undoable node authoring. column_map values are bare… | `*template_path, *parent, *table_path, format, *column_map, filter, art_column, limit, face_up, layout, persist` |
| `card_hand_layout` | Instance N cards under a container and arrange them as a row, fan, stack, or grid. Undoable node authoring. Each card carries its own data (bound via… | `*template_path, *parent, *cards, *mode, spacing, overlap, fan_angle, columns, align, origin, persist` |
| `card_instance` | Instance a card template into the open scene and bind data to its slots via the template's set_data(). Undoable node authoring. Slot values are… | `*template_path, *parent, *data, position, face_up, name, persist` |
| `card_set_face` | Flip an instanced card (or any node exposing set_face(bool) — the generated card and piece scripts both do) between its face and back. Instant by… | `*node, *face_up, method, animate` |
| `card_template_create` ⚠ | Build a reusable card scene (a PackedScene) from a slot spec, with a generated script-backed set_data() / set_face(). Named slots (label / rich_text… | `*path, *size, root_type, *slots, face, back, theme_path, theme, script_path, overwrite, confirm` |
| `cloudsave_scaffold` ⚠ | Generate save/load cloud-save helpers against an installed backend SDK. FEATURE-DETECTED both ways: if the SDK provides no cloud-save API (Photon is… | `*sdk, to_path, overwrite, confirm` |
| `leaderboard_scaffold` ⚠ | Generate submit/fetch leaderboard helpers against an installed backend SDK. FEATURE-DETECTED both ways: if the SDK provides no leaderboard API… | `*sdk, to_path, leaderboard_name, overwrite, confirm` |
| `mp_add_spawner` | Add a MultiplayerSpawner node under a parent (undoable). Godot 4 high-level multiplayer replicates server-spawned nodes to clients: set spawn_path to… | `*parent_path, name, spawn_path, spawnable_scenes` |
| `mp_add_synchronizer` | Add a MultiplayerSynchronizer node under a parent (undoable) and, if properties are given, build a SceneReplicationConfig that replicates them.… | `*parent_path, name, root_path, properties, replication_mode` |
| `mp_scaffold_lobby` ⚠ | Generate a lobby controller GDScript: host/join over ENet plus peer_connected/peer_disconnected tracking with player_joined / player_left /… | `*to_path, port, max_players, class_name, overwrite, confirm` |
| `mp_set_authority` | Set a node's multiplayer authority (set_multiplayer_authority) to a peer id (undoable). The authority peer is the one allowed to push… | `*path, *peer_id, recursive` |
| `mp_setup_enet_peer` ⚠ | Generate a GDScript helper that sets up an ENetMultiplayerPeer (host_game / join_game / close) and assigns multiplayer.multiplayer_peer. Godot's… | `*to_path, port, max_clients, class_name, overwrite, confirm` |
| `mp_setup_webrtc_peer` ⚠ | Generate a GDScript helper that sets up a WebRTCMultiplayerPeer mesh and assigns multiplayer.multiplayer_peer. FEATURE-DETECTED: if the WebRTC… | `*to_path, class_name, overwrite, confirm` |
| `mp_wire_rpc` ⚠ | Insert (or replace) an `@rpc(...)` annotation above a function in an existing GDScript, so it can be called across the network. If the function does… | `*path, *function, mode, transfer_mode, call_local, channel, confirm` |
| `piece_instance` | Instance a piece template into the open scene and bind data (art / color / label) via the template's set_data(). Undoable node authoring. Optionally… | `*template_path, *parent, *data, position, face_up, name, place_on, persist` |
| `piece_move` | Move a piece onto a board cell by id (reparent + snap via board_place), optionally with a short scale "pop" animation authored from Group C anim… | `*board, *node, *to, from, align, animate` |
| `piece_template_create` ⚠ | Build a reusable piece (token) scene from a spec: an Art node (Sprite2D under a Node2D root, TextureRect under a Control root), an optional Label, an… | `*path, *size, root_type, art, color, label, label_text, hit_area, back, script_path, overwrite, confirm` |

### N. ❌ 资产占位生成（7）

按 prompt 生成图标/精灵/纹理/音效/模型；无后端时退化为程序化占位资源。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `asset_gen_audio_sfx` ⚠ | Generate a short sound effect from a prompt and import it at a res:// path (an AudioStreamWAV for the placeholder backend). Delegates to the… | `*prompt, *to_path, duration_ms, placeholder, overwrite, confirm` |
| `asset_gen_configure` | Inspect or set the asset-generation backend for this session (Group J's feature flag). backend 'none' (default) makes the generators degrade to a… | `backend, command, provider` |
| `asset_gen_icon` ⚠ | Generate a square icon from a prompt and import it at a res:// path. Delegates to the configured backend; degrades to a request spec with no backend… | `*prompt, *to_path, width, height, placeholder, overwrite, confirm` |
| `asset_gen_model` ⚠ | Generate a 3D mesh from a prompt and import it at a res:// path (a BoxMesh/primitive for the placeholder backend). Delegates to the configured… | `*prompt, *to_path, shape, placeholder, overwrite, confirm` |
| `asset_gen_placeholder` ⚠ | Write a deterministic, in-engine PROCEDURAL placeholder asset to a res:// path — no model, fully reproducible (colour/frequency/size derive from a… | `*kind, *to_path, prompt, width, height, duration_ms, shape, overwrite, confirm` |
| `asset_gen_sprite` ⚠ | Generate a 2D sprite texture from a prompt and import it at a res:// path. Delegates the pixels to the configured backend (asset_gen_configure); with… | `*prompt, *to_path, width, height, placeholder, overwrite, confirm` |
| `asset_gen_texture` ⚠ | Generate a (tileable-intent) material texture from a prompt and import it at a res:// path. Delegates to the configured backend; degrades to a… | `*prompt, *to_path, width, height, placeholder, overwrite, confirm` |

### O. ❌ C#（本项目不用）（23）

OmniSharp / netcoredbg 的 C# 补全、诊断、引用、重命名与调试。

| 工具 | 作用 | 关键参数 |
| --- | --- | --- |
| `cs_code_action` | List the code actions (quick fixes / refactors) OmniSharp offers for a range — the lightbulb menu. Read-only: returns the available actions (title… | `*path, *start_line, *start_character, end_line, end_character, only` |
| `cs_completion` | Type-aware C# code completion at a position via OmniSharp. Returns at most max_results items (default 200) and sets truncated when the language… | `*path, *line, *character, max_results` |
| `cs_dbg_attach` | Attach netcoredbg to an already-running .NET process (e.g. a C# Godot game launched separately) by its OS process id. Any breakpoints set beforehand… | `*process_id` |
| `cs_dbg_continue` | Resume execution and wait for the program to settle again (next breakpoint or termination). Returns the resulting state; if it runs on with no… | — |
| `cs_dbg_evaluate` ⚠ | Evaluate a C# expression in the context of a stopped frame. Bounded by a shor | `*expression, frame_id, confirm` |
| `cs_dbg_launch` | Start a C# Godot game under netcoredbg. `program` defaults to the configured Mono/.NET Godot binary (GODOT_CSHARP_BIN) and `args` to ['--path', <C#… | `program, args, stop_on_entry, just_my_code, allow_port_conflict` |
| `cs_dbg_restart` | Restart the current C# debug session. Uses the DAP `restart` request when the adapter advertises `supportsRestartRequest`, otherwise falls back to… | `stop_on_entry, program, args` |
| `cs_dbg_scopes` | Return the variable scopes (Locals, etc.) for a C# stack frame. | `*frame_id` |
| `cs_dbg_set_breakpoints` | Set (replace) the breakpoints for a C# source file. Applied immediately if a session is running, else buffered until launch/attach. Feature-detected… | `*path, *lines, conditions` |
| `cs_dbg_set_exception_breakpoints` | Enable (replace) the debugger's exception breakpoint filters so execution halts when a matching .NET exception is thrown (DAP… | `filters` |
| `cs_dbg_set_variable` ⚠ | Change a variable's value in a stopped C# frame (DAP setVariable). `variabl | `*variables_ref, *name, *value, confirm` |
| `cs_dbg_stack_trace` | Return the current C# call stack (only meaningful while stopped at a breakpoint). | `levels` |
| `cs_dbg_step` | Step execution: 'over' (next), 'in' (stepIn), or 'out' (stepOut), then wait for the step to land. Returns the resulting state and stop reason. | `*kind` |
| `cs_dbg_variables` | List variables under a scope or a complex value (via its variables_ref). | `*variables_ref` |
| `cs_dbg_watch` | Manage a persistent set of C# watch expressions and evaluate them in the current stopped frame. Pass `add`/`remove`/`clear` to mutate the set (all… | `add, remove, clear, frame_id` |
| `cs_definition` | Resolve the definition location(s) of the C# symbol at a position. | `*path, *line, *character` |
| `cs_diagnostics` | Return compile/analyzer diagnostics (errors, warnings) for a C# script. Opens the file and waits briefly for OmniSharp to publish. | `*path, wait_ms` |
| `cs_document_symbols` | List the symbols (classes, methods, properties, fields) declared in a C# script. | `*path` |
| `cs_hover` | Hover documentation/type info at a position (e.g. the `Counter : int` type). | `*path, *line, *character` |
| `cs_references` | Find all references to the C# symbol at a position. | `*path, *line, *character, include_declaration` |
| `cs_rename` ⚠ | Rename a C# symbol project-wide via OmniSharp. Returns the planned edit; pass apply=true to WRITE the changes to disk ( new | `*path, *line, *character, *new_name, apply, confirm` |
| `cs_signature_help` | Show the call signature(s) and active parameter at a position (the parameter hints an IDE pops up inside a call). | `*path, *line, *character` |
| `cs_workspace_symbols` | Search C# symbols across the whole project by name. Unlike Godot's GDScript server, OmniSharp implements LSP 'workspace/symbol', so this returns real… | `*query` |

---

## 3. 维护

- 工具清单来自一次完整会话归档（442 tools 中 `mcp__godot__*` 共 298 个，为**旧口径**；当前插件实际注册 295 个，`session_tools` 视角隐藏 285 个）。Godot 插件升级后如增减工具，按同样方法重新生成，并同步「49 可激活 / 其余激活也拿不到」的划分。
- 提取方法：读会话 `.jsonl`，取 `seq==14` 的 `data.header.tools`，过滤 `name.startswith("mcp__godot__")`，导出 `name / description / parameters`。
- 本文件只做索引；工具行为、参数细节以调用时返回的 schema 为准。
