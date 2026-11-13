"""Capture and read a Perfetto trace of RetroXR on a Quest.

    python Tools/perf/quest_perfetto.py capture --seconds 20 --out room.pftrace
    python Tools/perf/quest_perfetto.py analyze room.pftrace [--from 5 --to 20]

`capture` runs the headset's own `perfetto` with the config below (scheduler,
CPU and GPU frequency, the Adreno counters and render stages Meta exposes, and
the `godot` / `godot_scripting` track events an engine built with
`profiler=perfetto` emits through the system backend), keeps logcat's VrApi
line beside it, and pulls the trace. `analyze` answers "CPU or GPU bound, and
on which thread / zone" from it with trace_processor (`pip install perfetto`).

An engine built without the profiler still gives thread states, frequencies,
GPU counters and the VrApi line: only the Godot zone tables come back empty.
"""
import argparse, os, re, subprocess, sys, time

PKG = "com.xenu.retroxr"
DEVICE_TRACE = "/data/misc/perfetto-traces/retroxr.pftrace"

CONFIG = """
buffers {{ size_kb: {buf_kb} fill_policy: DISCARD }}
buffers {{ size_kb: 8192 fill_policy: RING_BUFFER }}
data_sources {{ config {{ name: "linux.ftrace" target_buffer: 0 ftrace_config {{
    ftrace_events: "sched/sched_switch"
    ftrace_events: "sched/sched_waking"
    ftrace_events: "power/cpu_frequency"
    ftrace_events: "power/cpu_idle"
    ftrace_events: "power/gpu_frequency"
    ftrace_events: "task/task_newtask"
    ftrace_events: "task/task_rename"
    atrace_categories: "gfx"
    atrace_categories: "view"
    atrace_apps: "{pkg}"
    compact_sched {{ enabled: true }}
}} }} }}
data_sources {{ config {{ name: "linux.process_stats" target_buffer: 1
    process_stats_config {{ scan_all_processes_on_start: true proc_stats_poll_ms: 1000 }} }} }}
data_sources {{ config {{ name: "linux.sys_stats" target_buffer: 1
    sys_stats_config {{ stat_period_ms: 500 stat_counters: STAT_CPU_TIMES }} }} }}
data_sources {{ config {{ name: "track_event" target_buffer: 0
    track_event_config {{ {categories} }} }} }}
data_sources {{ config {{ name: "gpu.counters.oculus" target_buffer: 0
    gpu_counter_config {{ counter_period_ns: 1000000 {counter_ids} }} }} }}
data_sources {{ config {{ name: "gpu.renderstages.oculus" target_buffer: 0 }} }}
duration_ms: {ms}
# Interned names are sent once per sequence; a lost first packet (a wrapped ring) made every
# later Godot event unreadable (3.5 M "packet_skipped_seq_needs_incremental_state_invalid").
incremental_state_config {{ clear_period_ms: 500 }}
"""


def adb(*args, check=True, **kw):
    return subprocess.run(["adb", *args], check=check, text=True, capture_output=True, **kw)


def capture(a):
    adb("shell", "setprop", "persist.traced.enable", "1", check=False)
    # The Quest's producer (gpu.counters.oculus) lists no counter ids: it sends its own set.
    cats = " ".join(f'enabled_categories: "{c}"' for c in a.categories.split(","))
    cfg = CONFIG.format(pkg=PKG, ms=int(a.seconds * 1000), buf_kb=a.buffer_mb * 1024, categories=cats, counter_ids="")
    print(f"[trace] {a.seconds:.0f} s, categories {a.categories}, {a.buffer_mb} MiB (DISCARD: a full buffer ends the record early)")
    adb("logcat", "-c", check=False)
    log = open(os.path.splitext(a.out)[0] + ".logcat.txt", "w", encoding="utf-8")
    lc = subprocess.Popen(["adb", "logcat", "-v", "threadtime", "-s", "VrApi:*", "godot:*"], stdout=log, stderr=subprocess.STDOUT)
    try:
        r = subprocess.run(["adb", "shell", "perfetto", "--txt", "-c", "-", "-o", DEVICE_TRACE],
                           input=cfg, text=True, capture_output=True)
        print(r.stdout[-2000:], r.stderr[-2000:])
    finally:
        lc.terminate()
        log.close()
    adb("pull", DEVICE_TRACE, a.out)
    print(f"[trace] wrote {a.out} ({os.path.getsize(a.out)} bytes)")


