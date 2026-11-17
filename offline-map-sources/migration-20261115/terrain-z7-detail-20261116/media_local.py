import gzip, json, math, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont
import numpy as np

root=Path(__file__).resolve().parent
out=root.parent.parent.parent/'wwo-character-integration/docs/terrain-z7-detail'
out.mkdir(exist_ok=True)
assets=root/'archive'
assets.mkdir(exist_ok=True)
def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))
def frame(p):
    return Image.frombytes('RGBA',(1280,720),p.read_bytes()).convert('RGB')
def jpg(p):
    return Image.open(p).convert('RGB')
def font(size):
    return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',size)
def sheet(output, rows, width=640):
    height=width*9//16
    pane=Image.new('RGB',(width*max(map(len,rows)),(height+34)*len(rows)),(23,28,36))
    draw=ImageDraw.Draw(pane)
    for r,row in enumerate(rows):
        for c,(path,label) in enumerate(row):
            image=frame(path) if path.suffix=='.rgba' else jpg(path)
            left=c*width
            top=r*(height+34)
            pane.paste(image.resize((width,height),Image.Resampling.LANCZOS),(left,top+34))
            draw.text((left+10,top+5),label, font=font(17),fill=(245,246,249))
    pane.save(out/output,quality=87,optimize=True)

def stills(use_candidate=True):
    base=root/'baseline-stills'
    final=root/'final-stills'
    cand=root/'candidate-stills'
    if not use_candidate:
        final=cand
    continents=('亚洲','欧洲','非洲','北美洲','南美洲','大洋洲','南极洲')
    rows=[[((final if i==7 else cand)/f'continent-{i}-{view}.png',f'{label} · {["区域","近景"][idx]}')
           for idx,view in enumerate(('regional','close'))] for i,label in enumerate(continents,1)]
    sheet('continents.jpg',rows[:4],544)
    sheet('continents-south.jpg',rows[4:],544)
    cases=(('alps-corner','阿尔卑斯山脉 · 四角'),('wadden-edge','瓦登海屏障岛 · 共享边'),
           ('prairie','北美中部平原'),('tibet','羌塘高原'),
           ('obidos','亚马孙奥比杜斯河谷'),('mekong','湄公河三角洲'),
           ('new-zealand','库克海峡'),('guinea','几内亚湾海底'),
           ('dateline','反经线 · 白令海'),('north-pole','北极'),
           ('south-pole','南极点'),('mascarene','马斯克林海底'))
    sheet('landforms.jpg',[[((final if name=='south-pole' else cand)/(name+'.png'),label) for name,label in cases[i:i+3]] for i in range(0,len(cases),3)],464)
    issues=(('greenland','格陵兰 · 冰面蓝线'),('sahara','撒哈拉 · 露出水道'),('bosten','博斯腾湖 · 孤立河线'),('mascarene','马斯克林 · 海底斜带'))
    sheet('source-questions.jpg',[[(cand/(name+'.png'),label) for name,label in issues[i:i+2]] for i in range(0,4,2)])
    if use_candidate:
        sites=(('ross-shelf','罗斯冰架内侧'),('ronne-shelf','龙尼—菲尔希纳冰架'),('ross-front','罗斯冰架外缘'))
        sheet('shelves.jpg',[[(folder/(name+'.png'),label+' · '+kind) for folder,kind in ((base,'原版'),(final,'候选'))] for name,label in sites])

def frames_path(group):
    return sorted(group.glob('*.rgba'))

def image_stats(path):
    data=np.frombuffer(path.read_bytes(),dtype=np.uint8).reshape(720,1280,4)[24:-24,24:-24,:3].astype(np.float32)
    luma=data[...,0]*.2126+data[...,1]*.7152+data[...,2]*.0722
    return [round(float(s),3) for s in (*data.mean((0,1)),luma.mean(),np.abs(luma[:,1:]-luma[:,:-1]).mean(),np.abs(luma[1:]-luma[:-1]).mean())]

def playback(output, groups):
    ff='D:/programs/WWO/offline-map-sources/python-libs/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
    side=max(map(len,groups))>1
    cmd=[ff,'-hide_banner','-loglevel','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s','1280x720','-r','20','-i','-','-vf','format=yuv420p','-c:v','libx264','-preset','fast','-crf','21','-threads','2','-movflags','+faststart',str(assets/output)]
    with subprocess.Popen(cmd,stdin=subprocess.PIPE) as enc:
        for group in groups:
            files=[frames_path(path) for path,label in group]
            for i in range(min(map(len,files))):
                pane=frame(files[0][i])
                if len(group)>1:
                    pane=Image.new('RGB',(1280,720),(25,29,37))
                    for c,(path,label) in enumerate(group):
                        pane.paste(frame(files[c][i]).resize((640,360),Image.Resampling.LANCZOS),(640*c,175))
                        ImageDraw.Draw(pane).text((20+c*640,148),label,font=font(18),fill='white')
                draw=ImageDraw.Draw(pane)
                draw.rectangle((0,0,650,29),fill=(25,29,37))
                draw.text((8,3),f'{group[0][0].name}   {i+1:03}/{min(map(len,files)):03}   20 fps playback',font=font(16),fill='white')
                enc.stdin.write(pane.tobytes())
        enc.stdin.close()
        if enc.wait():
            raise RuntimeError(output)

