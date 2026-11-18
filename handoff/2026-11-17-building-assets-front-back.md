# 建筑四方向素材、视觉修正与可进入房屋交接（更新于2026-11-18）

## 当前状态与下一步

本文件沿用原文件名，内容已替换为当前实现。用户明确要求更新此工程路径，优先于 handoff 技能默认的系统临时目录。

本次需求先将旧单图／正背图建筑改为只接受真正四方向精灵图，接入用户提供的瞭望塔；随后根据用户截图依次修正锚点、地面裁切、投影角度、清晰度、角色遮挡。用户确认对齐与遮挡效果后，授权实现“大房屋可进入、可放室内角色、放大查看内部”的第一版。目前这些工作均已实现并完成针对性验证，没有待执行的开发承诺。

下一会话以用户视觉反馈和后续要求为准。可优先让用户试用内置“宽敞单层房屋”和室内示例，再按反馈调整美术或功能；不要自动扩展为多楼层、独立屋顶图层或房间绘制面板。没有重启用户正在使用的编辑器，没有截图或推送远端；继续遵守此前先代码验证、由用户验收视觉的约定。

## 事实来源与入口

完整操作、字段和限制直接参考 [建筑说明](../docs/building_assets.md)，不要重复按本文件重新设计接口。

- 素材格式、导入与UI：[catalog](../scripts/assets/user_asset_catalog.gd)、[service](../scripts/assets/user_asset_service.gd)、[素材面板](../scripts/editor/asset_library_panel.gd)。
- 快照解析与源纹理：[适配器](../scripts/assets/user_asset_visual_adapter.gd)。
- 建筑占地与室内逻辑：[building_layout](../scripts/core/building_layout.gd)、[building_interior](../scripts/core/building_interior.gd)。
- 编辑器与战场共用：[renderer](../scripts/iso/battlefield_renderer.gd)、[室内几何](../scripts/iso/building_interior_view.gd)、[3D地形](../scripts/iso/isometric_terrain_3d.gd)、[建筑遮挡](../scripts/iso/building_occlusion_controller.gd)。
- 编辑与保存加载：[文档模型](../scripts/editor/battlefield_doc.gd)、[加载器](../scripts/core/battlefield_loader.gd)、[Grid](../scripts/systems/grid_system.gd)。
- 内置注册：[瞭望塔](../scripts/assets/builtin_building_assets.gd)、[单层房屋](../scripts/assets/builtin_house_assets.gd)，统一在 [编辑器初始化](../scripts/scenes/map_editor.gd) 接入。
- 示例：[瞭望塔地图](../data/battlefields/building_demo.json)、[室内地图](../data/battlefields/house_interior_demo.json)；对应 [塔准备工具](../tools/prepare_building_demo.gd)、[房屋准备工具](../tools/prepare_house_demo.gd)。工具会重写专用示例，若用户开始编辑示例，应先保留其改动。

## 已确定的契约与踩坑

### 四方向输入与兼容

建筑仅接受4:1横排sheet，四个等大正方形帧从左至右为dir_0..3；`render.direction_mode="four_directions"`、`mode="full"`、`crop=null`。不再支持旧`back_mode/back_asset_id`，也不复制单图伪造四帧。旧建筑库记录隔离保留到`legacy_buildings`，不进入新建筑列表；普通地形、植物导入不受影响。

帧选择为`posmod(camera_quadrant - rotation, 4)`。地图实例仍为`{instance_id,asset_id,x,y,rotation}`；x/y表示旋转后占地矩形左上格。单栋只引用一个自包含描述符快照。工程内置资源可在空用户库下按source路径和SHA校验离线读取。

### 锚点、投影与清晰度

游戏是yaw45°／pitch30°的32×16 dimetric投影。用户原素材pitch45°与游戏地面不匹配；已经用建筑工具CLI重导出pitch30°版本，不要换回原45°图片。

