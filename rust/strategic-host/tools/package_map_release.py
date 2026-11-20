"""Package the retained regional map for the Windows game's versioned loader."""

import argparse
import json
import shutil
from pathlib import Path
from tempfile import TemporaryDirectory


VERSION = "regional-2026-11-14"
LEGACY_SIGNATURE = b"WWOCM2\0\0"
TILE_SIGNATURE = b"WWORGN1\0"
ART = (
    "political-flags-hd.png",
    "galactic-chart.png",
)


def read_json(path):
    return json.loads(path.read_bytes())


def write_release_json(path, document):
    document["map_release"] = VERSION
    path.write_text(json.dumps(document, ensure_ascii=False, separators=(",", ":")),
                    encoding="utf-8")


def package(source, data):
    world = read_json(source / "world.json")
    paths = [tile["path"] for tile in world["tiles"]]
    if (len(paths) != 638 or len(set(paths)) != 638 or paths[0] != "world.wcm"
            or sum(name.startswith("tiles/r68-surface-") for name in paths) != 282
            or world["tiles"][0]["source"] != "World / R68 ETOPO relief"):
        raise ValueError("expected the retained 2026-11-14 regional map source")
    visuals = read_json(source / "political-flags.json")
    if [row["id"] for row in world["polities"]] != [row["id"] for row in visuals["polities"]]:
        raise ValueError("political visuals and map identities differ")

    maps = data / "maps"
    maps.mkdir(parents=True, exist_ok=True)
    release = maps / VERSION
    if release.exists():
        raise FileExistsError(release)
    with TemporaryDirectory(dir=maps) as temp:
        stage = Path(temp) / VERSION
        (stage / "tiles").mkdir(parents=True)
        for name in paths:
            path = Path(name)
            if path.suffix != ".wcm" or (name != "world.wcm" and path.parent != Path("tiles")):
                raise ValueError(f"invalid tile path {name}")
            with (source / path).open("rb") as original, (stage / path).open("wb") as output:
                if original.read(8) != LEGACY_SIGNATURE:
                    raise ValueError(f"expected WWOCM2 in {name}")
                output.write(TILE_SIGNATURE)
                shutil.copyfileobj(original, output)
        for name in ART:
            with (source / name).open("rb") as original, (stage / f"{name}.wwo").open("wb") as output:
                output.write(VERSION.encode("ascii"))
                shutil.copyfileobj(original, output)
        write_release_json(stage / "political-flags.json", visuals)
        write_release_json(stage / "world.json", world)
        stage.rename(release)
    return release


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("retained_map_data", type=Path)
    parser.add_argument("game_data", type=Path)
    args = parser.parse_args()
    print(package(args.retained_map_data, args.game_data))
