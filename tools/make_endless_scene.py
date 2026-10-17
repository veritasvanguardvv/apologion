#!/usr/bin/env python3
"""Builds <godot>/Endless.tscn: the player, HUD, menus and Pastor Ramuel are
copied from Greed.tscn (same template as every level); the level itself is
built at runtime by endless_level.gd from data/endless_parts.json."""
import re,sys,os
GD=sys.argv[1] if len(sys.argv)>1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src=open(os.path.join(GD,'Greed.tscn'),encoding='utf-8').read()
# sections: each starts with a line beginning with '['
secs=re.split(r'\n(?=\[(?:gd_scene|ext_resource|sub_resource|node|connection|editable)[ \]])',src)
head=secs[0]; secs=secs[1:]
ext=[s for s in secs if s.startswith('[ext_resource')]
subs=[s for s in secs if s.startswith('[sub_resource')]
nodes=[s for s in secs if s.startswith('[node')]
conns=[s for s in secs if s.startswith('[connection')]
def attr(s,k):
    m=re.search(r'(?<![a-z_])'+k+r'="([^"]*)"',s.split('\n')[0]); return m.group(1) if m else None
KEEP_TOP={'BackgroundColor','CharacterBody2D','CanvasLayer','MenuLayer','PastorRamuel'}
kept=[]
for s in nodes:
    name=attr(s,'name'); parent=attr(s,'parent')
    if parent is None: continue  # root, rebuilt below
    top=name if parent=='.' else parent.split('/')[0]
    if top in KEEP_TOP: kept.append(s)
# player / pastor start (feet on part 0's floor, y 336; as in Unity's Endless.unity)
def setpos(s,pos):
    return re.sub(r'position = Vector2\([^)]*\)',f'position = Vector2({pos[0]}, {pos[1]})',s,count=1)
for i,s in enumerate(kept):
    first=s.split('\n')[0]
    if first.startswith('[node name="CharacterBody2D" type="CharacterBody2D" parent="."'): kept[i]=setpos(s,(-1401.1487,-222.7499))
    if first.startswith('[node name="PastorRamuel" parent="."'): kept[i]=setpos(s,(-1385.1487,332))
    if first.startswith('[node name="ColorRect" type="ColorRect" parent="BackgroundColor"'):
        kept[i]=re.sub(r'color = Color\([^)]*\)','color = Color(0.07, 0.06, 0.09, 1)',s)
# referenced sub/ext resources (sub resources can reference each other)
subid={attr(s,'id'):s for s in subs}
need_sub=set(); need_ext=set()
def scan(text):
    for m in re.findall(r'SubResource\("([^"]+)"\)',text):
        if m not in need_sub:
            need_sub.add(m); scan(subid.get(m,''))
    for m in re.findall(r'ExtResource\("([^"]+)"\)',text): need_ext.add(m)
music='56_g'
for s in kept: scan(s)
need_ext.add(music)
out=['[gd_scene format=3]','']
out+=[e.strip() for e in ext if attr(e,'id') in need_ext]
out.append('[ext_resource type="Script" path="res://endless_level.gd" id="endless_level"]')
out.append('')
out+=[s.rstrip()+'\n' for s in subs if attr(s,'id') in need_sub]
out.append(f'[node name="Endless" type="Node2D"]\nscript = ExtResource("endless_level")\nmusic = ExtResource("{music}")\n')
out+=[s.rstrip()+'\n' for s in kept]
names={attr(s,'name') if attr(s,'parent')=='.' else attr(s,'parent')+'/'+attr(s,'name') for s in kept}
for c in conns:
    f=attr(c,'from'); t=attr(c,'to')
    if (f=='.' or f in names or f.split('/')[0] in KEEP_TOP) and (t=='.' or t in names or t.split('/')[0] in KEEP_TOP): out.append(c.rstrip()+'\n')
open(os.path.join(GD,'Endless.tscn'),'w',encoding='utf-8').write('\n'.join(out))
print('nodes',len(kept),'subs',len(need_sub),'ext',len(need_ext))
