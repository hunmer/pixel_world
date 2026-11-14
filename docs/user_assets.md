# 用户素材库（user assets）运维手册

> 适用对象：负责素材服务、清单重跑、回滚与验收的维护者。
> 代码入口：`scripts/assets/`（service / catalog / visual_adapter）、`tools/build_blocks_manifest.mjs`。

## 1. 素材从哪来

- **本地导入**：地图编辑器「素材」Tab → 导入按钮（FileDialog，PNG/JPG/JPEG/WebP），走
  `UserAssetService.import_local_file()`，内容寻址（sha256）存 blob，去重。
- **网络清单**：默认源 `http://127.0.0.1:8076/blocks.json`（F:/blocks 的 http-server，仅回环）。
  编辑器面板「保存并刷新」或 `UserAssetService.request_manifest()` 拉取。

## 2. 清单协议（blocks.json）

- 顶层 `{ "blocks": [...] }`；service 也接受裸数组或 `assets/images/items/files/entries` 键（宽容解析，
  `extract_manifest_entries`）。
- 每条 descriptor 字段（对齐 `UserAssetCatalog.validate_descriptor`）：
  `id`（`^[a-z0-9][a-z0-9_.-]{0,63}$`）、`kind`（`terrain|plant`）、`name`、`tags`、`image`（相对 URL，
  由 `resolve_url` 拼到源目录）、`sha256`（64 hex）、`bytes`、`width`、`height`、`render`。
- `render` 默认（`default_render()`）：`{mode:"full", crop:null, pivot:{x:0.5,y:1.0}, scale:1.0, footprint:{w:1,h:1}}`。
  方块图一律 **整图 full 模式**——图片本身已含等距顶面，不做四向展开、不抠白底（单图视角限制，见 §6）。
- 下载图片时 service 校验 sha256（`_handle_image_body`），不符即 `asset_failed(sha256_mismatch)`，不落盘。

## 3. 生成 / 重跑清单

```bash
node tools/build_blocks_manifest.mjs --root F:/blocks --out F:/blocks/blocks.json   # 生成或增量重跑
node tools/build_blocks_manifest.mjs --root F:/blocks --check                        # 只校验不写
node --test tools/build_blocks_manifest.test.mjs                                     # Node 契约 7 项
```

- 扫描 `*.png`，魔数 + IHDR 校验，坏图剔除并计入 `anomalies`（退出码 1）。
- 确定性排序（id 升序）、字节/PNG 尺寸/SHA256/相对 image、稳定 id（文件名 slugify）。
- **重跑幂等**：按 id 保留用户改过的 `name/tags/render/kind`（与 service `_merge_net_descriptor` 同语义），
  源侧 `image/sha256/bytes/width/height` 始终以磁盘为准；磁盘消失的文件剔除并列入 `removed`。
- 原子写：`blocks.json.tmp` → 回读校验 → 备份旧文件为 `blocks.json.bak` → rename。
- 前缀 11 类（grassland/elfland/rainforest/desert/snow/swamp/volcano/ocean/vanilla/creative/basic）只作 tags。

## 4. HTTP 服务生命周期

- 进程：procm 受管进程 **id=`mATIDEYo`**（名 `pixelworld_assets_http`，组 `pixelworld-assets`），
  PID 28136，命令 `http-server F:/blocks -a 127.0.0.1 -p 8076 -c-1`（无缓存）。
- 仅 listen `127.0.0.1:8076`，不出网卡；root=F:/blocks，目录列表可见（便于排查）。
- 日志：MCP `mcp__procm-mcp__process-logs` `{"id": "mATIDEYo"}`；落盘文件
  `C:/Users/Administrator/.procm-mcp-dsh/UqU6-3(5680)/processes/mATIDEYo-stdout.log`（stderr 同名
  `-stderr.log`），用读文件工具直接查看即可。
- **临时停止（保留受管配置，ID 可沿用）**：MCP `mcp__procm-mcp__process-input` 参数
  `{"id": "mATIDEYo", "signal": "SIGTERM"}`；之后用 `mcp__procm-mcp__batch-process` 参数
  `{"action": "restart", "ids": ["mATIDEYo"]}` 按原 ID 拉起。
- **永久删除**：`mcp__procm-mcp__process` 参数 `{"action": "delete", "id": "mATIDEYo"}` 会移除受管配置、
  **ID 即失效**；之后必须用 `mcp__procm-mcp__batch-process` 参数
  `{"action": "start", "processes": [{"script": "http-server", "args": ["F:/blocks", "-a", "127.0.0.1", "-p", "8076", "-c-1"], "cwd": "F:/blocks", "name": "pixelworld_assets_http", "group": "pixelworld-assets", "port": 8076, "desc": "pixel_world 素材库 HTTP 服务"}]}` 完整重建，并把本文档 §4/§8 与新 ID 一并更新记录。