四帧使用统一的完整画布坐标锚点`pivot_space="frame"`；按每帧alpha包围盒计算会因挑檐不同而漂移。原512px纹理完整保留，`display_scale`控制实际显示尺寸，BAKED_VERSION=5；不要重新把源帧预缩小至约140px，否则镜头放大模糊。3D quad、2D绘制、淡化代理都继承相同比例。

建筑底座中心以下仍有透明图里的可见像素，直接放地面会被深度裁切。`_building_depth_offset`沿正交视线调整深度，保证屏幕锚点不动并保留深度测试；不要用禁用深度测试解决。遮挡计算必须使用修正后的实际绘制center，而不是原始grid anchor。

角色遮挡通过共享控制器按实际比例、纹理alpha和深度检测，挡住角色时淡至20%，离开后恢复；兼容多角色、重建和战斗特写锁。用户已确认这轮遮挡有效。

## 当前内置素材

素材导出工具工程为`/Users/Zhuanz/parametric-topdown-pixel-architecture`，仅通过其CLI生成，遵守该工程AGENTS和cli/README；不需要修改生成器源码。

| 素材 | 当前文件／标定 |
| --- | --- |
| 中世纪瞭望塔 | [sheet](../assets/buildings/medieval_watchtower/sheet.png)、[recipe](../assets/buildings/medieval_watchtower/recipe.json)；2048×512，占地2×2，ground_width_px=232.44195804706033，frame pivot=(0.5068258805742822,0.8142657649984744) |
| 宽敞单层房屋 | [sheet](../assets/buildings/spacious_house/sheet.png)、[recipe](../assets/buildings/spacious_house/recipe.json)；2048×512，占地6×6，ground_width_px=404.91010711440094，frame pivot=(0.5025193634904326,0.6697540881141923) |

原文件SHA-256（不能用图片工具的预览／重编码哈希替代）：

- 瞭望塔：`3a44869debc92e0d7bbdd3811320e1500611cb549021b355ca9eeee60cb5a377`。
- 房屋：`25b3ae98b249b5896dc90b5b37db3db8e494454cf384200f9e9ef18fd2653734`。

房屋为`castle_medieval house`，8×8米、单层、无阳台／门廊、yaw45／pitch30、正交四向512、关闭抗锯齿。内置注册保留用户名称与已有标定。原始用户素材路径`/Users/Zhuanz/Downloads/4fed27c02007c01d 2/p45_4d`只用于溯源；运行不依赖Downloads。CLI临时导出在`.tmp/watchtower_p30/`和`.tmp/spacious_house_export/`，不是运行时依赖。

## 可进入房屋第一版

已实现同地图、单层、真实格子室内。布局由`render.interior`配置并随素材快照保存；具体schema和示例见建筑说明。内置布局为6×6边界低墙、两格门口、一个桌子，室内地板留有连通走道。

- `BuildingLayout.occupied_cells/occupancy`仍表示完整footprint，用于建筑重叠、边界与区域选择；`blocking_cells/blocking_occupancy`仅对进入式房屋的`#`墙和`F`家具阻挡，旧塔保持全占地阻挡。
- `BuildingInterior.cell_at(entry,local,size)`统一0..3旋转；门、家具、碰撞和剖面保持一致。门和地板允许放角色，寻路经过门进入。
- 校验布局尺寸、字符、非角落边界门、全部通路连门、有限缩放阈值与平地高度。底层地形通行属性保留，室内地板不会把水域自动变得可走。
- 近景zoom≥1.8隐藏完整外壳，显示真实木地板、低墙和桌子；远景zoom≤1.5恢复外观，中间区间保持原状态。只切显示，不改变逻辑／存档。地板贴`visual_top_level`，不能用`stand_level`把它抬高一层。
- `IsoBoard`会平滑更新camera.zoom；运行时测试缩放需设置board的`_target_zoom`，仅改camera.zoom会被下一帧恢复。
- 当前是直接显隐，不是屋顶逐层淡出；无多楼层、室内灯光或房间绘制面板。数据可配置，UI暂只保留室内元数据而不提供布局绘制。占地内植物仅在表现层隐藏。

