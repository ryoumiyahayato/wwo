#!/usr/bin/env python3
"""Original Cedar Valley comparison assets. No downloaded commercial assets.
Requires numpy, scipy, pillow, trimesh. Deterministic seed 20261019.
Coordinates: metres; +Y up, -Z forward. Rebuild only cedar/assets.
"""
from pathlib import Path
import json, math, hashlib
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, zoom
import trimesh

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets'; OUT.mkdir(exist_ok=True)
rng=np.random.default_rng(20261019)
roads=[
 [(-470,-750),(-210,-460),(-82,-230),(-38,-45),(-39,15),(-68,135),(-46,300),(26,515),(210,710),(520,930)],
 [(-620,190),(-330,128),(-180,112),(-72,118),(80,116),(232,186),(520,255),(850,160)],
 [(-410,-350),(-245,-145),(-191,25),(-170,114),(-163,236),(-280,390),(-540,560)],
 [(-245,-145),(-80,-93),(90,-44),(230,22),(232,186),(215,365),(25,515)],
 [(215,365),(390,470),(520,770)]
]
buildings=[]
# Open roads and yards between groups; original deployment corridor stays clear.
for i,(x,z,rot) in enumerate([(-133,60,0),(-124,93,0),(-126,143,0),(-130,181,0),(-206,67,math.pi),(-210,102,math.pi),(-205,148,math.pi),(-205,184,math.pi),(-150,240,math.pi/2),(-212,244,0),(-104,240,0),(-275,152,math.pi/2)]):
 buildings.append(dict(id=f'house_{i:02d}',kind=f'house_{i%3}',position=[x,0,z],yaw=rot,scale=1.0,collision='solid_building'))
buildings += [dict(id='chapel',kind='chapel',position=[-230,218,0],yaw=0,scale=1.0,collision='solid_building')] if False else []
buildings += [dict(id='chapel',kind='chapel',position=[-253,0,220],yaw=0,scale=1.0,collision='solid_building'),dict(id='village_barn',kind='barn',position=[-275,0,102],yaw=math.pi/2,scale=1.0,collision='solid_building'),dict(id='farm_barn',kind='barn',position=[292,0,225],yaw=-.15,scale=1.0,collision='solid_building'),dict(id='farm_house',kind='house_1',position=[278,0,273],yaw=-.15,scale=1.15,collision='solid_building'),dict(id='south_barn',kind='barn',position=[-310,0,-105],yaw=.3,scale=.9,collision='solid_building'),dict(id='south_house',kind='house_0',position=[-353,0,-97],yaw=.3,scale=1.1,collision='solid_building'),dict(id='north_house',kind='house_2',position=[90,0,490],yaw=.45,scale=1.0,collision='solid_building'),dict(id='north_barn',kind='barn',position=[90,0,542],yaw=.45,scale=1.0,collision='solid_building')]
fields=[(-310,340,120,180,0),(-90,390,120,160,1),(110,290,115,150,2),(365,110,140,170,0),(405,315,140,150,1),(-345,-260,140,150,2),(-135,-325,120,140,1),(92,-197,150,145,0),(-380,12,95,160,0),(-40,195,70,100,2),(50,30,85,85,1),(355,-100,150,125,2)]

def dist_roads(x,z):
 d=np.full(np.broadcast(x,z).shape,1e6,dtype=np.float32)
 for line in roads:
  for (a,b),(c,e) in zip(line,line[1:]):
   vx,vz=c-a,e-b; q=np.clip(((x-a)*vx+(z-b)*vz)/(vx*vx+vz*vz),0,1)
   d=np.minimum(d,np.hypot(x-(a+q*vx),z-(b+q*vz)))
 return d

