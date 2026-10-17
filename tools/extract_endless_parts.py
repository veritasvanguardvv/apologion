#!/usr/bin/env python3
"""Extract Unity's EndlessPart0..5 prefabs (Greed Endless mode) into
<godot>/data/endless_parts.json for endless_level.gd, and copy the textures
they use into <godot>/Endless/.
Godot px = Unity units * 400, Y flipped (same as convert_unity_to_godot.py)."""
import sys,os,json,shutil
sys.path.insert(0,os.environ.get('GREED_UNITY','/workspace/greed-unity'))   # uflat.py / usprite.py of the Unity converter
import uflat,usprite
GD=sys.argv[1] if len(sys.argv)>1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S=400.0
uflat.build_guid_map()
def gx(x): return round(x*S,2)
def gy(y): return round(-y*S,2)
TEX={}
def tex(path):
    if path not in TEX:
        name=os.path.basename(path)
        dst=os.path.join(GD,'Endless',name)
        greed=os.path.join(GD,'Greed',name)
        if os.path.exists(greed): TEX[path]='res://Greed/'+name
        else:
            os.makedirs(os.path.dirname(dst),exist_ok=True)
            shutil.copy(os.path.join(uflat.ROOT,path),dst); TEX[path]='res://Endless/'+name
    return TEX[path]
def region(sp):
    x,y,w,h=sp['rect']; W,H=sp['texsize']; return [x,H-y-h,w,h]
def comps(n,t): return [d for tt,d,k in n.comps if tt==t]
def script(n):
    for t,d,k in n.comps:
        if t=='MonoBehaviour':
            p=uflat.GUID.get((d.get('m_Script') or {}).get('guid'),'')
            yield os.path.basename(p),d
parts=[]
for i in range(6):
    objs=uflat.flatten(f'Assets/Prefabs/Game/EndlessPart{i}.prefab')
    nodes,roots=uflat.build_tree(objs)
    part={'name':f'EndlessPart{i}','tiles':[],'solid':[],'pits':[],'traps':[],'spawns':[],'decor':[]}
    for n in nodes.values():
        sc=dict(script(n))
        if 'EndlessPart.cs' in sc:
            d=sc['EndlessPart.cs']
            mt=d.get('minMaxTraps') or {'x':0,'y':2}; me=d.get('minMaxEnemies') or {'x':0,'y':2}
            part['min_max_traps']=[int(mt['x']),int(mt['y'])]; part['min_max_enemies']=[int(me['x']),int(me['y'])]
        if n.name.startswith('EnemySpawn'):
            part['spawns'].append([gx(n.wpos[0]),gy(n.wpos[1])])
        for d in comps(n,'Tilemap'):
            cell=0.14
            for g in comps(n,'Grid'): cell=float(g['m_CellSize']['x'])
            c=cell*n.wscale[0]*S   # px per cell (56)
            sprites=d['m_TileSpriteArray']
            cells=set()
            for t in d['m_Tiles']:
                pos=t['first']; v=t['second']
                sp=usprite.resolve(sprites[v['m_TileSpriteIndex']]['m_Data'])
                if not sp or 'missing' in sp or sp.get('builtin'): continue
                cx,cy=int(pos['x']),int(pos['y'])
                x=gx(n.wpos[0])+cx*c; y=gy(n.wpos[1])-(cy+1)*c   # top-left of the cell
                part['tiles'].append({'pos':[round(x,2),round(y,2)],'size':round(c,3),'tex':tex(sp['tex']),'region':region(sp)})
                cells.add((cx,cy))
            part['cell']=round(c,3)
            if comps(n,'TilemapCollider2D'):
                # merge each row's runs into one box (fewer shapes)
                for cy in sorted({y for _,y in cells}):
                    xs=sorted(x for x,y in cells if y==cy); start=prev=None
                    for x in xs+[None]:
                        if start is None: start=prev=x; continue
                        if x is not None and x==prev+1: prev=x; continue
                        part['solid'].append([round(gx(n.wpos[0])+start*c,2),round(gy(n.wpos[1])-(cy+1)*c,2),round((prev-start+1)*c,2),round(c,2)])
                        start=prev=x
        if 'DamageArea.cs' in sc:
            dmg=int(sc['DamageArea.cs'].get('Damage',sc['DamageArea.cs'].get('damage',10)) or 10)
            box=(comps(n,'BoxCollider2D') or [{}])[0]
            bs=box.get('m_Size',{'x':1,'y':1}); bo=box.get('m_Offset',{'x':0,'y':0})
            w=abs(float(bs['x'])*n.wscale[0])*S; h=abs(float(bs['y'])*n.wscale[1])*S
            cx=gx(n.wpos[0]+float(bo['x'])*n.wscale[0]); cy=gy(n.wpos[1]+float(bo['y'])*n.wscale[1])
            rect=[round(cx-w/2,2),round(cy-h/2,2),round(w,2),round(h,2)]
            if dmg>=1000:
                part['pits'].append(rect); continue
            sr=(comps(n,'SpriteRenderer') or [None])[0]
            entry={'name':n.name,'damage':dmg,'rect':rect}
            if sr:
                sp=usprite.resolve(sr.get('m_Sprite'))
                if sp and 'missing' not in sp and not sp.get('builtin'):
                    k=S/sp['ppu']
                    entry['sprite']={'tex':tex(sp['tex']),'region':region(sp),'pos':[gx(n.wpos[0]),gy(n.wpos[1])],
                        'scale':[round(n.wscale[0]*k*(-1 if sr.get('m_FlipX') else 1),4),round(n.wscale[1]*k,4)],
                        'offset':[-sp['pivot'][0]*sp['rect'][2],-(1-sp['pivot'][1])*sp['rect'][3]],'rot':round(-n.wrot,3)}
            part['traps'].append(entry)
        elif n.name=='Square' and comps(n,'SpriteRenderer'):
            sr=comps(n,'SpriteRenderer')[0]; sp=usprite.resolve(sr.get('m_Sprite'))
            if sp and 'missing' not in sp and not sp.get('builtin'):
                k=S/sp['ppu']
                part['decor'].append({'tex':tex(sp['tex']),'region':region(sp),'pos':[gx(n.wpos[0]),gy(n.wpos[1])],'scale':[round(n.wscale[0]*k,4),round(n.wscale[1]*k,4)],
                    'offset':[-sp['pivot'][0]*sp['rect'][2],-(1-sp['pivot'][1])*sp['rect'][3]]})
    parts.append(part)
out={'source':'Unity Assets/Prefabs/Game/EndlessPart0-5.prefab (extract_endless_parts.py)','part_width':gx(3.36),'parts':parts}
os.makedirs(os.path.join(GD,'data'),exist_ok=True)
json.dump(out,open(os.path.join(GD,'data','endless_parts.json'),'w'),indent=1)
for p in parts:
    xs=[t['pos'][0] for t in p['tiles']]; ys=[t['pos'][1] for t in p['tiles']]
    print(p['name'],'tiles',len(p['tiles']),'x',min(xs),max(xs),'y',min(ys),max(ys),'solid',len(p['solid']),'traps',len(p['traps']),'spawns',p['spawns'],'pits',p['pits'])
print(TEX)
