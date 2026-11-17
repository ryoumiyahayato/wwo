"""Refresh the bounded military source snapshot from one committed military tree.

No binary assets, hashes, engine run, commit or push. Rules are edited in wwo-military;
this command only applies the recorded namespace/resource adaptations.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
RECEIPT = ROOT / 'military_runtime/NATIVE_SOURCE.json'
NATIVE = 'military_runtime/native/'
SOURCE = 'military-godot/'
RENDER = {
    'modules/region_observation/layered_terrain.gd': 'scripts/presentation/terrain/layered_terrain.gd',
    'modules/region_observation/terrain_height_source.gd': 'scripts/presentation/terrain/terrain_height_source.gd',
    'modules/region_observation/layered_ground.gdshader': 'shaders/presentation/terrain/layered_ground.gdshader',
}
RESOURCE_ADAPTATIONS = {
    'ridgevale/heightfield.gd': ['ridgevale/assets/'],
    'ridgevale/terrain.gd': ['ridgevale/assets/', 'cedar/assets/'],
    'ridgevale/world.gd': ['ridgevale/assets/', 'cedar/assets/'],
}


def git(repo: Path, *args: str) -> bytes:
    return subprocess.check_output(['git', '-C', str(repo), *args])


def source_text(repo: Path, commit: str, relative: str) -> str:
    return git(repo, 'show', f'{commit}:{SOURCE}{relative}').decode('utf-8').replace('\r\n', '\n').rstrip('\n') + '\n'


def adapt(relative: str, text: str) -> tuple[str, str]:
    if relative in RENDER:
        if relative.endswith('layered_terrain.gd'):
            text = text.replace('res://modules/region_observation/terrain_height_source.gd', 'res://scripts/presentation/terrain/terrain_height_source.gd')
            text = text.replace('res://modules/region_observation/layered_ground.gdshader', 'res://shaders/presentation/terrain/layered_ground.gdshader')
            text = text.replace('DEFAULT_BASE_PATH: String = "res://"', 'DEFAULT_BASE_PATH: String = "res://assets/terrain/region_slice/"')
        return RENDER[relative], text
    # A bare URI scheme (e.g. begins_with("res://")) is logic, not a path.
    text = re.sub(r'res://(?=[A-Za-z0-9_%.])', 'res://military_runtime/native/', text)
    for folder in RESOURCE_ADAPTATIONS.get(relative, []):
        text = text.replace('res://military_runtime/native/' + folder, 'res://assets/terrain/region_slice/' + folder)
    return NATIVE + relative, text


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-repo', type=Path, required=True)
    parser.add_argument('--commit', required=True, help='Committed military source, never a dirty WORKTREE')
    parser.add_argument('--apply', action='store_true', help='Default previews changed paths only')
    args = parser.parse_args()
    receipt = json.loads(RECEIPT.read_text(encoding='utf-8'))
    previous = receipt['military_commit']
    commit = git(args.source_repo, 'rev-parse', args.commit + '^{commit}').decode().strip()
    paths = set(receipt['source_paths']) | set(RENDER)
    original_paths = set(paths)
    sources: dict[str, str] = {}
    pending = list(sorted(paths))
    # Existing literal source dependencies only; no arbitrary folder mirroring.
    while pending:
        relative = pending.pop()
        if Path(relative).is_absolute() or '..' in Path(relative).parts:
            raise SystemExit('Unsafe source path: ' + relative)
        text = source_text(args.source_repo, commit, relative)
        sources[relative] = text
        for dependency in re.findall(r'[\"\']res://([^\"\']+\.(?:gd|gdshader))[\"\']', text):
            if '%' in dependency or '{' in dependency:
                continue  # Runtime-formatted paths are not literal dependencies.
            if dependency not in paths:
                paths.add(dependency)
                pending.append(dependency)
    changes: list[tuple[Path, str]] = []
    for relative in sorted(paths):
        destination, content = adapt(relative, sources[relative])
        target = ROOT / destination
        if target.exists():
            current = target.read_text(encoding='utf-8').replace('\r\n', '\n').rstrip('\n') + '\n'
            if current == content:
                continue
            if relative not in original_paths:
                raise SystemExit('Unrecorded existing destination: ' + destination)
            _, expected = adapt(relative, source_text(args.source_repo, previous, relative))
            if current != expected:
                raise SystemExit('Local source divergence; resolve it in military first: ' + destination)
        print(destination)
        changes.append((target, content))
    if args.apply:
        # Every source and destination was preflighted before writing any file.
        for target, content in changes:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding='utf-8', newline='\n')
        receipt['military_commit'] = commit
        receipt['source_paths'] = sorted(paths)
        RECEIPT.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f'{"Applied" if args.apply else "Preview"}: {len(changes)} changed source files; military {commit}')


if __name__ == '__main__':
    main()
