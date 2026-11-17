from pathlib import Path
import json
import statistics
root = Path(__file__).parent
for directory in ('motion-after','motion-cold','motion-after-fixed','motion-before','motion-before-fixed'):
    for filename in sorted((root/directory).glob('*.json')):
        data=json.loads(filename.read_bytes())
        if 'frames' not in data:continue
        rows=data['frames']
        times=sorted(b['ms']-a['ms'] for a,b in zip(rows,rows[1:]))
        samples=[[s['terrain'] for s in f['samples']['samples'] if s.get('terrain')] for f in rows]
        weights=[[sum(w for (z,x,y),w in s['contributors'] if z==7) for s in points] for points in samples]
        print(directory, filename.stem, len(rows), "mpp", rows[0]['mpp'], rows[-1]['mpp'],"ztarget",sorted(set(f['terrain']['draw_max_level'] for f in rows)),
              "need",max(f['terrain']['z7_view_pages'] for f in rows), "all required",max(f['terrain']['required_detail_pages'] for f in rows), 
              "resident",max(f['terrain']['resident_detail_pages'] for f in rows),"lack",sum(s['missing_exact_page'] for ss in samples for s in ss),
              "spread",max((max(ws)-min(ws) for ws in weights if ws),default=0),"p50/p95",round(statistics.median(times),2),round(times[(len(times)*95-1)//100],2))

