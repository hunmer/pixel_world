# 地图建筑素材与视觉验收

建筑使用独立 `buildings` 层：一栋建筑只保存一个实例，逻辑占地和图片高度分别计算。当前支持地面阻挡，不支持角色登楼或屋顶站立。

## 两类建筑图片

- **无背面**：`render.back_mode="single"`。四个地图视角均显示同一张正面图，建筑不会在背向相机时消失。
- **有背面**：`render.back_mode="front_back"`，并通过 `render.back_asset_id` 引用另一张已导入图片。相机相对实例方向的象限 0/1 显示正面，2/3 显示背面。背面图片缺失时回退正面。

两张图片提供前／背两个外观，不会自动生成四个独立方向。图片平面始终朝向相机；需要精确侧面轮廓时应准备更多方向素材或使用真实 3D 模型。

## 素材标定

素材 `kind` 设为 `building`，渲染参数如下：

```json
{
  "mode": "full",
  "crop": null,
  "pivot": {"x": 0.425, "y": 0.9},
  "scale": 1.0,
  "footprint": {"w": 2, "h": 2},
  "ground_width_px": 1150.0,
  "back_mode": "single",
  "back_asset_id": ""
}
```

上面是 `meowa_tiles/generated/citywall_1to9.png` 的**初始标定示例**，尚未通过画面验收，不代表最终美术参数。

- `footprint.w/h`：地面矩形占地，边长 1..8。实例旋转为奇数时交换宽高。
- `pivot`：落地锚点在非透明内容包围盒中的归一化坐标；应对准底座中心，而非整图最底端。
- `ground_width_px`：源图中底座的标定宽度。0 表示使用内容包围盒宽度；有阳台、挑檐时宜手动标定。
- `scale`：底座标定后的额外等比缩放，不改变逻辑占地。
- `crop`：启用裁切时，底座标定宽度以裁后图片中的底座为准。

建筑目标底座投影宽度为 `16 * (w+h)` 像素；整张图片按 `目标宽度/ground_width_px*scale` 等比缩放，高度不限制为一格。缩放使用最近邻。

## 地图数据

```json
{
  "buildings": [
    {"instance_id": "tower_001", "asset_id": "tower_front", "x": 4, "y": 4, "rotation": 0}
  ],
  "user_assets": {
    "tower_front": {"id": "tower_front", "kind": "building", "render": {}},
    "tower_back": {"id": "tower_back", "kind": "building", "render": {}}
  }
}
```

这里的素材描述符只是结构示意；正式描述符还包括图片内容哈希、尺寸、来源等字段，由素材服务生成。

`x/y` 是旋转后占地矩形的左上格，渲染落在该矩形中心。放置必须全范围界内、底面等高，并且不与其他建筑或单位重叠。建筑占地阻止单位站立、移动和寻路；建筑高度不抬升地形。保存地图时保留正面和背面素材的描述符快照；图片文件仍由本机素材库提供，迁移机器时需同时迁移素材库。

## 生成真实塔楼示例

在工程目录执行纯 headless 工具（不会打开游戏或截图）：

```bash
D:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/prepare_building_demo.gd
```

工具将真实塔楼导入本机素材库，并保存战场 `building_demo`（名称“建筑视觉验收：石塔”）。本次已生成 `res://data/battlefields/building_demo.json`；工程目录不可写时，保存逻辑会回退到 `user://battlefields/`。已有相同图片时复用素材；示例快照使用初始标定值，保留已有素材库中的用户参数。重复执行会更新这个专用示例地图。

如有真正的背面图，可显式传入：

```bash
D:/Godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/prepare_building_demo.gd -- --back=E:/assets/tower_back.png
```

不提供背面图时只创建无背面示例，不会把正面图伪装成背面。

## 编辑操作与代码验证

在素材面板将导入类型选为“建筑”，选中建筑素材后在地图上放置。`T` 旋转当前建筑方向；橡皮擦命中占地内任一格会删除整栋建筑。支持撤销、重做、地图保存加载，以及完整选中建筑后的区域复制和移动。命名区域预设暂不包含建筑，保存前会明确提示。

2026-11-17 已完成 15 项相关契约，结果均为 pass：`building_layout`、`building_visual`、`map_editor_building`、`battle_movement`、`battle_save`、`battlefields`、`editor_region_clipboard`、`editor_selection`、`map_editor`、`map_editor_region_ops`、`map_editor_ui`、`reinforcement`、`user_asset_catalog`、`user_asset_editor`、`user_asset_runtime`。报告位于 `.tmp/building_final/summary.tsv` 与 `junit.xml`。

另外对主场景执行了运行时加载编译检查，并用真实示例校验 B2 建筑视觉注入、地面占用和四象限相机同步。检查采用 headless，不截图。测试日志未发现脚本、解析或编译错误；部分既有测试退出时仍报告资源未释放，尚不能声称整个工程没有资源生命周期问题。

真实塔楼只有正面图；有背面的切换分支使用测试生成的不同图片验证，仍需要真实前／背配图进行人工视觉验收。

## 人工视觉验收

代码契约通过后，在重新载入脚本的编辑器中打开 `res://scenes/MapEditor.tscn`，加载上述示例。先保存未保存的编辑器工作，再按项目约定重启编辑器刷新脚本缓存。

1. 塔楼整图可见，底座贴住地面，塔身保持原图比例，透明背景不出现矩形底色。
2. 占地是 2×2；图像可向上和侧面超出占地范围。调整 `pivot` 与底座标定宽度，检查建筑是否悬空或扎地。
3. 在四个正交视角查看：无背面图一直可见；有背面图的示例按相对象限切图，缺背图回退正面。
4. 检查放置预览、越界／重叠拒绝，以及删除、撤销、重做、区域复制和移动是否整栋操作。
5. 保存再加载，检查方向、占地、素材引用与外观一致。
6. 进入该战场，检查角色绕开塔楼占地，人物靠近塔楼时的遮挡是否符合预期。

整张建筑图是一个平面，复杂交错遮挡存在表现边界；视觉验收应特别关注角色从塔后走到塔前的过程。当前阶段不以代码契约替代画面验收。
