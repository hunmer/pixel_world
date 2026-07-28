## 任务：生成交接文档（handoff）

用户要求生成 handoff 交接文档，记录本次会话**已完成的工作**（不包含未完成功能）。

### 已完成的工作（本次会话 5 项改动）

1. **Heroes 立绘尺寸过大** — `scripts/iso/unit_sprite.gd`：`UNIT_VISUAL_PX` 64.0 → 32.0（缩到约 1 格高，匹配 32×26 地块）
2. **战旗光标位置偏差** — `main.gd` `screen_to_cell()`：增加 stand_level 高度补偿（修 60~150px 偏差）
3. **战旗模式无法操控地图** — `main.gd`：+3 字段、`_handle_battle_input` 放行缩放键、`_process` 解锁相机+边缘滚屏、+4 新函数（拖拽平移/边缘滚屏/钳制范围/避开UI）、进出战斗复位
4. **边缘滚屏方向反** — `main.gd` `_update_battle_edge_pan`：`offset -=` → `offset +=`
5. **右键查看单位详情面板** — `scripts/scenes/battle.gd`（右键拾取/ESC关闭/左键先关）+ `scripts/battle/battle_ui.gd`（+FACTION 常量、+open/close/is_unit_detail_open/_detail_label，完整属性面板）

### 文档内容规划
- 保存到 OS 临时目录（用户 home 的 temp），不污染工作区
- 记录每项改动的根因、修复方案、文件:行号
- 包含验收步骤
- suggested skills 部分
- **不包含**未完成的点击失效调查（用户明确说不包含未完成功能）

### 步骤
1. 退出 plan mode
2. 写 handoff 文档到 `C:\Users\Administrator\AppData\Local\Temp\pixel_world_handoff.md`