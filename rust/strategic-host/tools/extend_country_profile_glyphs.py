"""Add missing country-profile and other HUD text to the embedded glyph strip."""

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main():
    repo = Path(__file__).resolve().parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base_atlas", type=Path, help="the runtime data/hud-type.json")
    parser.add_argument("--font", type=Path, default=repo / "assets/fonts/map/SourceHanSerifCN-Regular.otf")
    parser.add_argument("--text", action="append", default=[], help="additional HUD text to include")
    args = parser.parse_args()

    profile_path = repo / "data/world_map/historical/major_state_profiles_1900.json"
    glyph_path = repo / "data/character/hud-glyphs.json"
    image_path = glyph_path.with_suffix(".png")
    profiles = json.loads(profile_path.read_text(encoding="utf-8"))["profiles"]
    base = json.loads(args.base_atlas.read_text(encoding="utf-8"))
    glyphs = json.loads(glyph_path.read_text(encoding="utf-8"))
    text = "".join(row.get("opening_brief_zh") or row.get("brief_zh", "") for row in profiles)
    text += "".join(args.text)
    missing = sorted({ch for ch in text if not ch.isspace()
                      and f"0:{ch}" not in base and f"0:{ch}" not in glyphs})
    if not missing:
        return

    with Image.open(image_path) as source:
        image = source.convert("RGBA")
    font = ImageFont.truetype(str(args.font), 15)
    draw = ImageDraw.Draw(image)
    base_height = 2048
    cell_height = 22
    last_row = max(v for _, v, _, _, _ in glyphs.values())
    x = max(u + w for u, v, w, _, _ in glyphs.values() if v == last_row) + 1
    y = last_row - base_height
    for ch in missing:
        advance = max(1, round(font.getlength(ch)))
        cell_width = advance + 6
        if x + cell_width > image.width:
            x = 1
            y = max(v + h for _, v, _, h, _ in glyphs.values()) - base_height + 1
        if y + cell_height > image.height:
            raise ValueError("glyphs exceed the embedded HUD strip")
        draw.text((x + 2, y + 17), ch, font=font, anchor="ls", fill=(255, 255, 255, 255))
        glyphs[f"0:{ch}"] = [x, y + base_height, cell_width, cell_height, advance]
        x += cell_width + 1

    image.save(image_path)
    entries = [f"  {json.dumps(key, ensure_ascii=False)}: {json.dumps(rect)}"
               for key, rect in glyphs.items()]
    glyph_path.write_text("{\n" + ",\n".join(entries) + "\n}\n", encoding="utf-8")
    print(f"Added {len(missing)} HUD glyphs")


if __name__ == "__main__":
    main()