- 受管 procm 进程**没有对应 host job，禁止 `job_kill`**（会误杀无关任务）。
- 8076 被占用时**不得杀别人**：先 `netstat -ano | findstr :8076` 查属主，换端口或让原属主释放。
- 服务不在时 Godot 侧行为：清单刷新失败 → 面板显示错误 + Retry；已下载素材照常可用（库与 blob 在
  `user://custom_assets/`，adapter 离线可读，LRU 64）。

## 5. Godot 侧行为速查

| 场景 | 行为 |
| --- | --- |
| 首次刷新清单 | 1455 条全部入库（`manifest_loaded {ok,added=1455,total=1455}`） |
| 按需下载 | `request_asset_image(id)` → `asset_ready` / `asset_failed`（sha256 校验） |
| 丢图（库有描述符、blob 缺失） | adapter `resolve()` 返回程序占位（missing=true，淡红提示），引用不丢 |
| 在线素材预览 | 面板懒预览对「image 为 http 且本地无 blob」的可见素材**自动加载图片**（service 内部去重/限流），加载后缓存进 blob 目录；`asset_ready` 后清 adapter 占位缓存换真图；`asset_failed` 状态栏报真实错误 |
| 方块页素材方块 | 方块 Tab 的「素材方块」网格**只列已保存（✓）**的地形素材——浏览在线列表会自动下载缓存，按缓存过滤等于整页全进来，所以以用户保存标记为准（本地导入默认已保存）：素材 Tab 选中后点「保存标记」即出现在方块页；未下载的已保存方块保持占位、网格重建时顺手触发下载，完成经 `asset_ready` **0.3s 合批**重建换真图；取消标记/一键清空后从网格消失；空列表显示引导提示（`BlockAssetEmptyHint`）；网格一次性 `adapter.resolve_many(ids, false)` 批量出图（单次库加载、不灌 LRU）；点选后方块页画笔=ASSET 放置（tile_overrides 层），再点取消回选择工具；与素材 Tab 选中互斥；放置锚定=素材图**顶边对齐格顶面平面**（素材图是「顶面+侧面」的完整方块 depiction，同内建块 TOP_UV 贴法，renderer `_asset_block_for(top_aligned=true)`；底缘锚定会把整块顶高悬空）；**内置画笔/填充覆盖素材格时自动清 tile_override** 恢复常规柱（fill 同地形也走完清覆盖分支，否则 from==to 早退） |
| 素材尺寸归一化 | `UserAssetVisualAdapter.bake_image` 对 terrain 先 `_opaque_bounds` 裁到不透明内容（去透明留白），再等比 fit 进 32px×footprint.w × 26px×footprint.h 内容盒（等比最近邻缩放、不拉伸变形，盒=内建方块图集顶面 y6..22 + 侧面到 y32），`render.scale` 在其上再乘；植物不归一化；crop 模式按裁后尺寸算——解决 F 盘整图方块（~174px 宽、底部留白）放置后 32x40 比正常方块 32x26 大的问题 |
| 内容包围盒锚定 | pivot 的锚域是不透明内容包围盒（`_opaque_bounds` 扫描 alpha>0.04）而非整图底缘：素材 PNG 底部常带透明留白，整图锚会把块体顶高悬空；全不透明图退化为旧整图公式，行为兼容；与渲染层内建装饰 `_prop_content_bottom` 同思路 |
| 编辑器画布光照 | 编辑器场景无 main.gd 的日光系统，而地形材质自 3D 日照提交（3189caf）起是逐像素着色——无灯时整块画布渲成黑色（与素材无关的潜伏 bug，2026-11-14 修复）：`EditorCanvas._ready` 挂 `SunlightSystem` 固定正午 `apply_time(0.5, 0.0)`（与 battle.gd B2 同款）；素材 billboard 材质本就 unshaded 不受影响 |
| 烘焙缓存落盘 | crop/归一化/scale 的像素处理只做一次：`resolve`/`resolve_many` 走 `_load_baked_or_blob` 优先读 `<root>/baked/<id>.v2.png`（烘焙版本号 `BAKED_VERSION=2`，归一化语义变更后旧烘焙自然失效重烘），缺失则读 blob 现场烘焙并 `save_png` 落盘；render 参数编辑后 `invalidate_baked(id)` 删烘焙图重烘；源 blob 永不被修改 |
| 多选与保存标记 | 列表多选模式：普通点击=画笔主选，Ctrl+点击=加选/减选；「保存标记」对选中行**切换**用户保存标记（已标记→取消），经 `service.set_assets_saved` 持久化到库（manifest 重跑经 `_merge_net_descriptor` 全量保留旧字段不丢标记）；本地导入素材默认 saved=true；✓ 前缀=用户保存标记，与图片是否已缓存无关 |
| 隐藏素材 | `remove_asset(id, keep_blob=true)`：库中移除、blob 保留；地图引用靠存档内 `user_assets` 快照 |
| 一键清空已下载 | 素材面板「清空已下载…」按钮（带确认弹窗，`ClearCacheConfirmDialog`）→ `service.clear_online_cache()`：删除全部 **http 来源**素材的 blob 原图、`baked/` 烘焙图与**保存标记 ✓**（本地导入素材与其标记不动），库描述符保留、状态回 missing；先落库标记、成功后才删文件（保存失败整体不动）；面板视觉缓存全失效重建，之后浏览到会自动重新下载；用于重置/释放磁盘 |
| 编辑器 Esc | 素材弹窗先关（`AssetLibraryPanel.close_dialogs()`），不穿透退出编辑器 |
| 素材列表分页 | 全库先过滤 + 按 id 稳定排序再切页，24 条/页只建本页行；翻页条含上一页/下一页、页码/总页数/匹配总数；过滤变更回第 1 页，导入/隐藏/清单同步后钳制页界；翻页与异步 `asset_ready` 均不触发全库请求、不重建列表 |
| 存档 | `tile_overrides`（地块整图）与 `props[].asset_id`（植物）均带 `user_assets` 描述符快照，保存前权威预校验，tmp/bak 原子写 |

