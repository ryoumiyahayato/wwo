"""Bounded A0 lossless sample producer. Never writes formal assets or exports.
Uses the already-installed Git ZSTD library; no installation or acquisition.
Every candidate restores and compares the full original decoded byte stream.
"""
import ctypes as C
import io
import json
from pathlib import Path
import struct
import sys
import time
import zlib

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'local-artifacts/terrain-a0-20261027'
HEADER = struct.Struct('<8sBBHIIII')
MAGIC = b'FRA0\0\0\0\0'
Z = C.CDLL('D:/Git/mingw64/bin/libzstd.dll')
for name, args, result in [
    ('ZSTD_compressBound', [C.c_size_t], C.c_size_t),
    ('ZSTD_compress', [C.c_void_p, C.c_size_t, C.c_void_p, C.c_size_t, C.c_int], C.c_size_t),
    ('ZSTD_decompress', [C.c_void_p, C.c_size_t, C.c_void_p, C.c_size_t], C.c_size_t),
    ('ZSTD_isError', [C.c_size_t], C.c_uint),
    ('ZSTD_getErrorName', [C.c_size_t], C.c_char_p),
]:
    f = getattr(Z, name); f.argtypes = args; f.restype = result


def zstd(data, level):
    target = bytearray(Z.ZSTD_compressBound(len(data)))
    view = (C.c_char * len(target)).from_buffer(target)
    size = Z.ZSTD_compress(view, len(target), C.c_char_p(data), len(data), level)
    if Z.ZSTD_isError(size): raise ValueError(Z.ZSTD_getErrorName(size))
    return bytes(target[:size])


def unzstd(data, size):
    target = bytearray(size); view = (C.c_char * size).from_buffer(target)
    n = Z.ZSTD_decompress(view, size, C.c_char_p(data), len(data))
    if Z.ZSTD_isError(n) or n != size: raise ValueError('ZSTD size/decode mismatch')
    return target


