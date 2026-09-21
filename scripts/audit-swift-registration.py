#!/usr/bin/env python3
# Reverse registration audit: every app-surface .swift on disk must be compiled by
# SOME target — either explicitly registered in a Sources phase (or under a group
# the target syncs) or covered by a PBXFileSystemSynchronizedRootGroup.
# audit-project-inputs.py only checks pbxproj -> disk; this closes the disk -> pbxproj
# direction that let V2PreparedSession (e850456) reach CI undetected.
# Exempt: build-time Generated/*.swift (produced by script phases), and files listed
# in a sync group's membershipExceptions (deliberate non-compilation, reported).
import os, sys
import openstep_parser as op
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PBX = os.path.join(ROOT, "src/ios/Minis.xcodeproj/project.pbxproj")
SCAN_ROOTS = [os.path.join(ROOT, "src/ios"), os.path.join(ROOT, "Packages/RemoteKit/Sources")]
SKIP_DIRS = {".git", ".build", "build", "DerivedData", "Minis.xcodeproj"}
if "--pbx" in sys.argv:  # test hook: point at a fabricated pbxproj copy + scan dirs in /tmp
    PBX = sys.argv[sys.argv.index("--pbx") + 1]
    SCAN_ROOTS = [os.path.abspath(p) for p in sys.argv[sys.argv.index("--scan") + 1].split(",")]
LIST_MODE = "--list-compiled" in sys.argv

with open(PBX) as f:
    objs = op.OpenStepDecoder.ParseFromFile(f)["objects"]

parent = {}
for oid, o in objs.items():
    if o.get("isa") in ("PBXGroup",):
        for c in o.get("children", []) or []:
            parent[c] = oid

def group_chain_dir_segments(gid):
    """Filesystem path segments from a group/sync-group up to project root
    (name-only groups contribute no segment; a SOURCE_ROOT group re-anchors)."""
    segs = []
    seen = set()
    while gid in objs and gid not in seen:
        seen.add(gid)
        o = objs[gid]
        if o.get("isa") not in ("PBXGroup", "PBXFileSystemSynchronizedRootGroup"):
            break
        p = o.get("path")
        st = o.get("sourceTree", "<group>")
        if p and st == "<group>":
            segs.insert(0, p)
            gid = parent.get(gid)
        elif p:  # re-anchored group: ancestors irrelevant
            return [p]
        else:
            gid = parent.get(gid)
    return segs

def fs_ref_path(fid):
    """Absolute disk path of a PBXFileReference (same chain resolution as forward audit)."""
    fr = objs[fid]
    st = fr.get("sourceTree", "<group>")
    base = os.path.dirname(os.path.dirname(PBX))  # src/ios
    if st == "SOURCE_ROOT":
        return os.path.normpath(os.path.join(base, fr.get("path", "")))
    if st == "<absolute>":
        return os.path.normpath(fr.get("path", ""))
    segs = []
    g = parent.get(fid)
    seen = set()
    while g in objs and objs[g].get("isa") == "PBXGroup" and g not in seen:
        seen.add(g)
        p = objs[g].get("path")
        gst = objs[g].get("sourceTree", "<group>")
        if p and gst == "<group>":
            segs.insert(0, p); g = parent.get(g)
        elif p:
            return os.path.normpath(os.path.join(base, p, fr.get("path", "")))
        else:
            g = parent.get(g)
    return os.path.normpath(os.path.join(base, *segs, fr.get("path", "")))

registered = {}   # abs path -> target name (explicit Sources phase membership)
for oid, o in objs.items():
    if o.get("isa") != "PBXNativeTarget":
        continue
    for pid in o.get("buildPhases", []) or []:
        ph = objs.get(pid, {})
        if ph.get("isa") != "PBXSourcesBuildPhase":
            continue
        for bid in ph.get("files", []) or []:
            b = objs.get(bid, {})
            fid = b.get("fileRef")
            if fid in objs and objs[fid].get("isa") == "PBXFileReference":
                if str(objs[fid].get("lastKnownFileType", "")).endswith("swift"):
                    registered.setdefault(fs_ref_path(fid), o.get("name"))

