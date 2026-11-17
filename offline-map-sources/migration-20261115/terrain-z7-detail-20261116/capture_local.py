from pathlib import Path
import json, os, subprocess, sys, time, uuid

STAGE = Path(__file__).resolve().parent
MIGRATION = STAGE.parent
DATA = MIGRATION.parents[1]/'wwo/local-artifacts/strategic-map-phase4/data'
BASE = MIGRATION/'terrain-quality-20261115/recovered-candidate/worldcrs84quad-15s-v2'
CANDIDATE = STAGE/'candidate-final'
NATIVE = MIGRATION/'terrain-z0-skeleton-20261116/z0-final-native.exe'
OBS = STAGE/'z7-observe.exe'

def data(path):
    return json.loads(path.read_text(encoding='utf-8'))

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

class Host:
    def __init__(self, name, pack, *, fixed=False, native=False, replay=False):
        self.directory = STAGE/name
        self.directory.mkdir()
        self.request = self.directory/'map.json'
        self.response = self.directory/'map.response.json'
        self.log = (self.directory/'stderr.txt').open('wb')
        flags = ['--play','--background','--preferences',str(self.directory/'preferences.json')] if native else ['--terrain-review']
        if fixed:
            flags.extend(['--terrain-level','7'])
        exe = OBS if replay else (STAGE/'z7-final-native.exe' if pack == CANDIDATE else NATIVE)
        env = dict(os.environ, WWO_RUST_PROFILE='Z7Detail-'+uuid.uuid4().hex[:12])
        self.process = subprocess.Popen([str(exe), *flags, '--data', str(DATA.parent/'natural-terrain-preview/data' if native else DATA), '--terrain-candidate', str(pack), '--observe', str(self.request)], env=env, stdout=self.log, stderr=self.log, creationflags=subprocess.CREATE_NO_WINDOW)

    def talk(self, action, timeout=35, **fields):
        id = uuid.uuid4().hex
        tmp = self.request.with_suffix('.tmp')
        save(tmp, dict(id=id, action=action, **fields))
        tmp.replace(self.request)
        deadline = time.monotonic()+timeout
        while time.monotonic()<deadline:
            if self.process.poll() is not None:
                raise RuntimeError((self.process.returncode, self.directory/'stderr.txt'))
            try:
                response = data(self.response)
                if response['id']==id:
                    assert not response['state']['window']['focused'], response['state']['window']
                    return response
            except (OSError, ValueError):
                pass
            time.sleep(.025)
        raise TimeoutError((action, fields, self.directory))

    def ready(self, position=None, require_pages=True):
        for _ in range(180):
            response = self.talk('status')
            state = response['state']
            terrain = state['terrain']
            if not terrain or (require_pages and not terrain['selected_ready']):
                continue
            if position is not None:
                lon, lat, mpp = position
                if abs(((state['center'][0]-lon+180)%360)-180)>1e-6 or abs(state['center'][1]-lat)>1e-6 or abs(state['mpp']-mpp)>1e-6:
                    continue
            return state
        raise TimeoutError((position, state))

    def focus(self, lon, lat, mpp, require_pages=True):
        self.talk('focus', lon=lon, lat=lat, mpp=mpp, value='north')
        return self.ready((lon,lat,mpp), require_pages=require_pages)

    def still(self, name, position):
        self.focus(*position)
        return self.snapshot(name)

    def snapshot(self, name):
        reply = self.talk('capture', label=name)
        for _ in range(350):
            row = self.directory/(name+'.png')
            if row.is_file() and row.stat().st_size>0:
                break
            time.sleep(.04)
        save(self.directory/(name+'.json'), reply)
        print(name, reply['state']['center'], reply['state']['mpp'], flush=True)
        return reply

    def replay(self, name, lon, lat, scales, moves=None, prewarm=True):
        begin = self.focus(lon,lat,scales[0], require_pages=prewarm)
        request = dict(label=name, scales=scales, moves=moves or [], lon=lon, lat=lat)
        response = self.talk('zoom-replay', timeout=180, **request)
        assert 'frames' in response['extra'], response
        save(self.directory/(name+'.json'), dict(start=begin,request=request,end=response['state'],**response['extra']))
        print(name, len(response['extra']['frames']), flush=True)

    def __enter__(self):
        return self

    def __exit__(self, *ignored):
        if self.process.poll() is None:
            try:
                self.talk('quit', timeout=5)
            except (RuntimeError, TimeoutError):
                pass
            try:
                self.process.wait(5)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                self.process.wait(5)
        self.log.close()

SHELVES = {
    'ross-shelf': (-166.2583,-84.4318,340),
    'ronne-shelf': (-51.8965,-81.6525,370),
    'ross-front': (177,-78.55,430),
    'westerly-shelf': (-66,-72.05,405),
    'amery-shelf': (71.7,-69.65,415),
}
SPECIAL = {
    'alps-corner': (11.25,46.40625,360),
    'wadden-edge': (7.03125,53.58,320),
    'prairie': (-93.51,42.47,430),
    'tibet': (89,33,430),
    'greenland': (-47.866,68.165,345),
    'sahara': (-.703125,33.046875,425),
    'bosten': (88.4,41.94,200),
    'obidos': (-55.52,-1.92,300),
    'mekong': (106.15,9.88,395),
    'new-zealand': (174.4,-41.2,385),
    'mascarene': (61.8,-17.9,430),
    'guinea': (-7.66,-.20,430),
    'dateline': (179.9999,66.09375,355),
    'north-pole': (17,89.89,146),
    'south-pole': (-52,-89.89,146),
}