def analyze(a):
    from perfetto.trace_processor import TraceProcessor
    tp = TraceProcessor(trace=a.trace)
    q = lambda s: list(tp.query(s))
    # trace_start() can be hours early (a stale process-stats timestamp): bound by the scheduler.
    t0 = q("select min(ts) as s, max(ts) as e from sched")[0]
    lo = t0.s + int(a.frm * 1e9)
    hi = t0.e if a.to is None else t0.s + int(a.to * 1e9)
    span = (hi - lo) / 1e9
    print(f"window {a.frm:.1f}-{(hi - t0.s) / 1e9:.1f} s ({span:.1f} s)")

    upid = q(f"select upid from process where name like '{PKG}%' order by upid desc limit 1")
    if not upid:
        print("app process not in the trace"); return
    upid = upid[0].upid

    print("\n== app threads: CPU time (running), share of wall ==")
    for r in q(f"""
        select t.name as name, t.tid as tid, sum(min(s.ts + s.dur, {hi}) - max(s.ts, {lo})) as run
        from sched s join thread t using(utid)
        where t.upid = {upid} and s.ts < {hi} and s.ts + s.dur > {lo}
        group by utid order by run desc limit 20"""):
        print(f"  {r.name or '?':24s} {r.tid:6d}  {r.run / 1e9 / span * 100:5.1f}%")

    print("\n== app threads: state breakdown (top 6 threads) ==")
    for r in q(f"""
        with top as (select utid from sched join thread using(utid) where upid = {upid}
                     and ts between {lo} and {hi} group by utid order by sum(dur) desc limit 6)
        select t.name as name, ts.state as state, sum(ts.dur) as d from thread_state ts
        join thread t using(utid) where utid in (select utid from top) and ts.ts between {lo} and {hi}
        group by utid, state order by t.name, d desc"""):
        print(f"  {r.name or '?':24s} {r.state:4s} {r.d / 1e9 / span * 100:5.1f}%")

    print("\n== CPU frequency (mean MHz per cpu) ==")
    for r in q(f"""select cast(cct.cpu as int) as cpu, avg(c.value)/1000 as mhz from counter c
        join cpu_counter_track cct on c.track_id = cct.id where cct.name = 'cpufreq'
        and c.ts between {lo} and {hi} group by cct.cpu order by cct.cpu"""):
        print(f"  cpu{r.cpu}: {r.mhz:.0f}")

    print("\n== GPU frequency / counters (mean) ==")
    for r in q(f"""select t.name as name, avg(c.value) as v, max(c.value) as mx, count(*) as n from counter c
        join counter_track t on c.track_id = t.id
        where (t.name like '%gpu%' or t.name like '%GPU%' or t.type like '%gpu%')
        and c.ts between {lo} and {hi} group by t.name order by t.name limit 60"""):
        print(f"  {r.name:48s} mean {r.v:12.2f}  max {r.mx:12.2f}  n={r.n}")

    print("\n== GPU render stages (per second of wall) ==")
    for r in q(f"""select name, count(*) as n, sum(dur) as d from gpu_slice
        where ts between {lo} and {hi} group by name order by d desc limit 15"""):
        print(f"  {r.name or '?':40s} {r.n / span:7.1f}/s  {r.d / 1e6 / span:7.2f} ms/s")

    print("\n== Godot frame time counter ==")
    for r in q(f"""select t.name as name, avg(c.value) as v, max(c.value) as mx, count(*) as n
        from counter c join counter_track t on c.track_id = t.id
        where t.name like 'Frame time%' and c.ts between {lo} and {hi} group by t.name"""):
        print(f"  {r.name}: mean {r.v:.2f} max {r.mx:.2f} n={r.n}")

    print("\n== Godot zones: self time per frame, by thread (top 40) ==")
    frames = q(f"""select count(*) as n from slice where name = 'Main::iteration' and ts between {lo} and {hi}""")
    nfr = frames[0].n or 1
    print(f"  {nfr} Main::iteration slices -> {span / nfr * 1000:.2f} ms per frame")
    for r in q(f"""
        select coalesce(t.name, '?') as th, s.name as name, count(*) as n,
               sum(s.dur) as total,
               sum(s.dur - coalesce((select sum(c.dur) from slice c where c.parent_id = s.id), 0)) as self
        from slice s left join thread_track tt on s.track_id = tt.id left join thread t using(utid)
        where s.ts between {lo} and {hi} and (s.category like 'godot%' or s.category is null and t.upid = {upid})
        group by th, s.name order by self desc limit 40"""):
        print(f"  {r.th[:16]:16s} {r.self / 1e6 / nfr:7.3f} self {r.total / 1e6 / nfr:7.3f} incl  x{r.n / nfr:6.1f}  {r.name}")

    lc = os.path.splitext(a.trace)[0] + ".logcat.txt"
    if os.path.exists(lc):
        print("\n== VrApi (last 8) ==")
        lines = [l.rstrip() for l in open(lc, encoding="utf-8", errors="replace") if "FPS=" in l]
        for l in lines[-8:]:
            print("  " + l[l.find("FPS="):][:220])


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("capture"); c.add_argument("--seconds", type=float, default=20); c.add_argument("--out", required=True)
    c.add_argument("--categories", default="godot", help="godot = engine zones; add godot_scripting for every GDScript call (~270k events/s in the Starlight Arcade: keep it short)")
    c.add_argument("--buffer-mb", type=int, default=384)
    n = sub.add_parser("analyze"); n.add_argument("trace"); n.add_argument("--from", dest="frm", type=float, default=0.0)
    n.add_argument("--to", type=float, default=None)
    a = ap.parse_args()
    (capture if a.cmd == "capture" else analyze)(a)


if __name__ == "__main__":
    sys.exit(main())
