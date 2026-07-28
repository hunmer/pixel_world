# 对外接口（breakpoint_mcp）

## JSON 协议（loopback TCP, newline-delimited）

```
→ {"id":"<string>","method":"<name>","params":{...}}
← {"id":"<string>","ok":true,"result":{...}}
← {"id":"<string>","ok":false,"error":{"code":"<string>","message":"<string>"}}
```

服务器推送事件（无 id）：
- `godot://editor-state`（选择变化）
- `godot://scene-tree`（编辑场景切换）
- `resources/updated`（由前两者触发）

## 编辑器侧方法（`operations.gd` dispatch，28+ 个）

> 方法名与 host 的工具 1:1 对应。下面按 `operations.gd` 的 handler 归类（handler 多为 `_xxx`，对外方法名见 dispatch 表 / 上游 `docs/TOOL_CATALOG.md`，本仓库不含该目录）。

| 类别 | handler（源） | 能力 |
| --- | --- | --- |
| ping / 状态 | `_ping`, `_editor_get_state` | 心跳、编辑器状态 |
| 项目 | `_project_get_info`, `_project_get_setting`, `_project_set_setting` | 项目信息 / 设置读写 |
| 场景 | `_scene_get_tree`, `_scene_open`, `_scene_save`, `_scene_new` | 场景树查询 / 打开 / 保存 / 新建 |
| 节点 | `_node_add`, `_node_delete`, `_node_rename`, `_node_reparent`, `_node_duplicate`, `_node_get_children`, `_node_set_property`, `_node_get_property`, `_serialize_node` | 节点 CRUD + 属性读写（全带 undo/redo） |
| 选择 | `_selection_get`, `_selection_set` | 编辑器选择 |
| undo/redo | `_edit_undo`, `_edit_redo`, `_edit_history_step` | 撤销/重做/历史步进 |
| ClassDB / 文档 | `_classdb_get_class`, `_classdb_reference`, `_docs_search` | 类信息 / 文档搜索 / 文档 URL |
| 截图 | `_screenshot` | 编辑器截图 |

辅助：`_resolve(root, path)`、`_path_of`、`_descendants`、`_edited_root`、`_type_name`、`_doc_url`/`_doc_member_url`。

## 运行时侧方法（`runtime_bridge.gd`，runtime_*）

暴露**活的游戏**给 host（端口 9081）：

- **SceneTree**：读节点树、找节点。
- **属性**：读写运行时节点的属性（用 `variant_json.gd` round-trip 富类型）。
- **方法**：调用节点方法。
- **信号**：emit 信号。
- **输入注入**：注入 InputEvent。
- **Performance 监视器**：`runtime.get_monitors` 暴露精选 monitors（`MONITORS` 常量：fps/process/memory/node_count/render draw calls/physics/audio latency 等）。
- **截图**：捕获游戏帧。
- **日志环**：`LOG_CAP=1000` 的日志 ring buffer（Godot 4.5+ 用运行时编译的 Logger 子类捕获）。
- **D6 异步通道**：部分 await 帧的方法走 async lane（见 `_handle_line`/`_dispatch_async`）。

## Variant⇄JSON 编解码（`variant_json.gd`）

JSON 只能携带 null/bool/number/string/array/object。Godot 富类型编码为标签对象：
- `Vector2/2i/3/3i/4`、`Rect2`、`Color`、`Quaternion`、`NodePath` 等 → `{"__type__":"Vector3","x":..,"y":..,"z":..}`。
- `StringName` → 纯字符串；`encode()`/`decode()` 双向，保证属性 set/get round-trip。

## 安全门控

- 密钥握手（`bridge_secret.gd`）—— 见 [conventions.md](conventions.md)。
- mutation 的破坏性确认在 host 端 elicitation；addon 侧用密钥补这层门控的"牙齿"。
- 绑定 loopback only。

> 完整方法签名与参数 schema 见上游 `docs/TOOL_CATALOG.md`（本仓库未含，需回 breakpoint-mcp 上游仓库）。本索引仅归纳结构与能力清单。