## 6. 单图视角限制

等距方块图是**单张 2D 图**（含伪 3D 顶面），不是自动四向真 3D。渲染按 `render.pivot`（默认底部中心
`{0.5,1.0}`）贴到柱顶，战斗视角仅支持 4 正交角度（0/90/180/270）。禁止擅自抠白色背景或按角度重投影。

## 7. 用户原图保全

- F:/blocks 下 1455 张 PNG **只读**：生成脚本只写 `blocks.json`/`blocks.json.bak`/`.tmp`，不碰原图。
- 编辑器导入的本地文件只读源文件，blob 为内容寻址副本。
- 隐藏/删除素材保留 blob 与存档快照，随时可恢复引用。

## 8. 精确回滚

1. 临时停服务（保留配置）：`mcp__procm-mcp__process-input` `{"id": "mATIDEYo", "signal": "SIGTERM"}`；已永久删除则按 §4 的
   `batch-process start` 完整配置重建并记录新 ID。
2. 还原清单：`cp F:/blocks/blocks.json.bak F:/blocks/blocks.json`（或重跑 §3 脚本，幂等）。
3. 还原 Godot 库：`user://custom_assets/` 整目录替换为备份（库 `library.json` + `blobs/`）。
4. 重启服务：`mcp__procm-mcp__batch-process` `{"action": "restart", "ids": ["mATIDEYo"]}`（永久删除后改用 start 重建）。
5. 验证：`node tools/build_blocks_manifest.mjs --check` + `user_asset_source_live_contract`（需服务在线）。

## 9. 验收命令清单

```bash
node --test tools/build_blocks_manifest.test.mjs                                   # Node 7 项
godot --headless --path . --script res://tests/user_asset_source_live_contract.gd  # 需服务在线，57 checks
godot --headless --path . --script res://tests/user_asset_editor_contract.gd       # 59 checks，编辑器全链路
godot --headless --path . --script res://tests/user_asset_runtime_contract.gd      # 78 checks，service/adapter/归一化/烘焙缓存
```

> 注：本机无 godot MCP 桥接的会话以 headless 契约为准；带 MCP 的会话按 `godot-debug` skill 做运行态断言。

## 10. 测试证据交接（T1/T2/T3 实际执行记录）

> 以下均为本机真实执行结果（godot 二进制 `D:/Godot/Godot_v4.7.2-stable_win64.exe`），未重复跑已过测试。

