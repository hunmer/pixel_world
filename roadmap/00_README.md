# 可自定义剧情 × 可自定义地图 —— 功能路线图（战棋版）

> 目标形态：可自定义 div 剧情和地图的**回合制战棋**游戏，呈现方式类似《八方旅人》（HD-2D 观感、章节化剧情、Boss 战演出）。核心扩展方向：**元素系统 + 地形效果 + 两者交互**。
>
> 现有基础（可复用资产）：
> - 回合制战棋战斗（B1 就地 / B2 独立场景，`scripts/core/` + `scripts/systems/`）
> - 战场地图编辑器（`scripts/editor/`，按 E，JSON 存取 `user://battlefields/`，11 种地形）
> - 技能/物品/职业系统（`data/skills.json`、`items.json`、`professions.json`）
> - `story/` 目标态设计 bible（13 职业 / 27 技能 / 25 道具）
> - 确定性无限生态世界（`main.gd` + `scripts/world|ecology/`）
>
> 文件按难度从低到高编号；每个文件含【功能】【难度】【详细描述】三部分。
> 建议实施顺序即编号顺序：01 → 13。