def base_h(x,z):
 h=8+11*np.sin(x/440)*np.cos(z/590)+7*np.sin((x+z)/720)
 for cx,cz,a,rx,rz in [(520,450,90,290,350),(-550,490,65,280,270),(-650,-400,62,360,410),(400,-620,88,340,250),(1400,1100,145,650,580),(-1450,800,125,650,660),(900,-1600,180,600,740),(-1400,-1300,95,570,600)]:
  h+=a*np.exp(-(((x-cx)/rx)**2+((z-cz)/rz)**2))
 flat=np.exp(-((x/185)**4+((z-85)/330)**4))
 return h*(1-flat)+(5+.008*x+.008*z)*flat

N=1251; step=4.0
axis=np.linspace(-2500,2500,N,dtype=np.float32); X,Z=np.meshgrid(axis,axis)
H=base_h(X,Z).astype(np.float32)
# Grade building pads against the same base field, not a second collision height.
for b in buildings:
 x,_,z=b['position']; y=float(base_h(np.array(x),np.array(z)));b['position'][1]=y
 sx=15 if b['kind']=='barn' else 12;sz=15 if b['kind']=='chapel' else 12
 w=np.clip(1-(np.maximum(abs(X-x)/sx,abs(Z-z)/sz)-.65)/.6,0,1);w=w*w*(3-2*w)
 H=H*(1-w)+y*w
# Float32 little endian field, constant-time runtime sampling; magic in config.
H.astype('<f4').tofile(OUT/'height_4m.f32')

def sample(x,z):
 fx=np.clip((np.asarray(x)+2500)/4,0,N-1.000001);fz=np.clip((np.asarray(z)+2500)/4,0,N-1.000001)
 ix=fx.astype(int);iz=fz.astype(int);tx=fx-ix;tz=fz-iz
 return H[iz,ix]*(1-tx)*(1-tz)+H[iz,ix+1]*tx*(1-tz)+H[iz+1,ix]*(1-tx)*tz+H[iz+1,ix+1]*tx*tz
for b in buildings:b['position'][1]=float(sample(b['position'][0],b['position'][2]))
# Coarse color/semantic control shares the same map origin, no weather authority.
S=2048;a=np.linspace(-2500,2500,S,dtype=np.float32); xx,zz=np.meshgrid(a,a)
noise=gaussian_filter(rng.random((256,256)),2.2); noise=zoom(noise,(8,8),order=1)[:S,:S]
noise=(noise-noise.mean())/max(noise.std(),1e-9)
col=np.zeros((S,S,3),np.float32);col[:]=[.34,.405,.235];col+=noise[:,:,None]*np.array([.016,.018,.011])
field_mask=np.zeros((S,S),np.float32)
for cx,cz,w,h,k in fields:
 mask=(abs(xx-cx)<w/2)&(abs(zz-cz)<h/2)
 color=[[.53,.485,.285],[.38,.30,.205],[.30,.385,.21]][k]
 col[mask]=np.asarray(color)+noise[mask,None]*.009;field_mask[mask]=(k+1)/3
# Regional patches keep 5 km countryside coherent beyond focal village.
far=(np.hypot(xx,zz)>780)&(np.hypot(xx,zz)<1900)
patch=((np.floor((xx+2500)/260)+np.floor((zz+2500)/220))%5==0)&far
col[patch]=[.43,.425,.25]
rd=dist_roads(xx,zz);rw=1-np.clip((rd-4.25)/2.5,0,1);rw=rw*rw*(3-2*rw)
yards=np.zeros_like(rw)
for b in buildings:
 x,_,z=b['position']; q=1-np.clip((np.maximum(abs(xx-x)/14,abs(zz-z)/16)-.9)/.5,0,1);yards=np.maximum(yards,q)
