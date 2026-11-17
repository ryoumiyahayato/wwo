import os
from pathlib import Path
import subprocess
import sys
import time
import uuid


STAGE = Path(__file__).resolve().parent
MIGRATION = STAGE.parent
Z7 = MIGRATION / 'terrain-z7-detail-20261116'
sys.path[:0] = [str(Z7), str(MIGRATION / 'terrain-runtime-20261116')]
from capture_local import DATA, Host, save
from observe_runtime import gpu_sample


POINT = (11.25, 46.40625, 1420)
WHEEL = [1., .5, -.5, -1., -2.2, .7, -.7, 2.2] * 3
MODES = ('geographic', 'political', 'economic', 'military')


class FormalHost(Host):
    def __init__(self, name, pack):
        self.directory = STAGE / name
        self.directory.mkdir()
        self.request = self.directory / 'map.json'
        self.response = self.directory / 'map.response.json'
        self.profile = 'Z6Detail-' + uuid.uuid4().hex[:12]
        self.log = (self.directory / 'stderr.txt').open('wb')
        command = [str(Z7 / 'z7-final-native.exe'), '--play', '--background',
                   '--preferences', str(self.directory / 'preferences.json'),
                   '--data', str(DATA.parent / 'natural-terrain-preview' / 'data'),
                   '--terrain-candidate', str(pack), '--observe', str(self.request)]
        try:
            self.process = subprocess.Popen(command, env={**os.environ, 'WWO_RUST_PROFILE': self.profile},
                                            stdout=self.log, stderr=self.log, creationflags=subprocess.CREATE_NO_WINDOW)
        except OSError:
            self.log.close()
            raise

    def wait_for(self, predicate, timeout=55):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            try:
                last = self.talk('status', timeout=5)['state']
            except TimeoutError:
                continue
            if predicate(last):
                return last
        raise TimeoutError((self.directory, last))


def sequence(host):
    home = host.wait_for(lambda s: s['lobby'] and s['lobby']['ready'])
    assert home['window']['background'], home['window']
    host.talk('key', value='Enter')
    host.wait_for(lambda s: s['lobby'] and s['lobby']['selection_ready'])
    host.talk('key', value='Enter')
    start = host.wait_for(lambda s: s['session'] and s['session']['player'] and s['terrain'])
    assert start['session']['paused'] and start['window']['background'], start
    w, h = start['viewport']
    drag = dict(x=w*.56, y=h*.52, to_x=w*.49, to_y=h*.53, frames=35)
    modes = {}
    record = dict(profile=host.profile, home=home, start=start, modes=modes,
                  input=dict(position=POINT, wheel_steps=WHEEL, wheel_position=[w/2, h/2], drag=drag))
    for mode in MODES:
        if mode == 'military':
            host.talk('click', x=w/2, y=h-50)
            host.talk('click', x=w/2, y=h-min(78,max(52,.056*w))-87.5)
        else:
            host.talk('key', value=mode[0])
        host.wait_for(lambda s: s['mode'] == mode, timeout=10)

        host.talk('timing')
        before_focus = time.monotonic()
        settled = host.focus(*POINT)
        focus_seconds = time.monotonic() - before_focus
        motion = []
        for steps in WHEEL:
            state = host.talk('wheel', x=w/2, y=h/2, steps=steps)['state']
            motion.append({k: state[k] for k in ('mode', 'mpp', 'terrain', 'window')})
        host.talk('drag', **drag)
        time.sleep(.8)
        before_ready = time.monotonic()
        ready = host.ready()
        settle_seconds = time.monotonic() - before_ready
        timing = host.talk('timing')['extra']
        try:
            memory = gpu_sample(host)
            memory['gpu_status'] = 'MEASURED' if memory['gpu'] else 'NOT_RUN'
        except (OSError, ValueError, subprocess.SubprocessError) as exc:
            memory = dict(gpu_status='NOT_RUN', error=str(exc))
        host.focus(*POINT)
        host.snapshot(mode)
        modes[mode] = dict(timing=timing, memory=memory, motion=motion, start=settled, final=ready,
                           focus_seconds=focus_seconds, settle_seconds=settle_seconds)
        save(host.directory / 'formal.json', record)
        print(host.directory.name, mode, len(timing['interval_ms']), flush=True)


if __name__ == '__main__':
    run = uuid.uuid4().hex[:8]
    packs = [('before', STAGE / 'baseline-with-z7'),
             ('after', STAGE / os.environ.get('WWO_Z6_WORKING', 'candidate-final'))]
    for _, pack in packs:
        for resource in ('index.json', '6.qpk', '7.qpk'):
            if not (pack / resource).is_file():
                raise FileNotFoundError(pack / resource)
    for label, pack in packs:
        with FormalHost(f'formal-{label}-{run}', pack) as host:
            sequence(host)
