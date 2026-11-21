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
            host.ask('timing')
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
    parser.add_argument('--section', choices=('all','views','nile','zoom','edges'), default='all')
    parser.add_argument('--nile-drag-frames', type=int, choices=(18,24), default=24)
    args = parser.parse_args()
    args.routes = read(args.frozen)
    args.output.mkdir(parents=True)
    with TemporaryDirectory(dir=args.output,prefix='capture-') as directory:
        run(args,Path(directory))


if __name__ == '__main__':
    main()