soil=np.maximum(rw,yards*.8); col=col*(1-soil[:,:,None])+np.array([.57,.525,.414])*soil[:,:,None]
hs=zoom(H,((S-1)/(N-1),(S-1)/(N-1)),order=1)[:S,:S]
# slope rock zones influence color only, collision remains height field.
gx,gz=np.gradient(hs,5000/(S-1)); rock=np.clip((np.hypot(gx,gz)-.32)/.22,0,.7)
col=col*(1-rock[:,:,None])+np.array([.425,.43,.40])*rock[:,:,None]
Image.fromarray(np.clip(col*255,0,255).astype('uint8'),'RGB').save(OUT/'land_color.png',optimize=True)
control=np.stack([soil,field_mask,rock],axis=2);Image.fromarray(np.clip(control*255,0,255).astype('uint8')).save(OUT/'land_control.png',optimize=True)
# Seamless RGB detail carries gravel/soil/grass frequency at close view.
T=512; n=rng.random((T,T)); n=.65*n+.35*gaussian_filter(n,2,mode='wrap')
for name,color in [('grass',[.55,.61,.37]),('soil',[.65,.595,.49]),('stone',[.60,.60,.565])]:
 detail=(n-.5)*.16
 if name=='grass':detail+=gaussian_filter(rng.random((T,T)),(.35,4.0),mode='wrap')*.18-.09
 if name=='soil':detail+=np.where(rng.random((T,T))>.989,.14,0)
 rgb=np.clip(np.asarray(color)[None,None,:]+detail[:,:,None],0,1)
 Image.fromarray((rgb*255).astype('uint8'),'RGB').save(OUT/f'{name}_detail.png',optimize=True)
# UV-independent tiled micro surface for hull dressing and walls.
Image.fromarray(np.uint8(np.clip(n*255,0,255)),'L').save(OUT/'surface_noise.png',optimize=True)

palette={'plaster':'bcb99f','plaster2':'aaa58c','plaster3':'c6bea9','stone':'777767','roof':'795344','wood':'514638','glass':'303d3d','iron':'353c36','crop':'b9a56b','leaf':'566940','bark':'5c5140'}
def rgba(c):
 if isinstance(c,str):return np.array([int(c[i:i+2],16) for i in (0,2,4)]+[255],np.uint8)
 return np.array(list(c)+([255] if len(c)==3 else []),np.uint8)
def paint(m,c,var=0):
 v=np.tile(rgba(c),(len(m.vertices),1));
 if var:
  v[:,:3]=np.clip(v[:,:3].astype(float)+rng.normal(0,var,(len(v),1)),0,255).astype(np.uint8)
 m.visual=trimesh.visual.ColorVisuals(mesh=m,vertex_colors=v);return m

def bx(parts,p,size,c,rot=None):
 m=trimesh.creation.box(extents=size)
 if rot is not None:m.apply_transform(trimesh.transformations.rotation_matrix(rot,[0,1,0]))
 m.apply_translation(p);parts.append(paint(m,c));return m

def cyl(parts,p,r,h,c,axis='y',sections=12):
 m=trimesh.creation.cylinder(radius=r,height=h,sections=sections)
 if axis=='y':m.apply_transform(trimesh.transformations.rotation_matrix(-math.pi/2,[1,0,0]))
 if axis=='x':m.apply_transform(trimesh.transformations.rotation_matrix(math.pi/2,[0,1,0]))
 m.apply_translation(p);parts.append(paint(m,c));return m

def beam(parts,a,b,r,c,sides=7):
 a=np.array(a);b=np.array(b);m=trimesh.creation.cylinder(radius=r,height=float(np.linalg.norm(b-a)),sections=sides)
 m.apply_transform(trimesh.geometry.align_vectors([0,0,1],b-a));m.apply_translation((a+b)*.5);parts.append(paint(m,c));return m

def save(parts,name):
 m=trimesh.util.concatenate(parts)
 # One opaque material/surface; vertex colors preserve all sub-part materials.
 scene=trimesh.Scene();scene.add_geometry(m,node_name='Visual',geom_name=name)
 (OUT/(name+'.glb')).write_bytes(scene.export(file_type='glb'))
 return {'mesh':name,'triangles':len(m.faces),'vertices':len(m.vertices),'bytes':(OUT/(name+'.glb')).stat().st_size,'bounds':m.bounds.tolist()}