def motion():
    baseline=root/'before-jump'
    candidate=root/'after-jump-v2'
    cases=[('alps-corner','阿尔卑斯四角'),('coast-corner','海岸四角')]
    compare=[]
    for name,label in cases:
        compare.extend([[(folder/name/f'{i:04}.rgba',f'{label} · {kind} · 帧 {i+1}') for folder,kind in ((baseline,'原版'),(candidate,'候选'))] for i in (11,12,13,18)])
    sheet('zoom-jump.jpg',compare,460)
    playback('z7-detail-rapid.mp4',[[(baseline/name,'原版'),(candidate/name,'候选')] for name,label in cases])
    playback('z7-detail-wheel.mp4',[[(candidate/name,'候选')] for name in ('slow-warm','wheel-reversal','threshold','pan-rotate','antarctic-interface','ross-full-lod','overflow')]+[[(root/'candidate-cold-v2/alps-cold','候选')],[(root/'candidate-fixed-motion-v2/oblique','候选')],[(root/'fixed-overflow/pole','候选')]])
    summary={}
    paths=(baseline,candidate,root/'candidate-cold-v2',root/'candidate-fixed-motion-v2',root/'fixed-overflow')
    for folder in paths:
        for json_path in folder.glob('*.json'):
            if json_path.name in ('map.json','map.response.json'):
                continue
            clip=read(json_path)
            clip.pop('folder',None)
            f=frames_path(folder/json_path.stem)
            clip['raster_metrics']={'columns':['mean_R','mean_G','mean_B','mean_luma','mean_abs_horizontal_luma_gradient','mean_abs_vertical_luma_gradient'], 'values':[image_stats(p) for p in f]}
            summary[f'{folder.name}/{json_path.stem}']=clip
    still_json={}
    for dirname in ('baseline-stills','candidate-stills','final-stills','formal-after-ok'):
        for p in (root/dirname).glob('*.json'):
            if (p.with_suffix('.png')).exists():
                item=read(p)
                item.pop('id',None)
                if 'extra' in item and 'png' in item['extra']:
                    item['extra']['png']=p.with_suffix('.png').name
                still_json[f'{dirname}/{p.stem}']=item
    formal={kind:read(root/kind/'formal.json') for kind in ('formal-before-ok','formal-after-ok')}
    meta=dict(frame_clips=summary,stills=still_json,formal=formal)
    with gzip.open(assets/'z7-detail-frames.json.gz','wt',encoding='utf-8') as gz:
        json.dump(meta,gz,ensure_ascii=False,separators=(',',':'))
    import zipfile
    with zipfile.ZipFile(assets/'z7-detail-stills.zip','w',compression=zipfile.ZIP_STORED) as archive:
        for dirname in ('baseline-stills','candidate-stills','final-stills','formal-after-ok'):
            for source in (root/dirname).glob('*.png'):
                if dirname == 'candidate-stills' and ((root/'final-stills'/source.name).exists()):
                    continue
                archive.write(source,dirname+'/'+source.name)
    full=candidate/'ross-full-lod'
    clip=read(candidate/'ross-full-lod.json')['frames']
    z6=next(i for i,f in enumerate(clip) if f['terrain']['target_level']==6 and f['terrain']['draw_max_level']==6)
    same=[i for i,f in enumerate(clip) if f['mpp']==clip[z6]['mpp'] and f['terrain']['draw_max_level']==6]
    sheet('antarctic-lod.jpg',[[(full/f'{i:04}.rgba',f'罗斯冰架 · {clip[i]["mpp"]:.0f} 米／像素 · 帧 {i+1}') for i in (0,z6)],[(full/f'{i:04}.rgba',f'罗斯冰架 · {clip[i]["mpp"]:.0f} 米／像素 · 帧 {i+1}') for i in (same[-1],len(clip)-1)]],600)
    sheet('formal.jpg',[[(root/'formal-after-ok'/f'{mode}.png',label) for mode,label in row] for row in ((('geographic','地理 · 罗斯冰架'),('political','政治 · 阿尔卑斯')),(('economic','经济 · 阿尔卑斯'),('military','军事 · 阿尔卑斯')))],580)

if __name__=='__main__':
    if sys.argv[1]=='stills':
        stills()
    elif sys.argv[1]=='motion':
        motion()
