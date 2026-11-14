"""Pack the existing R68 artwork and the Chinese glyphs used by the HUD."""
import json
import re
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

base = Path(__file__).resolve().parents[1]
r68 = Path(sys.argv[1])
data = Path(sys.argv[2])
painting = Image.open(r68 / "assets/menu/paris_street_rainy_day_1877.jpg").convert("RGBA")
painting.thumbnail((1600, 1000), Image.Resampling.LANCZOS)
painting.save(data / "menu-painting.png")
src = r68 / "assets/ui/instrument_reference"
canvas = Image.new("RGBA", (1024, 1024))
rectangles = {}


def artwork(key, source, position, size, crop=None, reference=None):
    image = Image.open(source).convert("RGBA")
    if crop:
        image = image.crop(tuple(round(v * image.size[i % 2] / reference[i % 2]) for i, v in enumerate(crop)))
    image = image.resize(size, Image.Resampling.LANCZOS)
    canvas.paste(image, position)
    rectangles[key] = [position[0], position[1], *size]


artwork("clock", src / "dial_compact.png", (0, 0), (232, 232))
artwork("portrait", src / "portrait.png", (240, 0), (176, 248), (27, 12, 981, 1458), (1024, 1536))
for i, key in enumerate(("accounts", "belongings", "relations")):
    artwork(key, src / f"{key}.png", (424 + i * 84, 0), (76, 84), (77, 24, 1177, 1224), (1254, 1254))
artwork("messages", src / "message_handle.png", (688, 0), (72, 244), (379, 125, 749, 1390), (1024, 1536))
artwork("crest", src / "folio.png", (0, 272), (388, 110), (186, 0, 901, 202), (1086, 1448))
artwork("country_crest", src / "politics.png", (400, 272), (412, 96), (130, 0, 950, 190), (1086, 1448))
artwork("market_crest", src / "market.png", (0, 920), (388, 96), (138, 0, 948, 190), (1086, 1448))
artwork("land", r68 / "assets/maps/instrument/land_coarse.png", (0, 400), (1024, 512))
symbols = r68 / "assets/ui/map_symbols"
catalog = json.loads((symbols / "symbols.json").read_text(encoding="utf-8"))
atlas = Image.open(r68 / catalog["atlas"].removeprefix("res://")).convert("RGBA")
for i, (key, icon) in enumerate(catalog["icons"].items()):
    x, y, w, h = icon["rect"]
    position = (416 + i * 32, 920)
    image = atlas.crop((x, y, x+w, y+h)).resize((30, 30), Image.Resampling.LANCZOS)
    canvas.paste(image, position)
    rectangles["map_" + key] = [*position, 30, 30]
canvas.save(data / "hud-art.png")
(data / "hud-art.json").write_text(json.dumps(rectangles, separators=(",", ":")), encoding="utf-8")
(data / "map-symbols.json").write_text(json.dumps(catalog["icons"],separators=(",",":")),encoding="utf-8")

maps = r68 / "assets/maps"
shutil.copyfile(r68 / "data/presentation/economic_structure_1900.json", data / "economic-structure-r68.json")
messages = json.loads((r68 / "data/presentation/localization/messages_en.json").read_text(encoding="utf-8"))
for entry in json.loads((r68 / "data/presentation/localization/names.json").read_text(encoding="utf-8")).values():
    for field in ("name", "capital"):
        zh, en = entry.get("zh", {}).get(field), entry.get("en", {}).get(field)
        if zh and en:
            messages[zh] = en
messages.update({"军事地图": "Military map", "打开市场": "Open market",
                 "R68 规则兼容 · Rust 候选": "R68 compatibility · Rust candidate",
                 "再次点击当前模式可返回基础地貌": "Select the active mode again to return to terrain"})
(data / "messages-en-r68.json").write_text(json.dumps(messages, ensure_ascii=False), encoding="utf-8")
Image.open(maps / "background/galactic_chart.png").convert("RGBA").save(data / "galactic-chart.png")
ocean = maps / "ocean/orbital_r24"
for name, source in (("detail", "pelagic_eddies_albedo.png"), ("ice", "polar_pack_ice_albedo.png")):
    # R68's imported originals have mip generation disabled.
    Image.open(ocean / source).convert("RGBA").save(data / f"ocean-{name}-r68.png")

glyph_sources = [base / "src/formal_ui.rs", base / "src/market_ui.rs", base / "src/lobby.rs",
                 base / "src/migration_status.rs", base / "src/formal_character.rs",
                 base / "tools/formal_host_bridge.gd", base / "tools/formal_market_bridge.gd"]
glyph_sources += [base.parent / "character-core/src/health.rs", base.parent / "character-core/src/action.rs"]
glyph_sources += [r68 / "scripts/formal/formal_rust_character.gd"]
glyph_sources += list((r68 / "scripts/presentation/ui").glob("*.gd"))
glyph_sources += [r68 / "scripts/content/technology_pilot.gd", r68 / "scripts/persistence/formal_persistence.gd"]
glyph_sources.append(r68 / "scripts/content/france_market_goods.gd")
glyph_sources += [r68 / "scripts/formal/formal_world_menu.gd", r68 / "scripts/content/world_bootstrap.gd"]
glyph_sources += list((r68 / "data/local").glob("*.json"))
chars = set()
for path in glyph_sources:
    chars.update(re.findall(r"[\u3000-\u9fff\uff00-\uffef−×—·]", path.read_text(encoding="utf-8")))
world = json.loads((data / "world.json").read_text(encoding="utf-8"))
for group in ("polities", "places"):
    for record in world[group]:
        chars.update(record.get("name_zh", ""))
chars.update(chr(i) for i in range(32,127))
font_path = r68 / "assets/fonts/map/SourceHanSerifCN-Regular.otf"
latin_path = r68 / "assets/fonts/map/EBGaramond-Medium.ttf"
glyphs = {}
canvas = Image.new("RGBA", (2048, 2048), (255, 255, 255, 0))
pen = ImageDraw.Draw(canvas)
x, y, row = 1, 1, 0
settings_chars = set("主音量地图名称开启关闭语言简体中文窗口全屏返回−＋·%?设置") | set(chr(i) for i in range(32,127))
for font_id, size in enumerate((15, 20, 24, 13, 10, 13, 11, 12)):
    serif = ImageFont.truetype(str(font_path), size)
    latin = ImageFont.truetype(str(latin_path), size)
    font_chars = chars if font_id < 3 else settings_chars if font_id >= 5 else "0123456789:月日—?"
    button_font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", size) if font_id == 6 else None
    for char in sorted(font_chars):
        font = button_font or (latin if char.isascii() and 0 < font_id < 5 else serif)
        width = max(1, round(font.getlength(char)))
        cell_w = width + 6
        cell_h = size + 7
        if x + cell_w > canvas.width:
            x, y, row = 1, y + row + 1, 0
        if y + cell_h > canvas.height:
            raise ValueError("HUD glyph atlas exceeds its page")
        pen.text((x + 2, y + size + 2), char, font=font, anchor="ls", fill=(255,255,255,255))
        glyphs[f"{font_id}:{char}"] = [x, y, cell_w, cell_h, width]
        x += cell_w + 1
        row = max(row, cell_h)
canvas.save(data / "hud-type.png")
(data / "hud-type.json").write_text(json.dumps(glyphs, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