| 阶段 | 命令 | 检查数 / 结果 | 退出码 |
| --- | --- | --- | --- |
| T3 清单 | `node --test tools/build_blocks_manifest.test.mjs` | 7/7 通过（形状/字段/重跑保留/坏图拒绝/id 规范化/原子写/--check） | 0 |
| T3 清单实跑 | `node tools/build_blocks_manifest.mjs --root F:/blocks --out F:/blocks/blocks.json` | 1455 条，11 前缀，0 异常 | 0 |
| T3 HTTP 实测 | Node 脚本 GET `127.0.0.1:8076/blocks.json` + 每前缀代表图 | manifest 200/1455 条；hash 11/11 匹配；404 正常 | — |
| T3 live 端到端 | `godot --headless --path . --script res://tests/user_asset_source_live_contract.gd` | 45 checks 全绿（默认 URL/清单/描述符/下载/视觉/缺图/离线/面板手动下载回归 S7/多选批量下载 S8） | 0 |
| 后续迭代 | 同上 4 项编辑器契约（editor/pagination/ui） | editor 59（含方块页素材方块 S9）/ pagination 28 / ui EXIT=0 全绿 | 0 |
| 自动加载+保存标记+尺寸归一化 | `godot --headless --path . --script res://tests/user_asset_source_live_contract.gd` / `user_asset_runtime_contract.gd` | live 46（S7 懒预览自动加载/S8 保存标记 toggle+持久化）/ runtime 68（含 S12 归一化 5 项）EXIT=0 全绿；editor 59 / pagination 28 / ui / render / save / catalog / map_editor 回归 EXIT=0 | 0 |
| 归一化修正 32x26 盒 | `godot --headless --path . --script res://tests/user_asset_runtime_contract.gd` 等 5 项 | runtime 78（S12 改 32x26 内容盒 fit 断言）/ live 61（S9 烘焙路径改 .v2.png）/ editor 63 / pagination 28 / ui EXIT=0 全绿 | 0 |
| 放置悬空+覆盖修复 | 同上 + editor 契约 + 窗口化截图探针 | editor 65（新增画笔/填充覆盖清 override 2 断言）/ render / runtime 78 / pagination 28 / ui / live EXIT=0 全绿；窗口化截图 vision 确认素材块与邻格齐平不悬空 | 0 |
| 一键清空已下载 | `godot --headless --path . --script res://tests/user_asset_source_live_contract.gd` / `user_asset_editor_contract.gd` | live 61（S9 13 项：清空删在线 blob+烘焙图+保存标记/本地导入保留/描述符保留/状态回 missing）/ editor 63 EXIT=0；ui / pagination 28 回归 EXIT=0 | 0 |
| 方块网格只列已保存 | 同上 editor 契约 | editor 63 checks EXIT=0（S9 改保存标记 toggle 断言：取消标记出网格/恢复标记回归）；一键清空/取消标记后方块 Tab 网格即空 | 0 |
| 内容锚定+烘焙缓存+合批刷缩略图 | 同上 6 项契约（runtime/live/editor/pagination/ui/map_editor） | runtime 78（含 S14 烘焙落盘 4 项）/ live 46 / editor 59 / pagination 28 / ui / map_editor EXIT=0 全绿 | 0 |
| 编辑器黑块修复（画布光照） | 窗口化 `godot --path . --script` 截图探针：载入 plains_skirmish 实证修复前地形全黑、修复后彩色；回归 4 契约 `map_editor_ui_contract.gd` / `user_asset_editor_contract.gd` / `user_asset_pagination_contract.gd` / `battlefield_render_contract.gd` | 截图对比验证（EditorSunlight 固定正午）；4 项 EXIT=0 | 0 |
| T2 编辑器全链路 | `godot --headless --path . --script res://tests/user_asset_editor_contract.gd` | 59 checks（导入/放置/撤销重做/保存重开/四角度拾取/B2/缺图/方块页素材方块 S9） | 0 |
| T1+ service/adapter | `godot --headless --path . --script res://tests/user_asset_runtime_contract.gd` | 63 checks | 0 |
| T1 schema | `godot --headless --path . --script res://tests/user_asset_catalog_contract.gd` | 全过 | 0 |
| T2 受影响回归 | `map_editor_ui_contract.gd`（7 Tab+素材面板结构）、`battlefield_render_contract.gd`、`battle_save_contract.gd` | 全过 | 0（各） |

**重要边界**：以上 headless 契约通过**不替代** MapEditor 界面运行态、四角度画面与交互的 MCP 运行验收
（`godot-debug` skill 的 `dbg_launch` + `runtime_assert_*` + 截图）——该项受本会话工具缺失（无
`mcp__godot__*`）限制未执行，需在有 MCP 桥接的会话补验，不得据本表宣称界面验收通过。