stats=[]
def house(kind,wall_color,w=9,d=12,h=3.8):
 p=[];bx(p,[0,.25,0],[w+.3,.5,d+.3],palette['stone']);bx(p,[0,h/2+.45,0],[w,h,d],wall_color)
 e=h+.45;r=e+2.5;ww=w/2+.5;dd=d/2+.45
 v=np.array([[-ww,e,-dd],[ww,e,-dd],[0,r,-dd],[-ww,e,dd],[ww,e,dd],[0,r,dd]],float)
 f=np.array([[0,2,1],[3,4,5],[0,3,5],[0,5,2],[2,5,4],[2,4,1],[0,1,4],[0,4,3]])
 p.append(paint(trimesh.Trimesh(vertices=v,faces=f,process=False),palette['roof']))
 # Triangular gables, eaves, roof ridge and visible tile courses.
 for z in [-d/2,d/2]:
  vv=np.array([[-w/2,e,z],[w/2,e,z],[0,r-.2,z]])
  p.append(paint(trimesh.Trimesh(vertices=vv,faces=[[0,1,2],[2,1,0]],process=False),wall_color))
 for x in [-w/2,w/2]:bx(p,[x,e-.07,0],[.18,.18,d+.55],palette['wood'])
 beam(p,[0,r+.015,-dd],[0,r+.015,dd],.10,'674d3e')
 for side in [-1,1]:
  for k in range(1,9):
   x=side*ww*k/9; y=r-(r-e)*k/9+.025;beam(p,[x,y,-dd],[x,y,dd],.022,'684a3a',5)
 # Facade: inset windows with light jambs; ground-floor doors are closed.
 for side in [-1,1]:
  x=side*(w/2+.012)
  for z in [-d*.28,d*.28]:
   bx(p,[x,2.2,z],[.06,1.3,1.3],palette['glass'])
   for dz in [-.73,.73]:bx(p,[x+side*.04,2.2,z+dz],[.1,1.6,.13],palette['wood'])
   for dy in [-.72,.72]:bx(p,[x+side*.045,2.2+dy,z],[.13,.12,1.55],palette['wood'])
   bx(p,[x+side*.05,2.2,z],[.15,.10,1.4],'aaa693');bx(p,[x+side*.05,2.2,z],[.15,1.4,.07],'aaa693')
 for z in [-d/2-.035,d/2+.035]:
  bx(p,[0,1.65,z],[1.5,2.5,.1],palette['wood']);bx(p,[0,.38,z],[2.0,.16,.5],palette['stone'])
  for x in [-.88,.88]:bx(p,[x,1.65,z],[.14,2.8,.16],wall_color)
  bx(p,[0,3.05,z],[1.9,.18,.15],wall_color)
  for x in [-2.8,2.8]:
   bx(p,[x,2.25,z],[1.35,1.2,.05],palette['glass'])
   bx(p,[x,2.25,z-.02],[.10,1.25,.07],palette['wood'])
 bx(p,[1.9,r-.05,1.5],[.95,2.1,.9],'7c6957');bx(p,[1.9,r+1.04,1.5],[1.15,.14,1.10],'999887')
 stats.append(save(p,kind));return p
for i in range(3):house(f'house_{i}',palette[['plaster','plaster2','plaster3'][i]],w=8.5+i*.65,d=11+i,h=3.6+i*.18)
p=house('barn',palette['wood'],w=12,d=19,h=4.4)
# Add barn-specific bracing and broad closed doors in same one-surface mesh.
for x in [-4.4,-2.2,0,2.2,4.4]:bx(p,[x,2.8,-9.56],[.18,4.5,.20],'796a4e')
for a,b in [([-5.5,.6,-9.65],[5.5,5,-9.65]),([-5.5,5,-9.65],[5.5,.6,-9.65])]:beam(p,a,b,.08,'81704f')
stats=[s for s in stats if s['mesh']!='barn'];stats.append(save(p,'barn'))
p=house('chapel',palette['plaster'],w=8,d=15,h=5)
bx(p,[0,5.7,-10],[4.8,11.4,4.5],palette['stone'])
for sx in [-1,1]:
 bx(p,[sx*2.43,9.0,-10],[.07,2.2,1.25],palette['glass'])
