#!/usr/bin/env python3
"""QA visualizations from the actual baked game heightfield; not Godot screenshots."""
import json,numpy as np,math
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import LightSource
root=Path(__file__).resolve().parents[1];src=root/'assets';h=np.fromfile(src/'height_4m.f32',dtype='<f4').reshape(1251,1251)
d=json.loads((src/'hydrology.json').read_text());m=json.loads((src/'map.json').read_text())
fig,ax=plt.subplots(figsize=(11.7,10),dpi=120)
height=h[::3,::3]
lit=LightSource(315,50).shade(height,cmap=plt.get_cmap('gist_earth'),vert_exag=0.8,blend_mode='soft')
ax.imshow(lit,extent=[-2500,2500,2500,-2500],origin='upper')
river=np.array([[p['x'],p['z']] for p in d['profile']])
ax.plot(river[:,0],river[:,1],color='#0d4e6b',lw=4.5,alpha=.95)
for road in m['roads']:
 q=np.asarray(road['points'])
 ax.plot(q[:,0],q[:,1],lw=2 if 'valley' in road['id'] else 1.3,c='#eee1b5',alpha=.9)
for kind,mark,color in [('house','s','#e0c5a1'),('barn','s','#af7f53'),('tree','.', '#29482f'),('rock','.', '#827969')]:
 pp=[r for r in m['placements'] if r['kind'].startswith(kind)]
 if pp:
  qq=np.asarray([r['position'] for r in pp]);ax.scatter(qq[:,0],qq[:,2],s=11 if kind in ('house','barn') else 4,c=color,marker=mark,linewidths=0,zorder=3)
b=d['bridge'];ford=d['ford'];ax.plot(b['center_x'],b['center_z'],marker='D',c='#f4f0da',markersize=10,zorder=5);ax.text(b['center_x']+70,b['center_z']-120,'BRIDGE / drivable deck',color='white',fontsize=9,weight='bold',bbox={'facecolor':'#202b2c','alpha':.65,'edgecolor':'none'})
p=d['profile'][int((ford['center_z']+2500)/5)];ax.plot(p['x'],ford['center_z'],marker='o',c='#f4d56c',markersize=8,zorder=5);ax.text(p['x']-730,ford['center_z']-95,'FORD / shallow bed',color='white',fontsize=9,weight='bold',bbox={'facecolor':'#202b2c','alpha':.65,'edgecolor':'none'})
ax.plot(-6,-7,marker='^',c='#ffbc56',ms=11);ax.text(10,-80,'Legacy spawn vicinity',color='white',fontsize=9,bbox={'facecolor':'#26312a','alpha':.7,'edgecolor':'none'})
ax.set_xlim(-2500,2500);ax.set_ylim(2500,-2500);ax.set_xlabel('metres east/west (X)');ax.set_ylabel('metres north/south (Z)');ax.set_title('WWO Rivergate B1  |  GAME HEIGHTFIELD + BRIDGE + ROADS',fontsize=13)
ax.grid(alpha=.1);fig.text(.5,.025,'Computed from the exact Godot map data. OFFLINE TOPOGRAPHY PREVIEW — NOT IN-GAME RENDER OR TEST.',ha='center',fontsize=9)
fig.tight_layout(rect=[0,.035,1,.98]);fig.savefig(root/'review/actual_height_and_route_preview.png',dpi=120);plt.close(fig)

# Actual measured cross-section at the two crossings, not an artist's rendering.
fig,axes=plt.subplots(2,1,figsize=(12,6.5),dpi=130)
def sample(x,z):
 xx=np.clip((np.asarray(x)+2500)/4,0,1249.999999);zz=(z+2500)/4;i=np.floor(xx).astype(int);j=int(zz);a=xx-i;t=zz-j
 return (1-t)*((1-a)*h[j,i]+a*h[j,i+1])+t*((1-a)*h[j+1,i]+a*h[j+1,i+1])
for a,zz,title in zip(axes,[b['center_z'],ford['center_z']],['Real elevated bridge deck vs carved channel','Actual shallow ford and graded approaches']):
 p=d['profile'][int((zz+2500)/5)];xc=p['x'];x=np.linspace(xc-200,xc+200,900);y=sample(x,zz)
 a.plot(x-xc,y,'#68543c',lw=2,label='Baked terrain / physical bed')
 a.axhline(p['water_y'],c='#307fa3',lw=1.5,label='Water surface (visual only)')
 if zz==b['center_z']:
  z=b['half_span_m'];a.plot([-z,z],[b['deck_top_y'],b['deck_top_y']],c='#222',lw=5,label='Real bridge collision deck top')
 a.fill_between(x-xc,y,min(y)-6,color='#918663',alpha=.4)
 a.set_xlim(-200,200);a.set_ylabel('Y (m)');a.set_title(title,fontsize=10);a.legend(loc='upper right',fontsize=8)
axes[-1].set_xlabel('X distance from river centre (m)');fig.tight_layout();fig.savefig(root/'review/physical_crossings_preview.png');plt.close(fig)
print('rendered QA previews')
