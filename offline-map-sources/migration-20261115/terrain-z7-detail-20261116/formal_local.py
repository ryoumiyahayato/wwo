from capture_local import *
sys.path.insert(0, str(MIGRATION/'terrain-runtime-20261116'))
from observe_runtime import gpu_sample

def sequence(host, capture):
    for _ in range(120):
        try:
            home = host.talk('status',timeout=5)['state']
        except TimeoutError:
            continue
        if home['lobby'] and home['lobby']['ready']:
            break
    assert home['lobby']['ready'], home
    host.talk('key', value='Enter')
    for _ in range(120):
        home = host.talk('status')['state']
        if home['lobby'] and home['lobby']['selection_ready']:
            break
    host.talk('key', value='Enter')
    for _ in range(240):
        start = host.talk('status')['state']
        if start['session'] and start['session']['player'] and start['terrain']:
            break
    assert start['session']['paused'] and start['window']['background'], start
    w,h = start['viewport']
    modes = {}
    for mode in ('geographic','political','economic','military'):
        if mode=='military':
            host.talk('click', x=w/2, y=h-50)
            host.talk('click', x=w/2, y=h-min(78,max(52,.056*w))-87.5)
        else:
            host.talk('key',value=mode[0])
        assert host.talk('status')['state']['mode']==mode
        host.focus(11.25,46.40625,530)
        host.talk('timing')
        motion = []
        for step in [1.,1.,-1.,-1.,-3.04,-1.,1.,3.04]*3:
            frame=host.talk('wheel',x=w/2,y=h/2,steps=step)['state']
            motion.append({k:frame[k] for k in ('mode','mpp','terrain','window')})
        host.talk('drag', x=w*.56, y=h*.52, to_x=w*.49, to_y=h*.53, frames=35)
        time.sleep(.8)
        began=time.monotonic()
        ready=host.ready()
        waited=time.monotonic()-began
        timing=host.talk('timing')['extra']
        memory=gpu_sample(host)
        modes[mode]=dict(timing=timing,memory=memory, motion=motion, final=ready, wait_seconds=waited)
        if capture:
            if mode=='geographic':
                host.focus(-166.2583,-84.4318,170)
            else:
                host.focus(11.25,46.40625,530)
            host.snapshot(mode)
        save(host.directory/'formal.json',dict(start=start,modes=modes))
        print(mode,len(timing['interval_ms']),flush=True)

if __name__ == '__main__':
    with Host('formal-before-ok',BASE,native=True) as before:
        sequence(before,False)
    with Host('formal-after-ok',CANDIDATE,native=True) as after:
        sequence(after,True)