bx(p,[0,9,-12.29],[1.25,2.2,.08],palette['glass'])
vv=np.array([[-2.8,11.4,-12.8],[2.8,11.4,-12.8],[2.8,11.4,-7.2],[-2.8,11.4,-7.2],[0,15,-10]])
p.append(paint(trimesh.Trimesh(vertices=vv,faces=[[0,4,1],[1,4,2],[2,4,3],[3,4,0],[0,1,2],[0,2,3]],process=False),'5b6661'))
beam(p,[0,15,-10],[0,16.2,-10],.045,'444a44');beam(p,[-.42,15.85,-10],[.42,15.85,-10],.045,'444a44')
stats=[s for s in stats if s['mesh']!='chapel'];stats.append(save(p,'chapel'))
# Trees: open lower trunk, irregular solid leaf clusters all above head height.
for v in range(3):
 p=[];beam(p,[0,0,0],[.13,6.2,0],.26,palette['bark'],9)
 for j in range(10):
  ang=j*2.39996+v;rad=1.8+float(rng.random())*1.2;cy=4.7+float(rng.random())*3
  center=[math.cos(ang)*rad,cy,math.sin(ang)*rad]
  beam(p,[0,2.5+j*.16,0],center,.10,palette['bark'])
  m=trimesh.creation.icosphere(subdivisions=1,radius=1);m.vertices*=rng.uniform(.88,1.13,(len(m.vertices),1));m.apply_scale([2.0+v*.12,1.4+float(rng.random())*.8,1.8]);m.apply_translation(center)
  # Mild vertical tone gradient; no billboard opacity or foliage collider.
  c=np.tile(rgba(['4f633a','617240','586637'][v]),(len(m.vertices),1)).astype(float);c[:,:3]+=(m.vertices[:,1:2]-5.5)*5+rng.normal(0,5,(len(c),1));m.visual.vertex_colors=np.uint8(np.clip(c,0,255));p.append(m)
 stats.append(save(p,f'tree_{v}'))
for v in range(3):
 m=trimesh.creation.icosphere(subdivisions=1);m.vertices*=rng.uniform(.82,1.15,(len(m.vertices),1));m.apply_scale([1.4+v*.35,.7+v*.17,1.15]);m.apply_translation([0,.45,0]);stats.append(save([paint(m,['858979','787e72','8c8b7b'][v],3)],f'rock_{v}'))
p=[];cyl(p,[0,.95,0],.95,1.35,'ad9a62',axis='x',sections=18)
for x in [-.63,.63]:cyl(p,[x,.95,0],.96,.026,'9a8655',axis='x',sections=18)
stats.append(save(p,'hay_roll'))
p=[]
for row in range(4):
 for j in range(5):
  x=(j-2)*.82+(row%2)*.16;bx(p,[x,.15+row*.30,0],[.78,.28,.48],['7f8070','727566','909080'][(row+j)%3])
bx(p,[0,1.25,0],[4.45,.16,.58],'929180');stats.append(save(p,'wall_4m'))
# Dressing is strictly cosmetic, separate named meshes for hull and turret.
p=[]
for x in [-.93,.93]:
 bx(p,[x,1.205,1.77],[.43,.19,.85],'655f47')
 for z in [1.48,1.76,2.03]:bx(p,[x,1.306,z],[.46,.025,.048],'343b31')
for i in range(11):bx(p,[-.50+i*.10,1.21,1.68],[.025,.028,.70],'313930')
for side in [-1,1]:
 for z in [-1.6,-1,-.4,.2,.8,1.4]:bx(p,[side*1.09,1.05,z],[.032,.05,.22],'747c58')
 beam(p,[side*1.11,1.10,.6],[side*1.11,1.10,2.1],.023,'79745a')