def levels(w, h, bpp, mips):
    offset = 0
    while True:
        n = w * h * bpp
        yield offset, w, h, n
        offset += n
        if not mips or (w == h == 1): break
        w = max(1, w // 2); h = max(1, h // 2)


def original(a):
    data = (ROOT / a['path'].removeprefix('res://')).read_bytes()
    if a['format'] == 'RGBA8_MIP_DEFLATE':
        if data[:8] != b'FRT42\0\0\0': raise ValueError('Unexpected legacy header')
        w, h, length = struct.unpack('<III', data[8:20])
        raw = zlib.decompress(data[20:]); bpp = 4; mips = True
        if (w, h, length) != (a['width'], a['height'], a['decoded_bytes']): raise ValueError('Metadata mismatch')
    else:
        bpp = 2 if a['format'] == 'RG8' else 1; mips = False
        p = np.asarray(Image.open(io.BytesIO(data)).convert('RGB'), dtype=np.uint8)
        h, w = p.shape[:2]; raw = p[:, :, :bpp].tobytes()
    if len(raw) != a['decoded_bytes']: raise ValueError('Decoded length mismatch')
    if sum(v[3] for v in levels(w, h, bpp, mips)) != len(raw): raise ValueError('Mip layout mismatch')
    return data, raw, w, h, bpp, mips


def png_bytes(p):
    stream = io.BytesIO(); Image.fromarray(p).save(stream, format='PNG', compress_level=6)
    return stream.getvalue()


def rgba_for_png(p):
    if p.shape[-1] == 4:
        return p[:, :, :3] if np.all(p[:, :, 3] == 255) else p
    result = np.zeros((*p.shape[:2], 3), dtype=np.uint8)
    result[:, :, :p.shape[-1]] = p
    return result


def restored_png(data, bpp):
    p = np.asarray(Image.open(io.BytesIO(data)).convert('RGBA'), dtype=np.uint8)
    return p[:, :, :bpp].tobytes()


def category(a):
    if a['format'] != 'RGBA8_MIP_DEFLATE': return 'global_png'
    if a.get('surface_role') == 'base': return 'base'
    span = a.get('surface_lod_degrees', 2)
    if span == 16: return 'mid16'
    if span == 8: return 'mid8'
    return 'fine217' if a['width'] == 1088 else 'continuity1853'


SURFACE_CATALOGUES = ['france_r42','british_r43','german_r44','spain_r45','canary_r45','benelux_r46','europe_r48','siberian_r50','asian_r51','northern_r52','arid_r53','european_r55','sampling_r57']


def catalogue_assets():
    assets = {}
    paths = [ROOT/'data/presentation'/(slug.replace('_r','_surface_r')+'.json') for slug in SURFACE_CATALOGUES]
    paths.append(ROOT/'data/presentation/global_physical_relief.json')
    for path in paths:
        doc = json.loads(path.read_text(encoding='utf-8'))
        for fact in doc['evidence_catalog']['facts']:
            for asset in fact['value'].get('assets', []):
                assets[asset['id'].split(':',1)[1]] = asset
    return assets


def select():
    assets = catalogue_assets()
    packed = json.loads((ROOT/'local-artifacts/terrain-ab-20261026/pck-directory.json').read_text(encoding='utf-8'))
    present = {f['path']: f['bytes'] for f in packed['files']}
    names = ['canonical_r56_france_r42_46_+6', 'repair_r57_canonical_r56_france_r42_46_+0',
             'repair_r57_fine_r56_46_+14', 'canonical_r56_german_r44_48_+12']
    for target in [(60, 40), (30, 66)]:
        candidates = [(k, a) for k, a in assets.items() if k not in names and category(a) == 'fine217'
                      and a.get('surface_encoding') == 5 and a['path'].removeprefix('res://') in present]
        def distance(pair):
            b = pair[1]['core_bounds_lon_lat']; return ((b[0]+b[2])/2-target[0])**2+((b[1]+b[3])/2-target[1])**2
        names.append(min(candidates, key=distance)[0])
    names += ['repair_r57_mid16_r56_32_+0', 'global_region_r57_16_-32_+016',
              'global_region_r57_16_-32_-080', 'global_region_r57_16_-16_+176',
              'repair_r57_mid8_r56_40_+0', 'global_region_r57_south_asia_base0',
              'euro_afro_russia_r57_continuity_base', 'france_r42_base', 'british_r43_base',
              'german_r44_base', 'spain_r45_base', 'canary_r45_base', 'arid_r53_10_+34', 'world']
    selected = []
    for name in names:
        a = assets[name]
        if a['path'].removeprefix('res://') not in present: raise ValueError('Sample not in current PCK: '+name)
        if (ROOT/a['path'].removeprefix('res://')).stat().st_size != present[a['path'].removeprefix('res://')]:
            raise ValueError('PCK/source byte size mismatch: '+name)
        selected.append({k: a[k] for k in ['id','path','format','width','height','decoded_bytes','surface_encoding','surface_role','surface_lod_degrees','bounds_lon_lat','core_bounds_lon_lat'] if k in a})
    weights = {}; seen = set()
    for a in assets.values():
        path = a['path'].removeprefix('res://')
        if path not in present or path in seen: continue
        seen.add(path)
        key = category(a) + ':' + str(a.get('surface_encoding', 0))
        q = weights.setdefault(key, {'bytes':0,'count':0}); q['bytes'] += present[path]; q['count'] += 1
    return selected, weights


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT/'.gdignore').write_text('', encoding='utf-8')
    selected, weights = select()
    previous = {}
    if '--resume' in sys.argv and (OUT/'results.json').exists():
        previous = {s['asset']['id']:s for s in json.loads((OUT/'results.json').read_text(encoding='utf-8'))['samples']}
    results = []
    for a in selected:
        if a['id'] in previous:
            results.append(previous[a['id']]); continue
        name = a['id'].split(':', 1)[1]
        data, raw, w, h, bpp, mips = original(a)
        layout = list(levels(w, h, bpp, mips))
        row = {'asset':a, 'category':category(a), 'source_bytes':len(data), 'raw_bytes':len(raw),
               'mip_bytes':len(raw)-w*h*bpp, 'mip_levels':len(layout), 'candidates':{}}
        outputs = {}
        for label, level in [('zstd3',3), ('zstd6',6)]:
            began = time.perf_counter(); payload = zstd(raw, level)
            assert unzstd(payload, len(raw)) == raw
            row['candidates'][label] = {'bytes':28+len(payload), 'lossless':True, 'encode_ms':(time.perf_counter()-began)*1000}
            if label == 'zstd6': outputs[label] = (1, payload)
        p = np.frombuffer(raw, dtype=np.uint8).reshape(-1, bpp)
        planar = p.T.copy().tobytes(); payload = zstd(planar,6)
        assert np.frombuffer(unzstd(payload,len(raw)),dtype=np.uint8).reshape(bpp,-1).T.copy().tobytes() == raw
        row['candidates']['planar_zstd6'] = {'bytes':28+len(payload),'lossless':True}
        delta = np.frombuffer(raw,dtype=np.uint8).copy()
        for off, ww, hh, length in layout:
            v = delta[off:off+length].reshape(hh,ww,bpp); v[:,1:] = v[:,1:]-v[:,:-1]
        transformed = delta.reshape(-1,bpp).T.copy().tobytes(); payload = zstd(transformed,6)
        back = np.frombuffer(unzstd(payload,len(raw)),dtype=np.uint8).reshape(bpp,-1).T.copy().reshape(-1)
        for off, ww, hh, length in layout:
            v = back[off:off+length].reshape(hh,ww,bpp); np.cumsum(v,axis=1,dtype=np.uint8,out=v)
        assert back.tobytes() == raw
        row['candidates']['delta_planar_zstd6'] = {'bytes':28+len(payload),'lossless':True}
        # Keep this one transform specimen only, to measure the actual GDScript inverse cost.
        if name == 'canonical_r56_france_r42_46_+6': outputs['delta_planar_zstd6'] = (4,payload)
        chunks = []
        for off, ww, hh, length in layout:
            pic = np.frombuffer(raw,dtype=np.uint8,count=length,offset=off).reshape(hh,ww,bpp)
            chunk = png_bytes(rgba_for_png(pic)); assert restored_png(chunk,bpp) == raw[off:off+length]
            chunks.append(struct.pack('<I',len(chunk))+chunk)
        payload = struct.pack('<I',len(chunks))+b''.join(chunks)
        row['candidates']['mip_png6'] = {'bytes':28+len(payload),'lossless':True}; outputs['mip_png6']=(2,payload)
        # One PNG carrying the complete byte stream, with only final-row zero padding.
        hh = (len(p)+w-1)//w
        flat = np.zeros((hh*w,bpp),dtype=np.uint8); flat[:len(p)] = p
        payload = png_bytes(rgba_for_png(flat.reshape(hh,w,bpp)))
        assert restored_png(payload,bpp)[:len(raw)] == raw
        row['candidates']['flat_png6'] = {'bytes':28+len(payload),'lossless':True}; outputs['flat_png6']=(3,payload)
        for label,(codec,payload) in outputs.items():
            path = OUT/(name+'.'+label+'.bin')
            path.write_bytes(HEADER.pack(MAGIC,1,codec,(bpp<<8)|int(mips),w,h,len(raw),len(payload))+payload)
            row['candidates'][label]['path'] = 'res://'+path.relative_to(ROOT).as_posix()
        results.append(row)
        (OUT/'results.json').write_text(json.dumps({'samples':results,'weights':weights},ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps({'id':name,'source':len(data),'candidates':{k:v['bytes'] for k,v in row['candidates'].items()}},ensure_ascii=True),flush=True)
        del raw, data, p, planar, delta, transformed, back, flat, outputs, payload
    (OUT/'results.json').write_text(json.dumps({'samples':results,'weights':weights},ensure_ascii=False,indent=2),encoding='utf-8')
    print('A0_ENCODING_DONE',len(results),flush=True)


def webp_followup():
    document = json.loads((OUT/'results.json').read_text(encoding='utf-8'))
    for row in document['samples']:
        a = row['asset']; name = a['id'].split(':',1)[1]
        _, raw, w, h, bpp, mips = original(a)
        p = np.frombuffer(raw,dtype=np.uint8).reshape(-1,bpp)
        hh = (len(p)+w-1)//w
        flat = np.zeros((hh*w,bpp),dtype=np.uint8); flat[:len(p)] = p
        image = Image.fromarray(rgba_for_png(flat.reshape(hh,w,bpp)))
        stream = io.BytesIO(); began = time.perf_counter()
        image.save(stream,format='WEBP',lossless=True,exact=True,quality=100,method=4)
        payload = stream.getvalue()
        recovered = np.asarray(Image.open(io.BytesIO(payload)).convert('RGBA'),dtype=np.uint8)[:,:,:bpp].tobytes()[:len(raw)]
        assert recovered == raw, name+' WebP is not exact'
        path = OUT/(name+'.flat_webp.bin')
        path.write_bytes(HEADER.pack(MAGIC,1,5,(bpp<<8)|int(mips),w,h,len(raw),len(payload))+payload)
        row['candidates']['flat_webp']={'bytes':path.stat().st_size,'lossless':True,'encode_ms':(time.perf_counter()-began)*1000,'path':'res://'+path.relative_to(ROOT).as_posix()}
        print(json.dumps({'id':name,'source':row['source_bytes'],'webp':path.stat().st_size},ensure_ascii=True),flush=True)
        (OUT/'results.json').write_text(json.dumps(document,ensure_ascii=False,indent=2),encoding='utf-8')
        del raw,p,flat,image,payload,recovered
    print('A0_WEBP_DONE',flush=True)


def redundancy():
    doc=json.loads((ROOT/'data/presentation/sampling_surface_r57.json').read_text(encoding='utf-8'))
    assets={a['id'].split(':',1)[1]:a for f in doc['evidence_catalog']['facts'] for a in f['value']['assets']}
    def layer(name,lod):
        a=assets[name];_,raw,w,h,bpp,mips=original(a)
        off,ww,hh,n=list(levels(w,h,bpp,mips))[lod]
        return a,np.frombuffer(raw,dtype=np.uint8,count=n,offset=off).reshape(hh,ww,bpp).copy()
    rows=[]
    def compare(label,x,y):
        if x.shape!=y.shape:raise ValueError('Unaligned comparison')
        exact=np.all(x==y,axis=2);diff=np.abs(x.astype(np.int16)-y.astype(np.int16))
        row={'case':label,'pixels':exact.size,'exact_pixel_fraction':float(exact.mean()),'all_bytes_equal':bool(np.array_equal(x,y)),'mean_abs_byte_difference':float(diff.mean()),'max_abs_byte_difference':int(diff.max())}
        # Count only truly equal, aligned 16x16 full-RGBA blocks; no hashing.
        good=total=0
        for yy in range(0,x.shape[0]-15,16):
            for xx in range(0,x.shape[1]-15,16):
                total+=1;good+=int(np.array_equal(x[yy:yy+16,xx:xx+16],y[yy:yy+16,xx:xx+16]))
        row['equal_16px_blocks']=good;row['tested_16px_blocks']=total;rows.append(row)
    for left,right in [('repair_r57_canonical_r56_france_r42_46_+0','repair_r57_canonical_r56_france_r42_46_+2'),('global_region_r57_16_-32_+016','global_region_r57_16_-32_+032')]:
        for lod in range(3):
            _,x=layer(left,lod);_,y=layer(right,lod);shift=1024//2**lod
            compare(left+' east collar mip '+str(lod),x[:,shift:],y[:,:x.shape[1]-shift])
    for fine,lod,coarse in [('repair_r57_canonical_r56_france_r42_46_+0',2,'repair_r57_mid8_r56_40_+0'),('repair_r57_mid8_r56_40_+0',1,'repair_r57_mid16_r56_32_+0')]:
        a,x=layer(fine,lod);b,y=layer(coarse,0)
        step=(b['bounds_lon_lat'][2]-b['bounds_lon_lat'][0])/b['width']
        dx=round((a['bounds_lon_lat'][0]-b['bounds_lon_lat'][0])/step)
        dy=round((b['bounds_lon_lat'][3]-a['bounds_lon_lat'][3])/step)
        compare(fine+' mip '+str(lod)+' vs '+coarse,x,y[dy:dy+x.shape[0],dx:dx+x.shape[1]])
    (OUT/'redundancy.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    print(json.dumps(rows),flush=True)


def memory_profile():
    import subprocess
    import threading
    class Counters(C.Structure):
        _fields_=[('cb',C.c_ulong),('faults',C.c_ulong)]+[(k,C.c_size_t) for k in ['peak_working','working','peak_paged','paged','peak_nonpaged','nonpaged','pagefile','peak_pagefile','private']]
    get_memory=C.WinDLL('psapi').GetProcessMemoryInfo
    get_memory.argtypes=[C.c_void_p,C.POINTER(Counters),C.c_ulong];get_memory.restype=C.c_int
    profiles=[]
    for name in ['canonical_r56_france_r42_46_+6','global_region_r57_south_asia_base0']:
        for method in ['original','zstd6','mip_png6','flat_webp']:
            proc=subprocess.Popen(['D:/Tools/Godot-4.6.3/Godot_v4.6.3-stable_win64.exe','--headless','--path',str(ROOT),'--script','tools/map/terrain_a0_verify.gd','--',name,method],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
            state={'active':False};samples=[];record=None;transcript=[]
            def watch():
                while proc.poll() is None:
                    if state['active']:
                        c=Counters();c.cb=C.sizeof(c)
                        if get_memory(int(proc._handle),C.byref(c),c.cb):samples.append((time.perf_counter(),c.working,c.private))
                    time.sleep(.001)
            thread=threading.Thread(target=watch);thread.start()
            for line in proc.stdout:
                transcript.append(line)
                if line.startswith('A0_BEGIN '):state['active']=True
                if line.startswith('A0_MEASURE_END'):state['active']=False
                if line.startswith('A0_END '):record=json.loads(line[len('A0_END '):])
            code=proc.wait();thread.join()
            if code or record is None or not record['equal'] or len(samples)<10:raise RuntimeError('Godot memory trial failed: '+''.join(transcript))
            baseline=int(np.median([s[1] for s in samples[:15]]));peak=max(s[1] for s in samples)
            row={'id':name,'method':method,'working_baseline_bytes':baseline,'working_peak_bytes':peak,'working_peak_delta_bytes':peak-baseline,'private_peak_bytes':max(s[2] for s in samples),'sample_count':len(samples),'decode_us':record['us'],'equal':record['equal']}
            profiles.append(row);print(json.dumps(row),flush=True)
            (OUT/'memory.json').write_text(json.dumps(profiles,indent=2),encoding='utf-8')
    print('A0_MEMORY_DONE',len(profiles),flush=True)


def batch_summary(rows):
    rows = list(rows)
    return {'processed':len(rows),'source_bytes':sum(r['source_bytes'] for r in rows),'chosen_bytes':sum(r['chosen_bytes'] for r in rows),'saved_bytes':sum(r['source_bytes']-r['chosen_bytes'] for r in rows),'webp_selected':sum(r['chosen_format']=='RGBA8_MIP_FRA0' for r in rows)}


def select_measured_encoding(output):
    """Keep original for reproducible large-base latency regressions, not size alone."""
    path = output/'manifest.json'
    document = json.loads(path.read_text(encoding='utf-8'))
    loose = {r['id']:r for r in json.loads((output/'godot-batch-decode.json').read_text(encoding='utf-8'))}
    packed = {r['id']:r for r in json.loads((output/'godot-packed-decode.json').read_text(encoding='utf-8'))}
    retained = []
    for row in document['files']:
        id = row['asset']['id'].split(':',1)[1]
        if row['category']!='base' or row['raw_bytes']<16777216:
            continue
        measurements = [loose[id],packed[id]]
        if all(m['candidate_us']-m['source_us']>100000 and m['candidate_us']>m['source_us']*1.4 for m in measurements):
            row['decode_policy'] = {'choice':'original','reason':'Both loose and actual-PCK three-read medians add >100ms and >40%; do not hide behind background decoding','measurements':measurements}
            row['chosen_format'] = row['asset']['format']
            row['chosen_bytes'] = row['source_bytes']
            row['candidate_path'] = row['asset']['path'].removeprefix('res://')
            retained.append(id)
    document['summary'] = batch_summary(document['files'])
    path.write_text(json.dumps(document,ensure_ascii=False,indent=2),encoding='utf-8')
    print('BATCH_LATENCY_RETENTION',json.dumps(retained),flush=True)
    print('BATCH_SELECTED',json.dumps(document['summary']),flush=True)


def batch_webp():
    """Incremental production representation, scoped to the actual R59 pack."""
    import argparse
    from concurrent.futures import ThreadPoolExecutor, as_completed
    parser = argparse.ArgumentParser()
    parser.add_argument('--batch', action='store_true')
    parser.add_argument('--categories', default='fine217,mid16')
    parser.add_argument('--select-from-godot', action='store_true')
    parser.add_argument('--workers', type=int, default=3)
    parser.add_argument('--output', default='local-artifacts/terrain-lossless-20261027')
    parser.add_argument('--temporary-budget-mib', type=int, required=True)
    args = parser.parse_args()
    output = (ROOT/args.output).resolve()
    if not output.is_relative_to(ROOT/'local-artifacts') or args.workers not in range(1,5):
        raise ValueError('Candidate output/workers outside bounded preparation')
    output.mkdir(parents=True,exist_ok=True)
    if args.select_from_godot:
        select_measured_encoding(output)
        return
    packed = json.loads((output/'baseline-directory.json').read_text(encoding='utf-8'))
    baseline = Path(packed['container'])
    if baseline.stat().st_size != packed['container_bytes']:
        raise ValueError('Baseline container changed')
    present = {v['path']:v for v in packed['files']}
    def packed_bytes(path):
        entry = present[path]
        with baseline.open('rb') as file:
            file.seek(entry['offset'])
            data = file.read(entry['bytes'])
        if len(data)!=entry['bytes']:
            raise ValueError('Truncated baseline resource')
        return data
    catalogues = ['data/presentation/'+slug.replace('_r','_surface_r')+'.json' for slug in SURFACE_CATALOGUES]
    catalogues.append('data/presentation/global_physical_relief.json')
    assets = {}
    for path in catalogues:
        doc = json.loads(packed_bytes(path))
        for fact in doc['evidence_catalog']['facts']:
            for asset in fact['value'].get('assets',[]):
                assets[asset['id'].split(':',1)[1]] = asset
    unique = {}
    for asset in assets.values():
        path = asset['path'].removeprefix('res://')
        if path in present:
            if path in unique and any(unique[path].get(k)!=asset.get(k) for k in ['format','width','height','decoded_bytes']):
                raise ValueError('Conflicting catalogue storage metadata: '+path)
            unique[path] = asset
    categories = set(args.categories.split(','))
    selected = [a for path,a in sorted(unique.items()) if a['format']=='RGBA8_MIP_DEFLATE' and (args.categories=='all' or category(a) in categories)]
    if sum(present[a['path'].removeprefix('res://')]['bytes'] for a in unique.values()) > args.temporary_budget_mib*1024**2:
        raise ValueError('Declare a sufficient candidate preparation budget')
    manifest_path = output/'manifest.json'
    document = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {'schema':1,'baseline':str(baseline),'baseline_bytes':packed['container_bytes'],'baseline_pck_bytes':packed['pck_bytes'],'catalogues':catalogues,'files':[]}
    records = {row['asset']['path']:row for row in document['files']}
    samples = {row['asset']['path']:row for row in json.loads((OUT/'results.json').read_text(encoding='utf-8'))['samples']}
    def convert(asset):
        source = ROOT/asset['path'].removeprefix('res://')
        before = source.stat()
        data,raw,w,h,bpp,mips = original(asset)
        if data != packed_bytes(asset['path'].removeprefix('res://')):
            raise ValueError('Local original differs from actual R59 bytes: '+str(source))
        name = asset['path'].removeprefix('res://')
        candidate = output/'resources'/name
        if not candidate.resolve().is_relative_to(output/'resources') or candidate.resolve()==source.resolve():
            raise ValueError('Unsafe candidate resource path')
        reused = False
        sample_path = samples.get(asset['path'],{}).get('candidates',{}).get('flat_webp',{}).get('path')
        known = candidate if candidate.exists() else ROOT/sample_path.removeprefix('res://') if sample_path else None
        began = time.perf_counter()
        if known is not None and known.exists():
            encoded = known.read_bytes()
            header = HEADER.unpack(encoded[:HEADER.size])
            if header != (MAGIC,1,5,1025,w,h,len(raw),len(encoded)-HEADER.size):
                raise ValueError('Resume candidate header differs: '+str(known))
            payload = encoded[HEADER.size:]
            reused = True
        else:
            pixels = np.frombuffer(raw,dtype=np.uint8).reshape(-1,4)
            flat_height = (len(pixels)+w-1)//w
            flat = np.zeros((flat_height*w,4),dtype=np.uint8)
            flat[:len(pixels)] = pixels
            image = Image.fromarray(rgba_for_png(flat.reshape(flat_height,w,4)))
            stream = io.BytesIO()
            image.save(stream,format='WEBP',lossless=True,exact=True,quality=100,method=4)
            payload = stream.getvalue()
            encoded = HEADER.pack(MAGIC,1,5,1025,w,h,len(raw),len(payload))+payload
        encode_ms = (time.perf_counter()-began)*1000
        began = time.perf_counter()
        decoded_image = Image.open(io.BytesIO(payload)).convert('RGBA')
        if decoded_image.size != (w,(len(raw)//4+w-1)//w):
            raise ValueError('Invalid flat lossless image size')
        recovered = decoded_image.tobytes()[:len(raw)]
        if recovered != raw:
            raise ValueError('Full RGBA/Mip bytes differ: '+str(source))
        verify_ms = (time.perf_counter()-began)*1000
        decode_policy = records.get(asset['path'],{}).get('decode_policy')
        use_webp = len(encoded)<len(data) and not (decode_policy and decode_policy['choice']=='original')
        if use_webp and not candidate.exists():
            candidate.parent.mkdir(parents=True,exist_ok=True)
            candidate.write_bytes(encoded)
        if source.stat().st_mtime_ns != before.st_mtime_ns or source.stat().st_size != before.st_size:
            raise ValueError('Original changed during conversion: '+str(source))
        return {'asset':asset,'category':category(asset),'source_bytes':len(data),'encoded_bytes':len(encoded),'chosen_bytes':len(encoded) if use_webp else len(data),'chosen_format':'RGBA8_MIP_FRA0' if use_webp else asset['format'],'candidate_path':candidate.relative_to(ROOT).as_posix() if use_webp else source.relative_to(ROOT).as_posix(),'source_mtime_ns':before.st_mtime_ns,'raw_bytes':len(raw),'mip_levels':len(list(levels(w,h,4,True))),'mip_bytes':len(raw)-w*h*4,'transparent_pixels_all_levels':int(np.count_nonzero(np.frombuffer(raw,dtype=np.uint8).reshape(-1,4)[:,3]==0)),'full_rgba_mips_equal':True,'transparent_rgb_equal':True,'encode_or_reuse_ms':encode_ms,'verify_decode_ms':verify_ms,'reused':reused,'decode_policy':decode_policy}
    print('BATCH_BEGIN',len(selected),'workers',args.workers,'categories',args.categories,flush=True)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(convert,a):a for a in selected}
        for completed,future in enumerate(as_completed(futures),1):
            row = future.result()
            records[row['asset']['path']] = row
            if completed%25==0 or completed==len(selected):
                # Candidate bytes are already durable. A restart revalidates
                # the last <=24 files, without O(N²) full-JSON writes per item.
                document['files'] = sorted(records.values(),key=lambda r:r['asset']['path'])
                document['summary'] = batch_summary(records.values())
                manifest_path.write_text(json.dumps(document,ensure_ascii=False,indent=2),encoding='utf-8')
            print('BATCH_FILE',len(records),row['category'],row['asset']['id'],row['source_bytes'],row['chosen_bytes'],'equal=true',flush=True)
    print('BATCH_DONE',json.dumps(document['summary']),flush=True)


if __name__ == '__main__':
    if '--batch' in sys.argv: batch_webp()
    elif '--webp' in sys.argv: webp_followup()
    elif '--profile' in sys.argv: memory_profile()
    elif '--redundancy' in sys.argv: redundancy()
    elif '--reweight' in sys.argv:
        document=json.loads((OUT/'results.json').read_text(encoding='utf-8'));document['weights']=select()[1]
        (OUT/'results.json').write_text(json.dumps(document,ensure_ascii=False,indent=2),encoding='utf-8')
        print('weight_bytes',sum(x['bytes'] for x in document['weights'].values()))
    else: main()
