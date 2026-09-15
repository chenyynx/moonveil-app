#!/usr/bin/env python3
# Full-project input audit: for every file in every Sources phase, resolve the
# group chain the way Xcode does (each group path relative to parent; project
# dir = src/ios) and check existence on disk. Catches cumulative-path bugs.
import os, sys
import openstep_parser as op
PBX = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src/ios/Minis.xcodeproj/project.pbxproj")
PROJ_DIR = os.path.dirname(PBX)  # src/ios/Minis.xcodeproj -> project dir is src/ios
with open(PBX) as f:
    objs = op.OpenStepDecoder.ParseFromFile(f)["objects"]

parent = {}
for oid, o in objs.items():
    if o.get("isa") == "PBXGroup":
        for c in o.get("children", []) or []:
            parent[c] = oid

def resolve_group_path(gid):
    parts = []
    while gid in objs and objs[gid].get("isa") == "PBXGroup":
        p = objs[gid].get("path")
        if p is None:
            p = objs[gid].get("name")
            if p is None:
                pass
        elif p != "":
            parts.insert(0, p)
        gid = parent.get(gid)
    return os.path.normpath(os.path.join(PROJ_DIR, "..", *parts)) if False else parts

def chain_segments(fid):
    """Return (source_tree, [group paths], file path). A group with non-<group>
    sourceTree re-anchors the chain (SOURCE_ROOT = relative to project dir)."""
    fr = objs[fid]
    st = fr.get("sourceTree", "<group>")
    if st == "<group>":
        chain = []
        g = parent.get(fid)
        while g in objs and objs[g].get("isa") == "PBXGroup":
            p = objs[g].get("path")  # 'name'-only groups are logical: no filesystem segment
            gst = objs[g].get("sourceTree", "<group>")
            if p and gst == "<group>":
                chain.insert(0, p)
                g = parent.get(g)
            elif p:  # SOURCE_ROOT etc.: this group re-anchors; ancestors irrelevant
                return st, [p], fr.get("path", "")
            else:
                g = parent.get(g)
        return st, chain, fr.get("path", "")
    return st, [], fr.get("path", "")

def full_path(fid):
    base = os.path.dirname(PROJ_DIR)  # src/ios/Minis.xcodeproj -> src/ios
    st, chain, fpath = chain_segments(fid)
    if st == "SOURCE_ROOT":
        rel = os.path.join(base, fpath)
    elif st == "<absolute>":
        rel = fpath
    else:  # <group>
        rel = os.path.join(base, *chain, fpath)
    return os.path.normpath(rel), "/".join(chain)

missing = 0
checked = 0
gen_ok = 0
for oid, o in objs.items():
    if o.get("isa") != "PBXNativeTarget":
        continue
    tgt = o.get("name")
    for pid in o.get("buildPhases", []) or []:
        ph = objs.get(pid, {})
        if ph.get("isa") != "PBXSourcesBuildPhase":
            continue
        for bid in ph.get("files", []) or []:
            b = objs.get(bid, {})
            fid = b.get("fileRef")
            if not fid or fid not in objs:
                continue
            fo = objs[fid]
            if fo.get("isa") not in ("PBXFileReference",):
                continue
            if not str(fo.get("lastKnownFileType", "")).endswith("swift"):
                continue
            full, chain = full_path(fid)
            checked += 1
            if "/Generated/" in full or full.endswith("Generated.swift"):
                gen_ok += 1  # produced by pre-build script phase; absent in clean checkout
                continue
            if not os.path.isfile(full):
                missing += 1
                print(f"MISSING [{tgt}] {full}   (chain: {chain})")
print(f"[audit] checked={checked} missing={missing} generated-ok={gen_ok}")
sys.exit(1 if missing else 0)