stats.append(save(p,'tank_hull_dressing'))
p=[];bx(p,[0,.43,1.52],[1.5,.43,.39],'64684c')
for x in [-.67,.67]:bx(p,[x,.66,1.51],[.065,.024,.42],'242f25')
for x in [-.91,.91]:
 for z in [-.85,-.50,-.15,.2]:cyl(p,[x,.36,z],.055,.018,'80846c',axis='x',sections=8)
beam(p,[.83,.53,.62],[.84,2.25,.68],.012,'363e31',5)
bx(p,[-.64,.51,-.08],[.30,.14,.34],'798263');bx(p,[-.64,.59,-.15],[.21,.035,.09],'283c39')
stats.append(save(p,'tank_turret_dressing'))

# Place tree groups and roadside natural elements, exclude fixed deployment area.
placements=buildings.copy(); tree_count=0
for j in range(520):
 x=float(rng.uniform(-700,700));z=float(rng.uniform(-500,750))
 if -100<x<80 and -160<z<290:continue
 if float(dist_roads(np.array(x),np.array(z)))<9.5:continue
 if any(abs(x-b['position'][0])<20 and abs(z-b['position'][2])<22 for b in buildings):continue
 if any(abs(x-cx)<w/2+2 and abs(z-cz)<h/2+2 for cx,cz,w,h,k in fields):continue
 # Forest bands and clumps rather than uniform sprinkling.
 band=math.sin(x/70)+math.cos(z/95)
 if band<-.25 and rng.random()<.8:continue
 placements.append(dict(id=f'tree_{tree_count:03d}',kind=f'tree_{tree_count%3}',position=[x,float(sample(x,z)),z],yaw=float(rng.uniform(0,6.283)),scale=float(rng.uniform(.75,1.22)),collision='trunk'))
 tree_count+=1
# Rocks are outside roads and initial battle slots, real convex obstacles.
for i in range(48):
 x=float(rng.uniform(-560,520));z=float(rng.uniform(-350,620))
 if -100<x<80 and -160<z<290:continue
 if float(dist_roads(np.array(x),np.array(z)))<12:continue
 if any(abs(x-b['position'][0])<18 and abs(z-b['position'][2])<20 for b in buildings):continue
 placements.append(dict(id=f'rock_{i:02d}',kind=f'rock_{i%3}',position=[x,float(sample(x,z))-.12,z],yaw=float(rng.uniform(0,6.283)),scale=float(rng.uniform(.6,1.4)),collision='rock'))
for j in range(20):
 x=float(rng.uniform(310,370));z=float(rng.uniform(30,145));placements.append(dict(id=f'hay_{j:02d}',kind='hay_roll',position=[x,float(sample(x,z)),z],yaw=float(rng.uniform(0,6.283)),scale=1.0,collision='solid_hay'))
# A partial yard boundary with deliberate broad entrance gaps.
for group,(cx,cz,along) in enumerate([(-232,82,'z'),(-231,143,'z'),(-112,210,'x'),(260,243,'z'),(-291,-121,'x')]):
 for j in range(5):
  x=cx+(j-2)*4.35 if along=='x' else cx; z=cz+(j-2)*4.35 if along=='z' else cz
  placements.append(dict(id=f'wall_{group}_{j}',kind='wall_4m',position=[x,float(sample(x,z))-.10,z],yaw=0 if along=='x' else math.pi/2,scale=1.0,collision='solid_wall'))
# Collision descriptors in asset-local space; static assets are explicitly not destructible.
colliders={}
for i in range(3):
 w=8.5+i*.65;d=11+i;h0=3.6+i*.18;e=h0+.45;r=e+2.5;ww=w/2+.5;dd=d/2+.45
 colliders[f'house_{i}']={'shape':'compound','boxes':[{'size':[w+.3,.5,d+.3],'center':[0,.25,0]},{'size':[w,h0,d],'center':[0,h0/2+.45,0]},{'size':[.95,2.1,.9],'center':[1.9,r-.05,1.5]}], 'convex':[[[-ww,e,-dd],[ww,e,-dd],[0,r,-dd],[-ww,e,dd],[ww,e,dd],[0,r,dd]]]}
