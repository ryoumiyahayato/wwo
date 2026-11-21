"""Replay frozen global map views through the normal game observer."""
import argparse
import math
from pathlib import Path
from statistics import median
from tempfile import TemporaryDirectory
import time
import uuid

from capture_z7_pages import Observer, png_size, read, write


def run(args, scratch):
    snapshots = []
    timings = {}
    args.profile = 'WWO-GlobalMap-' + uuid.uuid4().hex[:12]
    args.terrain_candidate = None

    with Observer(args, scratch, play=True, log_path=args.output / 'game.log') as host:
        def status():
            return host.ask('status')['state']

        def capture(label, *, settled=None):
            frame = host.ask('capture', label=label, value='terrain-samples')
            png = scratch / f'{label}.png'
            state = frame['state']
            if png_size(png) != tuple(state['viewport']):
                raise OSError(f'No completed frame for {label}')
            png.replace(args.output / png.name)
            snapshots.append(dict(label=label, settled=settled, frame=frame))
            write(args.output / 'frames.json', snapshots)
            terrain = state['terrain']
            print(label, round(state['mpp'],2), state['center'],
                  (terrain['target_level'], terrain['view_max_level'], terrain['draw_max_level']),
                  terrain.get('water_geometry_view_missing_outside_budget'), flush=True)
            return frame

        def settle(seconds=6):
            deadline = time.monotonic()+seconds
            while True:
                state = status()
                terrain = state['terrain']
                foreground = state['mpp'] < 4200
                if terrain['selected_ready'] and (not foreground or (
                        terrain.get('water_geometry_view_resident') == terrain.get('water_geometry_view_wanted')
                        and not terrain.get('water_geometry_handoff_active',False))):
                    return True
                if time.monotonic() >= deadline:
                    return False

        def focus(point):
            lon,lat,mpp = point
            camera = dict(lon=lon,lat=lat,mpp=mpp,value='north')
            focused = host.ask('focus',**camera)['state']
            if abs(focused['pitch_degrees']) > 1e-6:
                host.ask('key',value='v')
                host.ask('focus',**camera)
            return status()

        def stable(label, point):
            focus(point)
            return capture(label, settled=settle())

        def wheel(count):
            x,y = (value/2 for value in extent)
            for _ in range(abs(count)):
                host.ask('wheel',x=x,y=y,steps=-1 if count>0 else 1)

        def pan(reverse=False, frames=18, offsets=(-430,430)):
            x,y = (value/2 for value in extent)
            positions = (x+offsets[0],x+offsets[1])
            start,end = reversed(positions) if reverse else positions
            host.ask('drag',x=start,y=y,to_x=end,to_y=y,frames=frames)

        def timed(label, route):
            host.ask('timing', value='profile' if args.profile_frames else '')
            route()
            frame = host.ask('timing')
            timing = frame['extra']
            numbers = sorted(timing['interval_ms'])
            timings[label] = dict(
                frame_count=len(numbers),
                p50_ms=median(numbers) if numbers else None,
                p95_ms=numbers[min(len(numbers)-1,int(.95*len(numbers)))] if numbers else None,
                max_ms=max(numbers,default=None),
                intervals=timing,
            )
            write(args.output/'timings.json',timings)
            print(label,{key:value for key,value in timings[label].items() if key!='intervals'},flush=True)

        opened = time.monotonic()
        host.ask('status',timeout=65,refresh=True)
        capture('cold-lobby')
        host.ask('key',value='Enter')
        opening_deadline = time.monotonic()+10
        while not status()['lobby']['selection_ready']:
            if time.monotonic() >= opening_deadline:
                raise RuntimeError('The opening country list did not load')
        host.ask('key',value='Enter')
        if status()['lobby']['page'] == 'Prologue':
            for _ in range(6):
                host.ask('key',value='Enter')
        deadline = time.monotonic()+22
        while not (state:=status())['session']:
            if time.monotonic() >= deadline:
                raise RuntimeError('Could not enter the normal game world')
        host.ask('key',value='g')
        extent = state['viewport']
        cold = capture('cold-geography')
        first_geography_seconds = time.monotonic()-opened
        cold_settled = capture('cold-geography-settled', settled=settle())
        write(args.output/'cold-start.json',dict(
            first_engine_frame_ms=cold['state']['first_frame_ms'],
            until_first_geography_capture_seconds=first_geography_seconds,
            engine_gpu=cold_settled['state']['gpu'], viewport=extent,
            capture_process='fresh game process and independent profile, OS cache untouched',
        ))

        if args.section == 'troyes':
            x, y = (value/2 for value in extent)
            radius = min(78, max(52, .056 * extent[0]))
            host.ask('click', x=x, y=extent[1]-10)
            host.ask('click', x=x, y=extent[1]-radius-202+114)
            stable('troyes-military-grid', args.routes['troyes'])
            host.ask('click', x=x, y=y)
            selected = status()['military_grid']['selected']
            if selected != args.routes['troyes_cell']:
                raise RuntimeError(f'Unexpected Troyes military grid selection: {selected}')

            def open_battle():
                host.ask('key', value='Enter')
                time.sleep(1.0)
            timed('troyes-enter', open_battle)
            battle = status()['land_battle']
            if not battle or battle['cell'] != selected:
                raise RuntimeError('Could not enter the Troyes exercise')
            host.ask('key', value='3')
            timed('troyes-vehicle-paused', lambda: time.sleep(1.1))

            def view_roundtrip(shoot=False):
                for key in ('1','2','3','Tab'):
                    host.ask('key', value=key)
                    time.sleep(.25)
                if shoot:
                    host.ask('key', value='Space')
                    host.ask('key', value='p')
                    time.sleep(.55)
                    host.ask('key', value='p')
            timed('troyes-scale-and-fire', lambda: view_roundtrip(shoot=True))
            timed('troyes-scale-repeat', view_roundtrip)
            after = status()['land_battle']
            host.ask('key', value='Escape')
            timed('troyes-reenter', open_battle)
            resumed = status()['land_battle']
            if not resumed or resumed['id'] != after['id']:
                raise RuntimeError('Could not resume the same Troyes exercise')
            write(args.output/'troyes.json', dict(before=battle, after=after, resumed=resumed))
            return

        if args.section == 'material':
            x,y = (value/2 for value in extent)
            for label,lon,lat,zoom_scale,near in args.routes['material']:
                def zoom_to(mpp):
                    current = status()['mpp']
                    host.ask('wheel',x=x,y=y,steps=math.log(current/mpp,1.22))

                levels = [('z5',5.), ('z5-z6',5.565), ('z6',6.),
                          ('z6-z7',6.565), ('z7',7.12)]
                stages = [(name,zoom_scale/2**lod) for name,lod in levels] + [('near',near)]
                if args.material_transitions_only:
                    stable(f'{label}-z7',(lon,lat,stages[-2][1]))
                    for name,mpp in reversed(stages[:-2]):
                        zoom_to(mpp)
                        capture(f'{label}-{name}',settled=settle())
                    continue

                stable(f'{label}-z5',(lon,lat,stages[0][1]))
                for name,mpp in stages[1:]:
                    zoom_to(mpp)
                    capture(f'{label}-in-{name}',settled=settle())

                def roundtrip():
                    pan(frames=20,offsets=(-180,180))
                    time.sleep(.55)
                    pan(True,frames=20,offsets=(-180,180))
                    time.sleep(.55)

                timed(f'{label}-near-pan',roundtrip)
                capture(f'{label}-pan-return',settled=settle())

                def retreat():
                    for _,mpp in reversed(stages[:-1]):
                        zoom_to(mpp)
                        time.sleep(.38)

                timed(f'{label}-zoom-return',retreat)
                capture(f'{label}-zoom-return',settled=settle())

                # With the finer level already selected, the outward wheel route
                # visits both partially blended states inside the LOD hysteresis.
                stable(f'{label}-z7',(lon,lat,stages[-2][1]))
                for name,mpp in reversed(stages[:-2]):
                    if name == 'z5':
                        break
                    zoom_to(mpp)
                    capture(f'{label}-{name}',settled=settle())

                if label in ('troyes','nearshore'):
                    focus((lon,lat,stages[0][1]))
                    settle()
                    # Record actual game frames on a second, densely stepped route.
                    for index in range(49):
                        progress = 1.-abs(index/24.-1.)
                        zoom_to(stages[0][1]*(near/stages[0][1])**progress)
                        capture(f'{label}-motion-{index:02}')
            return

        if args.section in ('all', 'edges'):
            edge = (179.88,-16.77,135)
            stable('dateline-before',edge)
            pan(True)
            time.sleep(.35)
            capture('dateline-across')
            pan()
            time.sleep(.35)
            capture('dateline-return', settled=settle())
            for label,lon,lat,mpp in (('normal-max-overview',89.2,21.85,29039.88),
                                     ('z0-observer-overview',89.2,21.85,88000)):
                stable(label,(lon,lat,mpp))
            if args.section == 'edges':
                return

        if args.section in ('all','views'):
            for item in args.routes['random_draws']:
                label = item['continent'].lower().replace(' ','-')
                for suffix,mpp in [('region',item['regional_mpp']),('near',item['near_mpp'])]:
                    stable(label+'-'+suffix,(item['lon'],item['lat'],mpp))
            for label,lon,lat,mpp in args.routes['fixed']:
                stable(label,(lon,lat,mpp))
            for label,lon,lat,mpp in args.routes['fixed']:
                if label in ('dateline-west','south-pole','z6-capacity','seine'):
                    if label == 'south-pole':
                        # Start on the landward side to cross the polar grid without a pole clamp.
                        lat = -89.4
                    focus((lon,lat,mpp))
                    settle()
                    pan()
                    capture(label+'-pan-mid')
                    time.sleep(.55)
                    capture(label+'-pan-end')
                    pan(True)
                    time.sleep(.55)
                    capture(label+'-pan-return', settled=settle())
            if args.section == 'views':
                return

        if args.section in ('all','nile'):
            nile = args.routes['nile']
            stable('nile-start',nile)
            drag_offsets = (0,-110) if args.nile_drag_frames == 24 else (-430,430)

            def nile_motion():
                wheel(22)
                time.sleep(.30)
                pan(frames=args.nile_drag_frames,offsets=drag_offsets)
                time.sleep(.55)
                pan(True,frames=args.nile_drag_frames,offsets=drag_offsets)
                time.sleep(.55)
                wheel(-22)
                time.sleep(.45)

            timed('nile-idle',lambda: time.sleep(1.1))
            for repeat in range(1,4):
                focus(nile)
                settle()
                timed(f'nile-roundtrip-{repeat}',nile_motion)
                capture(f'nile-roundtrip-{repeat}-return', settled=settle())
            stable('nile-400',(nile[0],nile[1],400))
            stable('nile-930',(nile[0],nile[1],930))
            stable('nile-1780',(nile[0],nile[1],1780))
            if args.section == 'nile':
                return

        lon,lat,start_mpp = args.routes['zoom']
        stable('zoom-out-z7',(lon,lat,start_mpp))
        previous_level = 7
        steps = 0
        previous_mpp = start_mpp
        for step in range(40):
            wheel(1)
            state = status()
            if abs(state['mpp']-previous_mpp)<1e-6:
                break
            previous_mpp = state['mpp']
            steps += 1
            level = state['terrain']['target_level']
            if level != previous_level:
                capture(f'zoom-out-z{level}')
                previous_level = level
            if level == 0:
                break
        capture('zoom-out-stable', settled=settle())
        # Correct for the final outward tick if it hit the normal maximum partway.
        target_steps = math.log(previous_mpp/start_mpp,1.22)
        x,y = (value/2 for value in extent)
        if target_steps%1>1e-6 and target_steps%1<1-1e-6:
            host.ask('wheel',x=x,y=y,steps=target_steps%1)
            steps = int(target_steps)
        for step in range(steps):
            wheel(-1)
            state = status()
            level = state['terrain']['target_level']
            if level != previous_level:
                capture(f'zoom-in-z{level}')
                previous_level = level
        capture('zoom-return', settled=settle())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('exe','data','frozen','output'):
        parser.add_argument(key, type=lambda value: Path(value).resolve())
    parser.add_argument('--section', choices=('all','views','nile','zoom','edges','troyes','material'), default='all')
    parser.add_argument('--nile-drag-frames', type=int, choices=(18,24), default=24)
    parser.add_argument('--profile-frames', action='store_true')
    parser.add_argument('--material-transitions-only', action='store_true')
    args = parser.parse_args()
    args.routes = read(args.frozen)
    args.output.mkdir(parents=True)
    with TemporaryDirectory(dir=args.output,prefix='capture-') as directory:
        run(args,Path(directory))


if __name__ == '__main__':
    main()