# sync groups -> covering targets, and their membership exceptions
sync_dirs = {}    # abs dir -> set(target names)
sync_exempt = {}  # abs path -> set(target names) that deliberately exclude it
for oid, o in objs.items():
    if o.get("isa") != "PBXFileSystemSynchronizedRootGroup":
        continue
    base = os.path.dirname(os.path.dirname(PBX))
    segs = group_chain_dir_segments(oid)
    d = os.path.normpath(os.path.join(base, *segs))
    for tid, t in objs.items():
        if t.get("isa") == "PBXNativeTarget" and oid in (t.get("fileSystemSynchronizedGroups") or []):
            sync_dirs.setdefault(d, set()).add(t.get("name"))
    for xid in o.get("exceptions", []) or []:
        x = objs.get(xid, {})
        for rel in x.get("membershipExceptions", []) or []:
            sync_exempt.setdefault(os.path.normpath(os.path.join(d, rel)), set()).add(
                objs.get(x.get("target"), {}).get("name", x.get("target")))

def under(path, d):
    return path == d or path.startswith(d + os.sep)

# Upstream dead code: shipped by the open-source initial commit d9d4d5b, referenced by
# no target and no caller. Registering it would newly compile 204 lines of example code.
# Deleting it needs pp's call. Exemption is deliberate and must stay narrow.
DEAD_CODE_EXEMPT = [
    ("src/ios/ISHCommandExecutionExample.swift",
     "upstream dead code (d9d4d5b), never compiled, zero references"),
]

orphans, compiled, exempt_gen, exempt_exc, synced_only = [], [], 0, [], 0
exempt_dead = []
for scan in (SCAN_ROOTS or []):
    for dirpath, dirnames, filenames in os.walk(scan):
        dirnames[:] = [x for x in dirnames if x not in SKIP_DIRS and not x.startswith(".")]
        for fn in filenames:
            if not fn.endswith(".swift"):
                continue
            full = os.path.normpath(os.path.join(dirpath, fn))
            if "/Generated/" in full or full.endswith("Generated.swift"):
                exempt_gen += 1; continue
            tgt = registered.get(full)
            cov = sorted({t for d, ts in sync_dirs.items() if under(full, d) for t in ts})
            exc = sorted(sync_exempt.get(full, set()))
            if exc:  # excluded by its covering group's exception set
                exempt_exc.append((full, exc)); continue
            if tgt:
                compiled.append((full, tgt)); continue
            if cov:
                synced_only += 1; compiled.append((full, "sync:" + ",".join(cov))); continue
            rel = full.replace(ROOT + os.sep, "", 1)
            dead = next((why for suffix, why in DEAD_CODE_EXEMPT if rel == suffix), None)
            if dead:
                exempt_dead.append((full, dead)); continue
            orphans.append(full)

for full, why in exempt_exc:
    if not LIST_MODE:
        print(f"EXEMPT [membershipExceptions {'/'.join(why)}] {full}")
for full, why in exempt_dead:
    if not LIST_MODE:
        print(f"EXEMPT [dead-code {why}] {full}")
if LIST_MODE:
    # app-build surface only: MinisTests/MinisUITests never compile in the iOS Build
    # scheme, so downstream gates (swift-parse) must not be red for them.
    for full, t in sorted(compiled):
        if t in ("MinisTests", "MinisUITests") or t.startswith("sync:MinisTests") or t.startswith("sync:MinisUITests"):
            continue
        print(full)
    sys.exit(0)
n_app = sum(1 for _f, t in compiled if not t.startswith("sync:MinisTests") and not t.startswith("sync:MinisUITests"))
print(f"[reverse-audit] registered={len(registered)} compiled-surface={len(compiled)} "
      f"(app-explicit={n_app}) sync-covered={synced_only} exempt-generated={exempt_gen} "
      f"exempt-exceptions={len(exempt_exc)} exempt-dead={len(exempt_dead)} orphans={len(orphans)}")
for full in orphans:
    print(f"NOT-COMPILED: {full}   (no Sources-phase entry, no covering sync group)")
sys.exit(1 if orphans else 0)