for kind,w,d,h0 in [('barn',12,19,4.4),('chapel',8,15,5.0)]:
 e=h0+.45;r=e+2.5;ww=w/2+.5;dd=d/2+.45
 colliders[kind]={'shape':'compound','boxes':[{'size':[w+.3,.5,d+.3],'center':[0,.25,0]},{'size':[w,h0,d],'center':[0,h0/2+.45,0]}], 'convex':[[[-ww,e,-dd],[ww,e,-dd],[0,r,-dd],[-ww,e,dd],[ww,e,dd],[0,r,dd]]]}
colliders['chapel']['boxes'].append({'size':[4.8,11.4,4.5],'center':[0,5.7,-10]})
colliders['chapel']['convex'].append([[-2.8,11.4,-12.8],[2.8,11.4,-12.8],[2.8,11.4,-7.2],[-2.8,11.4,-7.2],[0,15,-10]])
for i in range(3):
 colliders[f'tree_{i}']={'shape':'cylinder','radius':.3,'height':5.8,'center':[0,2.9,0]}
 colliders[f'rock_{i}']={'shape':'convex_visual'}
colliders['hay_roll']={'shape':'cylinder','radius':.95,'height':1.35,'center':[0,.95,0],'axis':'x'}
colliders['wall_4m']={'shape':'box','size':[4.45,1.33,.58],'center':[0,.665,0]}
config={'schema':'cedar-valley-v1','seed':20261019,'height_grid':{'n':N,'step_m':4,'origin_xz':[-2500,-2500],'encoding':'little-endian-float32-row-major-zx','file':'height_4m.f32'},'world_extent_m':[5000,5000],'detailed_content_extent_m':[-700,-500,700,750],'roads':roads,'road_nominal_width_m':8.5,'fields':fields,'placements':placements,'colliders':colliders,'asset_statistics':stats,'semantics':{'static_buildings':'opaque solid, not enterable/not destructible','trees':'physical trunk only; crown above head height, no new hiding mechanic','fields':'visual land cover only, no new mud/traction rules','roads':'surface marking on shared smooth heightfield; no separate road-grade or traction solver','no_actors_added':True}}
(OUT/'map.json').write_text(json.dumps(config,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
# Actual triangulated preview of the same sampled map, not an imaginary illustration.
viewstep=6.;ax=np.arange(-720,721,viewstep,dtype=float);az=np.arange(-510,751,viewstep,dtype=float);vx,vz=np.meshgrid(ax,az);vy=sample(vx,vz)
verts=np.stack([vx.ravel(),vy.ravel(),vz.ravel()],axis=1)
w=len(ax);rows=len(az);idx=np.arange((rows-1)*(w-1));iz=idx//(w-1);ix=idx%(w-1);aa=iz*w+ix;faces=np.stack([aa,aa+w,aa+1,aa+1,aa+w,aa+w+1],1).reshape(-1,3)
terrain=trimesh.Trimesh(vertices=verts,faces=faces,process=False)
uv=np.stack([(verts[:,0]+2500)/5000,1-(verts[:,2]+2500)/5000],axis=1)
terrain.visual=trimesh.visual.texture.TextureVisuals(uv=uv, material=trimesh.visual.material.PBRMaterial(baseColorFactor=[255,255,255,255],baseColorTexture=Image.open(OUT/'land_color.png'),metallicFactor=0,roughnessFactor=.94))
scene=trimesh.Scene();scene.add_geometry(terrain,node_name='TerrainPreview_6m',geom_name='TerrainPreview_6m');(OUT/'map_preview.glb').write_bytes(scene.export(file_type='glb'))
checks={'height_min':float(H.min()),'height_max':float(H.max()),'finite_heights':bool(np.isfinite(H).all()),'building_count':len(buildings),'tree_count':tree_count,'placements':len(placements),'asset_count':len(stats),'all_original_assets':True,'engine_executed':False}
(ROOT/'asset_build_receipt.json').write_text(json.dumps(checks,indent=2))
print(json.dumps(checks,indent=2))
