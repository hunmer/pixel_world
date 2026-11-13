# 11 · Boss 战：盾牌点数与弱点演出

【功能】
八方旅人式 Boss 战：Boss 带「盾牌点数」（shield points）与明确的弱点元素集合，集火弱点破盾 → 打断 Boss 行动进入眩晕；配合登场演出（名牌横幅、镜头推拉、BGM 分段）—— 元素系统（01）的最终展示舞台。

【难度】★★★★★（困难）

【详细描述】
- Boss 定义扩展单位 schema：`{ "phases":[{"hp_pct":100,"shield":3,"weak":["fire","ice"]},{"hp_pct":50,"shield":5,"weak":["thunder"]}], "skills":[...] }`；每回合开始盾牌点数回满，命中弱点元素 -1 点，归零 → 眩晕一回合并跳过 Boss 行动（即「打断」）。
- 盾牌 UI：Boss 头顶盾牌图标 + 数字，弱点未探明显示 `?`，命中一次后点亮 —— 八方旅人的核心探索乐趣。
- 与地形交互联动：Boss 站在水域时对雷弱点判定加成（03 规则自动生效），关卡设计把「引导 Boss 走进雷云区再集火」做成教学战。
- 演出层 `scripts/battle/boss_presentation.gd`：登场横幅（Boss 名 + 称号黑底金字）、Camera3D 推拉（复用 `scripts/iso/` 相机，遵守 4 正交角度约定）、破盾震屏 shader（`shaders/` 已有工程先例）、BGM 分段切换（`world_audio_system.gd` 加 `play_boss_phase(n)`）。
- 技能系统对接：Boss 技能直接复用 `data/skills.json` + `scripts/systems/` 结算，不另造伤害管线；`story/` bible 里 27 技能优先挑 6–8 个做 Boss 招式。
- 演出与逻辑解耦：演出层只订阅逻辑信号（`boss_phase_changed` / `shield_broken`），纯逻辑可 headless 测试。
- 验证：契约测试覆盖阶段切换阈值、盾牌刷新与破碎判定、弱点探明状态；演出层用 `runtime_assert_*` 验证信号触发。
