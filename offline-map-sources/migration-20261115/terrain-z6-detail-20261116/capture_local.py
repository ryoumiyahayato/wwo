"""Capture the Z6 candidate through the existing Rust offscreen observer."""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import uuid

STAGE = Path(__file__).resolve().parent
MIGRATION = STAGE.parent
Z6_SEAMS = MIGRATION / 'terrain-z6-seams-20261116'
Z7_DETAIL = MIGRATION / 'terrain-z7-detail-20261116'
BASELINE = STAGE / 'baseline-with-z7'
CANDIDATE = STAGE / os.environ.get('WWO_Z6_WORKING', 'candidate-final')
OBSERVE = Z7_DETAIL / 'z7-observe.exe'
NATIVE = Z7_DETAIL / 'z7-final-native.exe'

spec = importlib.util.spec_from_file_location('z7_capture', Z7_DETAIL / 'capture_local.py')
z7 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(z7)


class Host(z7.Host):
    def __init__(self, directory, pack, *, level=None, replay=False):
        self.directory = directory
        self.pack_name = pack.name
        self.directory.mkdir(parents=True)
        self.request = self.directory / 'map.json'
        self.response = self.directory / 'map.response.json'
        flags = ['--terrain-review', '--data', str(z7.DATA), '--terrain-candidate', str(pack),
                 '--observe', str(self.request)]
        if level is not None:
            flags.extend(['--terrain-level', str(level)])
        env = dict(os.environ, WWO_RUST_PROFILE='Z6Detail-' + uuid.uuid4().hex[:12])
        self.log = (self.directory / 'stderr.txt').open('wb')
        try:
            self.process = subprocess.Popen([str(OBSERVE if replay else NATIVE), *flags],
                                            env=env, stdout=self.log, stderr=self.log,
                                            creationflags=subprocess.CREATE_NO_WINDOW)
        except OSError:
            self.log.close()
            raise

    def replay(self, name, lon, lat, scales, moves=None, prewarm=True):
        super().replay(name, lon, lat, scales, moves, prewarm)
        path = self.directory / (name + '.json')
        receipt = z7.data(path)
        receipt['initial_selected_ready_requested'] = prewarm
        receipt['candidate_directory'] = self.pack_name
        z7.save(path, receipt)


def run_stills(output, suite):
    plan = z7.data(STAGE / 'z6-sample-plan.json')
    triptych_ids = {
        'ross-shelf', 'ronne-filchner-shelf', 'ross-shelf-front', 'amery-shelf',
        'antarctic-peninsula-west',
    }
    comparison = [(row['id'], (row['lon'], row['lat'], row['mpp']))
                  for row in plan['special'] if row['id'] in triptych_ids]
    if suite in ('all', 'shelves'):
        for label, pack, level in [
            ('shelves-old-z6', BASELINE, 6),
            ('shelves-candidate-z6', CANDIDATE, 6),
            ('shelves-reference-z7', CANDIDATE, 7),
        ]:
            with Host(output / label, pack, level=level) as host:
                for name, position in comparison:
                    host.still(name, position)
    if suite in ('all', 'coverage'):
        with Host(output / 'coverage-z6', CANDIDATE, level=6) as host:
            for item in plan['random']:
                for scale in ('regional', 'close'):
                    host.still(f"{item['id']}-{scale}",
                               (item['lon'], item['lat'], item[f'{scale}_mpp']))
            for row in plan['special']:
                if row['id'] not in triptych_ids:
                    host.still(row['id'], (row['lon'], row['lat'], row['mpp']))


def replay_recorded(host, parent, relative, *, name=None, prewarm=True):
    source = parent / relative
    request = z7.data(source)['request']
    host.replay(name or source.stem, request['lon'], request['lat'],
                request['scales'], request.get('moves'), prewarm=prewarm)


def run_motion(output, suite):
    if suite in ('all', 'shelves'):
        for label, pack in [('shelves-old-z6', BASELINE), ('shelves-candidate-z6', CANDIDATE)]:
            with Host(output / label, pack, replay=True) as host:
                replay_recorded(host, Z7_DETAIL, 'after-jump-v2/ross-full-lod.json')
            with Host(output / (label + '-ronne'), pack, replay=True) as host:
                # Use the same wheel step as the game, with a deliberate hold at each target.
                mpp = 120
                stages = [mpp * 1.22 ** step for step in range(9)]
                scales = [stages[0]] * 14
                for value in stages[1:]:
                    scales.extend([value] * 9)
                scales.extend([stages[-1]] * 25)
                for value in reversed(stages[:-1]):
                    scales.extend([value] * 9)
                scales.extend([stages[0]] * 14)
                host.replay('ronne-shelf-wheel', -51.8965, -81.6525, scales)
    if suite in ('all', 'fixed'):
        with Host(output / 'fixed-z6', CANDIDATE, level=6, replay=True) as host:
            for name in ('alps-z6', 'coast-z6', 'date-z6'):
                replay_recorded(host, Z6_SEAMS, f'z6-exact-motion/{name}.json')
            host.focus(11.25, 45.0, 105)
            if host.talk('status')['state']['pitch_degrees'] == 0:
                host.talk('key', value='v')
            replay_recorded(host, Z6_SEAMS, 'z6-exact-motion/alps-oblique.json')
    if suite in ('all', 'lod'):
        with Host(output / 'auto-warm', CANDIDATE, replay=True) as host:
            for name in ('slow-warm-z6', 'rapid-z6', 'motion-z6'):
                replay_recorded(host, Z6_SEAMS, f'z6-auto-extended/{name}.json')
            replay_recorded(host, Z6_SEAMS, 'z6-z7-final/date-z6.json')
            for name in ('alps-corner', 'coast-corner'):
                replay_recorded(host, Z7_DETAIL, f'after-jump-v2/{name}.json',
                                name=f'fast-jump-{name}')
            for name in ('threshold', 'wheel-reversal'):
                replay_recorded(host, Z7_DETAIL, f'after-jump-v2/{name}.json')
        with Host(output / 'auto-cold', CANDIDATE, replay=True) as host:
            replay_recorded(host, Z7_DETAIL, 'candidate-cold-v2/alps-cold.json', prewarm=False)
        with Host(output / 'auto-over-budget', CANDIDATE, replay=True) as host:
            replay_recorded(host, Z7_DETAIL, 'after-jump-v2/overflow.json', prewarm=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('stills', 'motion'))
    parser.add_argument('--suite', default='all',
                        choices=('all', 'shelves', 'coverage', 'fixed', 'lod'))
    parser.add_argument('--run-label', help='Use a new label to retain earlier captures on rerun.')
    args = parser.parse_args()
    if args.mode == 'stills' and args.suite in ('fixed', 'lod'):
        parser.error(f'{args.suite} is a motion suite')
    if args.mode == 'motion' and args.suite == 'coverage':
        parser.error('coverage is a stills suite')
    if args.run_label and (Path(args.run_label).name != args.run_label
                           or args.run_label in ('.', '..')):
        parser.error('run label must be one directory name')
    required = [OBSERVE if args.mode == 'motion' else NATIVE, CANDIDATE / 'index.json']
    if args.suite in ('shelves', 'all'):
        required.append(BASELINE / 'index.json')
    for path in required:
        if not path.is_file():
            parser.error(f'required file missing: {path}')
    output = STAGE / ('capture-' + args.mode + '-' + (args.run_label or args.suite))
    if output.exists():
        parser.error(f'capture directory exists: {output}; choose a new --run-label')
    if args.mode == 'stills':
        run_stills(output, args.suite)
    else:
        run_motion(output, args.suite)


if __name__ == '__main__':
    main()
