"""按实际技能绑定生成图标验收预览。"""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
skills = json.loads((ROOT / "data/skills.json").read_text(encoding="utf-8"))["skills"]
extra = {"51": "power_surge.png", "52": "guard.png", "53": "haste.png"}
preview = Image.new("RGB", (len(skills) * 144, 178), (22, 24, 30))
draw = ImageDraw.Draw(preview)
for i, skill in enumerate(skills):
    icon_id = skill["iconId"]
    filename = extra.get(icon_id, f"{icon_id}.png")
    icon = Image.open(ROOT / "assets/ui/skills" / filename).convert("RGBA")
    icon = icon.resize((112, 112), Image.Resampling.NEAREST)
    x = i * 144 + 16
    preview.paste(icon, (x, 12), icon)
    draw.text((x, 134), skill["id"], fill=(238, 239, 243))
    draw.text((x, 151), f"iconId: {icon_id}", fill=(175, 186, 205))
preview.save(OUT / "bound_skills_preview.png")
print(OUT / "bound_skills_preview.png")