用户试用：重新加载脚本后在【地形→建筑】选择“宽敞单层房屋”，T旋转；或打开室内示例，房屋origin=(4,3)，友军(7,6)在室内，敌军(7,9)在门外。未替用户重启编辑器，因此其已有运行实例可能仍使用旧脚本。

## 验证记录与边界

本轮macOS实际Godot为`v4.7.1.stable.official.a13da4feb`，二进制`/Applications/Godot.app/Contents/MacOS/Godot`；不要把旧文档的Windows4.7.2结果当作本轮证据。纯headless契约按godot-debug允许的路径运行，相关测试已加入 [manifest](../tests/contract_manifest.json)。

- [室内逻辑契约](../tests/building_interior_contract.gd)：PASS 95 checks，含schema、四向旋转、门口寻路、家具阻挡、编辑器真实放角色、水域保留、平地和JSON往返。
- [室内渲染契约](../tests/building_interior_visual_contract.gd)：PASS 209 checks，含四实例旋转×四相机、真实地板／墙／桌子、门格一致、外壳移除恢复、滞回、重建与删除清理。
- [房屋注册契约](../tests/builtin_house_assets_contract.gd)：PASS 24 checks；示例生成`HOUSE_DEMO_PASS`。
- 原有building_layout、map_editor_building（18 sections）、building_visual、map_editor_building_palette均PASS；building_occlusion回归PASS 37 checks；最终`git diff --check`通过。
- MCP独立headless peer-13加载MapEditor及室内示例成功，`runtime_assert_node_state`确认室内1间可见；设置board缩放后`runtime_await_condition`确认远景0／近景1，加载切换期间无新增error。验证peer已停止，用户9081游戏未触碰。

早期渲染测试曾因新脚本常量名`Projection`撞Godot内置类型出现解析错误，已改为`IsoProjection`并重跑通过；不能把那次exit0误判为无错误。当前扫描以最终重跑输出为准。素材库仍有“隔离保留2条旧建筑”的预期warning，部分历史测试有退出资源泄漏warning；不宣称全工程无错。没有运行全量测试，也未做本轮室内截图／人工美术验收。

## Git与继续工作约束

更新本交接前现场核实：`git status --short`为空，最新提交为`7fe2130 fix`、`e5eed65 fix`，再往前为`75944bd`、`f20e7a9`、`91abc71`。因此不能继续沿用旧交接“这批功能仍全部未提交”或“用户某文件仍有两行修改”的说法。当前会话没有执行commit或push；这两个最新提交的创建者／提交过程不在本会话记录中，应以git实际历史为准。此次只更新本交接文件。

本轮两个子代理house-layout／house-asset已完成，无待收集任务或运行中的验证peer。旧team记录属于历史工作，不需重建或重复派发。不要`git add .`或无差别提交临时导出、日志、备份；不要reset／stash／checkout覆盖用户工作。遵守根AGENTS／CLAUDE：tab缩进、模块化、不往main.gd追加业务分支、UI走组件和token、只测相关范围。Codegraph当前可用；其file模式曾拒绝空symbol，可用explore或针对性Read回退，别把旧“没有索引”的记录当现状。

## Suggested skills（建议技能）

- **godot-debug**：[技能文件](../.dsh/skills/godot-debug/SKILL.md)。运行、调试、画面或验证前必读；交互运行走MCP，纯headless契约按技能执行。连接是否需要激活，以当前会话实际工具和上层规则为准，不擅自重启用户编辑器。
- **handoff**：[技能文件](../.claude/skills/handoff/SKILL.md)。后续更新此交接时使用，用户已明确指定本文件位置。
- **dsh-agent-team**：只有确需团队协作或用户要求时加载；明确文件所有权，勿沿用历史成员模型配置作为当前授权。