def capture_fixed():
    plan = data(STAGE/'z7-sample-plan.json')['random']
    with Host('baseline-stills',BASE,fixed=True) as host:
        for name, position in (SHELVES | {'tibet':SPECIAL['tibet']}).items():
            host.still(name,position)
    with Host('candidate-stills',CANDIDATE,fixed=True) as host:
        for i, site in enumerate(plan):
            for view in ('regional','close'):
                host.still(f'continent-{i+1}-{view}',(site['lon'],site['lat'],site[view+'_mpp']))
        for name, position in (SHELVES | SPECIAL).items():
            host.still(name,position)

def capture_final():
    plan = data(STAGE/'z7-sample-plan.json')['random'][-1]
    with Host('final-stills',CANDIDATE,fixed=True) as host:
        for name, position in (SHELVES | {'south-pole': SPECIAL['south-pole']}).items():
            host.still(name, position)
        for view in ('regional','close'):
            host.still(f'continent-7-{view}', (plan['lon'],plan['lat'],plan[view+'_mpp']))
    with Host('fixed-overflow',CANDIDATE,fixed=True,replay=True) as host:
        host.replay('pole',17,89.89,[146]*15+[146*1.22]*4+[146*1.22**2]*4+[146*1.22**3]*12+[146*1.22**2]*4+[146]*20,prewarm=False)

def sequence(rel):
    return data(MIGRATION/rel)['request']

def dynamic(mode):
    overlap = 'terrain-z7-seams-20261116/guard-auto'
    jumps = 'terrain-z6-seams-20261116/z7-jump-auto'
    basepack = BASE if mode=='before' else CANDIDATE
    with Host(f'{mode}-jump-v2' if mode=='after' else f'{mode}-jump',basepack,replay=True) as host:
        for name in ('alps-corner','coast-corner'):
            request=sequence(f'{jumps}/{name}.json')
            host.replay(name,request['lon'],request['lat'],request['scales'],request['moves'])
        if mode=='before':
            return
        request=sequence(f'{overlap}/slow-warm.json')
        host.replay('slow-warm',request['lon'],request['lat'],request['scales'],request['moves'])
        request=sequence(f'{overlap}/zoom-pan-rotate.json')
        host.replay('pan-rotate',request['lon'],request['lat'],request['scales'],request['moves'])
        host.replay('wheel-reversal',11.25,46.40625,[530]*8+[530*1.22]*4+[530*1.22**2]*4+[530*1.22**3]*8+[530*1.22**2]*4+[530*1.22]*4+[530]*18+[530*1.22]*4+[530*1.22**2]*4+[530*1.22]*4+[530]*25)
        host.replay('threshold',11.25,46.40625,[530]*10+([660]*3+[730]*3+[790]*3+[730]*3)*4+[530]*15)
        host.replay('overflow',17,89.89,[146]*15+[178]*3+[218]*3+[266]*18+[218]*3+[178]*3+[146]*16)
        up=[155 * 1.22**(i/6) for i in range(1,57)]
        host.replay('ross-full-lod',177,-78.55,[155]*14+up+[up[-1]]*21+up[::-1]+[155]*18)
        host.replay('antarctic-interface',177,-78.55,[155]*16+[155*1.22]*5+[155*1.22**2]*5+[155*1.22**3]*5+[155*1.22**4]*20+[155*1.22**3]*5+[155*1.22**2]*5+[155*1.22]*5+[155]*24)
    with Host('candidate-cold-v2',CANDIDATE,replay=True) as host:
        host.replay('alps-cold',11.25,46.40625,[1150]*9+[800]*4+[660]*4+[530]*90,prewarm=False)
    with Host('candidate-fixed-motion-v2',CANDIDATE,fixed=True,replay=True) as host:
        cases={'alps-corner':(11.25,46.40625,380),'dateline':(179.9999,66.09375,310),'ross-front':(177,-78.55,350)}
        for name,(lon,lat,mpp) in cases.items():
            host.replay(name,lon,lat,[mpp*(1+i*.009) for i in range(15)]+[mpp*(1+i*.009) for i in reversed(range(15))],[[4,0,.5]]*12+[[-3,1,-.4]]*18)
        host.focus(11.25,46.40625,105)
        if host.talk('status')['state']['pitch_degrees'] == 0:
            host.talk('key',value='v')
        host.replay('oblique',11.25,46.40625,[105+i for i in range(20)]+[104+i for i in reversed(range(20))],[[5,3,.5]]*20+[[-3,-1,-.4]]*20)

if __name__ == '__main__':
    if sys.argv[1]=='fixed':
        capture_fixed()
    elif sys.argv[1]=='final':
        capture_final()
    elif sys.argv[1] in ('before','after'):
        dynamic(sys.argv[1])
