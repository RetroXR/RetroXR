"""What the imported textures of a restored room cost on the GPU, read from each .ctex header.

Takes the list of textures a run actually loaded from a Godot --verbose log ("Loading resource:
...ctex"), finds each file (in RetroXR/.godot/imported, or inside the mod pack zip that ships it),
and reads its width, height, mipmaps, Image.Format and data format. A VRAM format is counted at its
file size; a PNG/WebP (lossless) one as the RGBA8 it is expanded to on upload. Prints totals by
kind, by owner (base game or mod id) and the largest textures.

    "$godot" --verbose --path RetroXR --resolution 320x240 --position 20,20 \
        res://Tools/perf/restore_perf_probe.tscn -- --file=<copy of a slot> > run.log 2>&1
    python Tools/perf/texture_census.py run.log RetroXR ~/retroxr/mods

Runtime-made textures (book pages, viewports, labels) have no .ctex: restore_perf_probe
--runtime-textures counts those. See docs/dev/performance.md "Restoring a room".
"""
import sys,re,struct,zipfile,os,collections
log,proj,modsdir=sys.argv[1:4]
FMT={0:'L8',1:'LA8',2:'R8',3:'RG8',4:'RGB8',5:'RGBA8',17:'DXT1',18:'DXT3',19:'DXT5',20:'RGTC_R',21:'RGTC_RG',22:'BPTC_RGBA',25:'ETC',30:'ETC2_RGB8',31:'ETC2_RGBA8',35:'ASTC_4x4'}
BPP={'L8':8,'LA8':16,'R8':8,'RG8':16,'RGB8':32,'RGBA8':32}
paths=sorted(set(re.findall(r'Loading resource: (\S+\.ctex)',open(log,encoding='utf-8',errors='replace').read())))
zips={}
def zf(mid):
    if mid not in zips:
        p=os.path.join(modsdir,mid+'.zip')
        zips[mid]=zipfile.ZipFile(p) if os.path.exists(p) else None
    return zips[mid]
# the source png each ctex came from, for the report
rows=[];missing=0
for p in paths:
    rel=p[len('res://'):]
    data=None
    m=re.match(r'mods/([^/]+)/',rel)
    if m:
        z=zf(m.group(1))
        if z:
            try: data=z.read(rel)[:64]; size=z.getinfo(rel).file_size
            except KeyError: pass
    else:
        f=os.path.join(proj,rel)
        if os.path.exists(f): data=open(f,'rb').read(64); size=os.path.getsize(f)
    if data is None: missing+=1; continue
    w,h=struct.unpack('<II',data[8:16]); df=struct.unpack('<I',data[36:40])[0]
    mips=struct.unpack('<I',data[44:48])[0]; fmt=FMT.get(struct.unpack('<I',data[48:52])[0],str(struct.unpack('<I',data[48:52])[0]))
    if df in (1,2):  # PNG/WEBP: expanded to RGBA8 on the GPU
        gpu=w*h*4*(4/3 if mips>1 else 1); kind='LOSSLESS/'+('png' if df==1 else 'webp')
    elif fmt in BPP:
        gpu=w*h*BPP[fmt]/8*(4/3 if mips>1 else 1); kind='UNCOMPRESSED/'+fmt
    else:
        gpu=size-56; kind='vram/'+fmt
    src=re.sub(r'^.*/(_imported|\.godot/imported)/','',rel); src=re.sub(r'-[0-9a-f]{32}\..*$','',src)
    owner=m.group(1) if m else 'base'
    rows.append((gpu,w,h,kind,owner,src))
tot=sum(r[0] for r in rows)
print(f'{len(rows)} textures ({missing} not found), est. GPU {tot/2**20:.0f} MiB')
for key,idx in (('kind',3),('owner',4)):
    c=collections.Counter()
    for r in rows: c[r[idx]]+=r[0]
    print('by',key); [print(f'   {v/2**20:8.1f} MiB  {k}') for k,v in c.most_common(12)]
dims=collections.Counter()
for r in rows: dims[f'{max(r[1],r[2])}']+=r[0]
print('by largest side'); [print(f'   {v/2**20:8.1f} MiB  {k}px') for k,v in sorted(dims.items(),key=lambda x:-x[1])[:6]]
print('top 25');
for r in sorted(rows,reverse=True)[:25]: print(f'   {r[0]/2**20:6.1f} MiB {r[1]}x{r[2]} {r[3]:22} {r[4]:22} {r[5]}')
