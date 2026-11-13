"""Per eye pass work from Quest Perfetto traces (quest_perfetto.py capture): pass ms, vertices, primitives, bytes.

    python Tools/perf/quest_eye_pass.py a.pftrace b.pftrace  (pip install perfetto)
"""
import sys
from perfetto.trace_processor import TraceProcessor
K = ["Vertices Shaded / Second","Fragments Shaded / Second","Pre-clipped Polygons/Second","Write Total (Bytes/sec)","Read Total (Bytes/sec)","% Time Shading Vertices","% Shaders Busy"]
for path in sys.argv[1:]:
    tp = TraceProcessor(trace=path)
    main = "s.name like '%24 bit depth%MSAA%' and s.name like '%1344x1408%'"
    passes = list(tp.query(f"select ts, dur from gpu_slice s where {main} order by ts"))
    passes = passes[len(passes)//4: len(passes)*3//4]
    tot = {k:0.0 for k in K}; d=0
    for p in passes:
        d += p.dur
        for x in tp.query(f"select t.name nm, avg(c.value) v from counter c join gpu_counter_track t on c.track_id=t.id where c.ts between {p.ts} and {p.ts+p.dur} and t.name in ({','.join(repr(k) for k in K)}) group by nm"):
            tot[x.nm] += (x.v * p.dur/1e9) if '/' in x.nm and '%' not in x.nm else x.v
    n=len(passes)
    print("%-22s pass %.2f ms  verts %.2f M  frags %.2f M  prims %.2f M  write %.1f MB  read %.1f MB  vert%% %.0f  busy%% %.0f" % (
        path.split('.')[0], d/n/1e6, tot[K[0]]/n/1e6, tot[K[1]]/n/1e6, tot[K[2]]/n/1e6, tot[K[3]]/n/1e6, tot[K[4]]/n/1e6, tot[K[5]]/n, tot[K[6]]/n))
    tp.close()
