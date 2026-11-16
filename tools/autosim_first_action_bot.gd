## autosim_first_action_bot.gd — 最简 bot 策略：永远选第一个可用动作（试点用）
#
# 本试点中适配器只暴露一个 "auto_play" 动作（整场战斗由战斗侧 AI 自动对局），
# 因此任何 bot 策略都等价；此实现直接返回首个可用动作，保持框架调用链完整。
extends AutoSimBotStrategy


func reset() -> void:
	pass


func choose_action(_state: Variant, available_actions: Array) -> Variant:
	if available_actions.is_empty():
		return null
	return available_actions[0]
