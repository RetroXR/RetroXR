#!/usr/bin/env python3
"""Merge a newer libretro-super dist/info into RetroXR/libretro-core-info.

The mirror is NOT a copy of upstream any more: RetroXR's own lines live in it
(`secondary_systemids` in some 70 files, ES-DE systemids, firmware and extension
fixes for its own core builds), and upstream has none of them. A `cp` resync
throws all of that away, and the Game Gear, Sega CD, Satellaview... tiles with it.
So a refresh is a three-way merge, file by file:

    base   = libretro-super dist/info at the commit last merged (README.md names it)
    ours   = RetroXR/libretro-core-info as it is now
    theirs = libretro-super dist/info at the commit being merged

Both upstream sides are renamed to RetroXR's systemids first (the same table as
Tools/rename_systemids.py), so an id upstream never changed is not a difference.
`git merge-file` does each file; a file it cannot settle is written WITH conflict
markers and listed, and the exit status is non-zero until they are resolved.

    git clone --filter=blob:none --sparse https://github.com/libretro/libretro-super.git ../libretro-super
    git -C ../libretro-super sparse-checkout set dist/info
    git -C ../libretro-super fetch origin <base commit>      # if the clone is shallow
    python Tools/merge_core_info.py --repo ../libretro-super --base <base commit>            # report only
    python Tools/merge_core_info.py --repo ../libretro-super --base <base commit> --write    # do it

`--skip NAME` leaves a core's file alone (another change owns it). A file upstream
deleted is deleted here only if RetroXR never changed it; a file upstream renamed
(found by content) carries RetroXR's lines to the new name. Then: record the merged
commit in RetroXR/libretro-core-info/README.md, give any new systemid that ES-DE
names differently a SystemIds.LEGACY entry (re-run with --write so it is applied),
and run systems_data_tests.
"""
import argparse
import difflib
import io
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rename_systemids  # noqa: E402  (beside this file; -I drops the script dir)

ROOT = Path(__file__).resolve().parent.parent
OURS = ROOT / "RetroXR/libretro-core-info"
OVERLAY = ROOT / "RetroXR/libretro-core-info-retroxr"
RENAME_RATIO = 0.85  # how alike a deleted and an added file must be to count as a rename


def extract(repo: Path, rev: str, dest: Path) -> None:
    """dist/info at `rev`, as plain .info files in `dest`."""
    tar = subprocess.run(["git", "-C", str(repo), "archive", rev, "dist/info"],
                         capture_output=True, check=False)
    if tar.returncode != 0:
        sys.exit(f"git archive {rev} failed in {repo}: {tar.stderr.decode(errors='replace').strip()}")
    with tarfile.open(fileobj=io.BytesIO(tar.stdout)) as t:
        for m in t.getmembers():
            if m.isfile() and m.name.endswith(".info"):
                (dest / Path(m.name).name).write_bytes(t.extractfile(m).read())


def normalise(d: Path, legacy: dict[str, str]) -> None:
    """LF line ends (the mirror's), then RetroXR's systemids."""
    for p in d.glob("*.info"):
        p.write_bytes(p.read_bytes().replace(b"\r\n", b"\n"))
        rename_systemids.process(p, legacy, write=True)


def files(d: Path) -> dict[str, bytes]:
    return {p.stem: p.read_bytes() for p in d.glob("*.info")}


def merge3(ours: bytes, base: bytes, theirs: bytes, scratch: Path) -> tuple[bytes, int]:
    paths = []
    for tag, data in (("ours", ours), ("base", base), ("theirs", theirs)):
        p = scratch / f"{tag}.info"
        p.write_bytes(data)
        paths.append(str(p))
    r = subprocess.run(["git", "merge-file", "-p", "-L", "RetroXR", "-L", "base", "-L", "upstream",
                        *paths], capture_output=True, check=False)
    if r.returncode < 0 or r.returncode > 127:
        sys.exit(f"git merge-file failed: {r.stderr.decode(errors='replace').strip()}")
    return r.stdout, r.returncode


