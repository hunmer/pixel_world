#!/usr/bin/env python3
"""gen_art_registry.py — 生成 assets/art/character_art_registry.json：角色 → 三视图立绘路径，与 voice_registry.json 配套。"""
import os, json, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
UNITS = os.path.join(ROOT, "assets", "units")

# key -> (中文名, 最终采用图, 备选/历史版本)
CHARS = {
	"elf_companion": ("精灵同伴", "elf_companion/elf_turnaround_adult_v1.png",
	                  ["elf_companion/elf_turnaround_v1.png", "elf_companion/elf_turnaround_v2.png",
	               "elf_companion/elf_turnaround_v3.png", "elf_companion/elf_turnaround_v4.png"]),
	"hero": ("主角", "hero/hero_turnaround_v2.png", ["hero/hero_turnaround.png"]),
	"veteran": ("老将副官", "veteran/veteran_turnaround.png", []),
	"mercenary": ("佣兵弓手", "mercenary/mercenary_turnaround.png", []),
	"pegasus": ("天马斥候", "pegasus/pegasus_turnaround.png", []),
	"priest": ("随军司祭", "priest/priest_turnaround.png", []),
	"hierarch": ("神权国圣座", "hierarch/hierarch_turnaround_v2.png", ["hierarch/hierarch_turnaround.png"]),
	"demon": ("恶魔君主", "demon/demon_turnaround.png", []),
}

def img_size(p):
	try:
		out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", p],
		                     capture_output=True, text=True).stdout
		w = h = None
		for line in out.splitlines():
			if "pixelWidth" in line: w = int(line.split()[-1])
			if "pixelHeight" in line: h = int(line.split()[-1])
		return w, h
	except Exception:
		return None, None

registry = {"meta": {"style": "anime cel-shading, three-view turnaround (front/side/back)",
                     "model": "Lib Image 2.6 Pro",
                     "proportion_rule": "adult 1:7.5, not chibi",
                     "source": "libtv canvas pixel_world_配音音色 (projectId f43636c0a17f41279d0a307adc87f9ff)",
                     "companion": "res://assets/audio/voice/voice_registry.json",
                     "notes": "alt 版本为弃用候选（幼态/缺特征），仅备查"},
            "characters": {}}
for key, (name, main, alts) in CHARS.items():
	p = os.path.join(UNITS, main)
	w, h = img_size(p)
	registry["characters"][key] = {
		"name_cn": name,
		"turnaround": f"res://assets/units/{main}",
		"size": [w, h],
		"alt": [f"res://assets/units/{a}" for a in alts if os.path.exists(os.path.join(UNITS, a))],
	}

out = os.path.join(ROOT, "assets", "character_art_registry.json")
with open(out, "w", encoding="utf-8") as f:
	json.dump(registry, f, ensure_ascii=False, indent=2)
print(out, "| characters:", len(registry["characters"]))
