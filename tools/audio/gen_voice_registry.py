#!/usr/bin/env python3
"""gen_voice_registry.py — 生成 assets/audio/voice/voice_registry.json 映射表。
内容：8 角色 × 7 表情 → cut/ 独立文件路径 + 整段源文件 + 音色示例。"""
import os, json, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
VOICE = os.path.join(HERE, "..", "..", "assets", "audio", "voice")
EMOTIONS = ["attack", "hurt", "confused", "laugh", "shy", "cry", "panic"]
EMOTION_JA = {
    "attack": "攻撃のかけ声「えいっ！」",
    "hurt": "被弾「っ……！」",
    "confused": "疑惑「……どういうこと？」",
    "laugh": "笑い声「ふふっ」",
    "shy": "照れ「……そんな、勘違いしないで」",
    "cry": "泣き声「うっ……くっ……」",
    "panic": "驚きの大声「いやぁっ！？」",
}
CHARS = {
    "elf_companion": "精灵同伴（mage→sage）",
    "hero": "主角（recruitKnight→paladin）",
    "veteran": "老将副官（soldier→knight）",
    "mercenary": "佣兵弓手（archer→sniper）",
    "pegasus": "天马斥候（pegasusKnight）",
    "priest": "随军司祭（priest→bishop）",
    "hierarch": "神权国圣座（boss bishop）",
    "demon": "恶魔君主（boss knight/sage）",
}

def dur(p):
    return round(float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                       "-of", "csv=p=0", p], capture_output=True, text=True).stdout.strip()), 2)

registry = {"meta": {"language": "ja", "model": "seed-audio-1.0", "emo_order": EMOTIONS,
                     "source_note": "cut/ 由 *_battle_voices_ja.wav 按最长 6 静音切分；源文件保留"}, "characters": {}}
for c, cn in CHARS.items():
    entry = {"name_cn": cn,
             "sample": f"res://assets/audio/voice/voice_{c}_sample_ja.wav",
             "battle_all": f"res://assets/audio/voice/voice_{c}_battle_voices_ja.wav",
             "voices": {}}
    for e in EMOTIONS:
        p = os.path.join(VOICE, "cut", f"voice_{c}_{e}.wav")
        if os.path.exists(p):
            entry["voices"][e] = {"path": f"res://assets/audio/voice/cut/voice_{c}_{e}.wav",
                                  "line_ja": EMOTION_JA[e], "duration_s": dur(p)}
    registry["characters"][c] = entry

out = os.path.join(VOICE, "voice_registry.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(registry, f, ensure_ascii=False, indent=2)
total = sum(len(v["voices"]) for v in registry["characters"].values())
print(f"{out}\ncharacters={len(registry['characters'])} voices={total}")