def systemids(data: bytes) -> set[str]:
    out = set()
    for line in data.decode("utf-8", errors="replace").splitlines():
        m = rename_systemids.LINE.match(line)
        if not m:
            continue
        if m.group(2) == "systemid":
            out.add(m.group(4))
        else:
            out |= {part.partition(":")[0].strip() for part in m.group(4).split("|") if part}
    out.discard("")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", type=Path, required=True, help="a libretro-super checkout")
    ap.add_argument("--base", required=True, help="the commit last merged into the mirror")
    ap.add_argument("--head", default="HEAD", help="the commit to merge (default HEAD)")
    ap.add_argument("--skip", action="append", default=[], metavar="NAME",
                    help="leave NAME_libretro.info alone (repeatable; the _libretro suffix is optional)")
    ap.add_argument("--write", action="store_true", help="write the result (default: report only)")
    args = ap.parse_args()

    skip = {s if s.endswith("_libretro") else s + "_libretro" for s in args.skip}
    legacy = rename_systemids.load_legacy()
    with tempfile.TemporaryDirectory() as tmp:
        tmp_p = Path(tmp)
        base_d, head_d, scratch = tmp_p / "base", tmp_p / "head", tmp_p / "scratch"
        for d in (base_d, head_d, scratch):
            d.mkdir()
        extract(args.repo, args.base, base_d)
        extract(args.repo, args.head, head_d)
        normalise(base_d, legacy)
        normalise(head_d, legacy)
        base, theirs, ours = files(base_d), files(head_d), files(OURS)
        overlay = files(OVERLAY) if OVERLAY.is_dir() else {}

        added = sorted(set(theirs) - set(base) - set(ours))
        gone = sorted((set(base) - set(theirs)) & set(ours))
        renames = {}
        for old in gone:
            best, ratio = None, 0.0
            for new in added:
                r = difflib.SequenceMatcher(None, base[old], theirs[new]).ratio()
                if r > ratio:
                    best, ratio = new, r
            if best and ratio >= RENAME_RATIO:
                renames[old] = best
        added = [n for n in added if n not in renames.values()]

        writes: dict[str, bytes] = {}
        deletes: list[str] = []
        report: dict[str, list[str]] = {k: [] for k in (
            "merged", "conflict", "added", "renamed", "deleted", "kept (deleted upstream, changed here)",
            "kept (both added, differ)", "kept (deleted here)", "skipped")}

        for name in sorted(set(base) | set(theirs) | set(ours)):
            if name in skip:
                if name in theirs and theirs.get(name) != ours.get(name):
                    report["skipped"].append(name)
                continue
            b, t, o = base.get(name), theirs.get(name), ours.get(name)
            if name in renames:
                new = renames[name]
                merged, n = merge3(o, b, theirs[new], scratch)
                writes[new] = merged
                deletes.append(name)
                report["renamed"].append(f"{name} -> {new}" + (f"  ({n} CONFLICT(S))" if n else ""))
                if n:
                    report["conflict"].append(new)
                continue
            if name in renames.values():
                continue
            if o is None:
                if t is not None and b is None:
                    writes[name] = t
                    report["added"].append(name + ("  (also in the overlay, which wins)" if name in overlay else ""))
                elif t is not None:
                    report["kept (deleted here)"].append(name)
                continue
            if t is None:
                if b is None:
                    continue  # RetroXR's own file
                if o == b:
                    deletes.append(name)
                    report["deleted"].append(name)
                else:
                    report["kept (deleted upstream, changed here)"].append(name)
                continue
            if b is None:
                if o != t:
                    report["kept (both added, differ)"].append(name)
                continue
            if t == b:
                continue  # upstream did not touch it
            merged, n = merge3(o, b, t, scratch)
            if merged == o:
                continue
            writes[name] = merged
            report["conflict" if n else "merged"].append(name)

        print(f"base {args.base}  head {args.head}  ({len(base)} -> {len(theirs)} upstream files, {len(ours)} here)")
        for key, names in report.items():
            if names:
                print(f"\n{key} ({len(names)}):")
                for n in names:
                    print("  " + n)

        known = set().union(*(systemids(v) for v in ours.values()), *(systemids(v) for v in overlay.values()))
        fresh = {}
        for name, data in writes.items():
            for sid in systemids(data) - known:
                fresh.setdefault(sid, []).append(name)
        if fresh:
            print("\nsystemids new to RetroXR (give one a SystemIds.LEGACY entry if ES-DE's folder differs):")
            for sid in sorted(fresh):
                print(f"  {sid:24} {', '.join(sorted(fresh[sid]))}")

        if args.write:
            for name, data in writes.items():
                (OURS / f"{name}.info").write_bytes(data)
            for name in deletes:
                (OURS / f"{name}.info").unlink()
            print(f"\nwrote {len(writes)} file(s), deleted {len(deletes)}")
        else:
            print(f"\nreport only: would write {len(writes)} file(s) and delete {len(deletes)} (--write)")
        return 1 if report["conflict"] else 0


if __name__ == "__main__":
    sys.exit(main())
