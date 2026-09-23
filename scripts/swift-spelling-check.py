#!/usr/bin/env python3
# Case-spelling heuristic: a bare identifier that (1) is not declared anywhere in
# the compiled surface, (2) case-insensitively equals a declared type or top-level
# func that differs in case, and (3) is not a known inherited/foreign member, is
# almost always a "cannot find 'X' in scope" build break of the contentmodifier
# class (e850456-era SessionInteractionDock.swift:11). This is a grep-level
# heuristic, NOT scope resolution: it cannot see local scopes, so it is strictly
# advisory-grade except for the exact case-mirror pattern it targets.
# ALLOWLIST = UIKit/ObjC inherited members invisible to a declaration grep.
#
# [SPELL-CACHE 2026-09-24 pp 拍板] Content-hash cache, mirrors the
# swift-parse-check paradigm. Per file, the *parse results* (declarations the file
# contributes + candidate identifiers from its stripped source) are keyed by the
# file's sha256. The verdict pass ALWAYS re-runs against the freshly merged global
# pool, so a cache hit can only skip re-reading/re-regexing unchanged files — it
# can never change a verdict (cross-file effects stay live: a new declaration in
# file A still silences a stale candidate in unchanged file B).
# Invalidation: file content change -> new key; ANY edit to this script -> new
# cache dir (dir name = sha256 of this script's own source). Corrupt/partial cache
# is treated as empty (full rescan). Cache lives outside the repo.
# Env: MOONVEIL_SPELL_CACHE (cache root; default $HOME/.cache/moonveil-spelling).
import re, os, sys, subprocess, json, hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLOW = {"contentview", "superview", "bounds", "frame", "alpha", "hidden", "tag",
         "subviews", "window", "layer", "gesturerecognizers", "tintColor",
         "backgroundcolor", "isuserinteracting"}  # compared casefolded
ALLOW_CF = {a.lower() for a in ALLOW}

TYPE_DECL = re.compile(r'^\s*(?:(?:@[\w.]+(?:\([^)]*\))?\s+)+)?(?:(?:public|internal|fileprivate|private|final|static|class|actor|nonisolated|indirect|open)\s+)*(?:class|struct|enum|protocol|actor)\s+([A-Za-z_]\w*)', re.M)
FUNC_DECL = re.compile(r'^\s*(?:(?:public|internal|private|fileprivate|static|final|open)\s+)*func\s+([A-Za-z_]\w*)', re.M)

CACHE_ROOT = os.environ.get(
    "MOONVEIL_SPELL_CACHE",
    os.path.join(os.path.expanduser("~"), ".cache", "moonveil-spelling"))


def _self_hash():
    """Cache namespace = this script's own source hash; any logic edit moves it."""
    try:
        with open(os.path.abspath(__file__), "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()[:16]
    except OSError:
        return "nocache"


def _load_cache(path):
    try:
        with open(path) as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _parse_source(s):
    """Everything derivable from one file's source alone:
    pool contribution, declared-name contribution, and post-strip candidates."""
    pool = {}
    for t in TYPE_DECL.findall(s) + FUNC_DECL.findall(s):
        pool.setdefault(t.lower(), set()).add(t)
    decl = set(re.findall(r'\b(?:let|var|func|case|init|class|struct|enum)\s+([A-Za-z_]\w*)', s))
    decl |= set(re.findall(r'\b([A-Za-z_]\w*)\s*[:=]', s))
    s2 = re.sub(r'""".*?"""|"(?:[^"\\\n]|\\.)*"|//[^\n]*|/\*.*?\*/', " ", s, flags=re.S)
    cands = []
    for m in re.finditer(r'(?<![.\w])([a-z]\w{3,})(?![\w:=])', s2):
        # '(' NOT excluded: an undeclared call 'foo(' is the same scope error class.
        cands.append([m.group(1), s2[:m.start()].count("\n") + 1])
    return pool, decl, cands


def main():
    if "--files-from" in sys.argv:  # test hook: explicit file list (pool + scan)
        with open(sys.argv[sys.argv.index("--files-from") + 1]) as fh:
            files = [l.strip() for l in fh if l.strip().endswith(".swift")]
        files = [f for f in files if os.path.isfile(f)]
    else:
        r = subprocess.run(["python3", os.path.join(ROOT, "scripts/audit-swift-registration.py"),
                            "--list-compiled"], capture_output=True, text=True, cwd=ROOT)
        if r.returncode != 0:
            print("[spelling] FATAL: cannot get compiled surface", r.stderr); sys.exit(2)
        files = [f for f in r.stdout.split() if f.endswith(".swift") and os.path.isfile(f)]
    self_hash = _self_hash()
    cache_path = os.path.join(CACHE_ROOT, self_hash + ".json") if self_hash != "nocache" else None
    cache = _load_cache(cache_path) if cache_path else {}
    fresh = {}
    dirty = False
    pool, declared_any = {}, set()
    per_file_cands = []
    for f in files:
        try:
            raw = open(f, "rb").read()
        except OSError:
            continue
        h = hashlib.sha256(raw).hexdigest()
        ent = cache.get(f)
        if isinstance(ent, dict) and ent.get("h") == h \
                and isinstance(ent.get("pool"), dict) and isinstance(ent.get("decl"), list) \
                and isinstance(ent.get("cands"), list):
            p = {k: set(v) for k, v in ent["pool"].items()}
            decl = set(ent["decl"])
            cands = [tuple(c) for c in ent["cands"]]
            fresh[f] = ent  # carry over (also prunes files no longer in the list)
        else:
            dirty = True
            p, decl, cands = _parse_source(raw.decode("utf-8", errors="ignore"))
            fresh[f] = {"h": h, "pool": {k: sorted(v) for k, v in p.items()},
                        "decl": sorted(decl), "cands": [list(c) for c in cands]}
        for k, v in p.items():
            pool.setdefault(k, set()).update(v)
        declared_any |= decl
        per_file_cands.append((f, cands))
    declared_any |= {x for xs in pool.values() for x in xs}
    hits = 0
    for f, cands in per_file_cands:
        for ident, line in cands:
            cf = ident.lower()
            if cf in ALLOW_CF or ident in declared_any:
                continue
            near = sorted(t for t in pool.get(cf, set()) if t != ident)
            if near:
                print(f"{f}:{line}: case-spelling suspect: '{ident}' used but undeclared; "
                      f"declared near-match: {', '.join(near)}")
                hits += 1
    # Dump only when something actually changed (a miss, or the file list grew /
    # shrank so fresh != cache). json-encode of this nested 5MB structure is the
    # dominant cost under iSH (measured), and a pure-hit run has nothing to write.
    if cache_path and (dirty or len(fresh) != len(cache)):
        try:
            os.makedirs(CACHE_ROOT, exist_ok=True)
            tmp = cache_path + ".tmp.%d" % os.getpid()
            with open(tmp, "w") as fh:
                json.dump(fresh, fh)
            os.replace(tmp, cache_path)
        except OSError:
            pass
    print(f"[spelling] files={len(files)} suspects={hits}")
    sys.exit(1 if hits else 0)


if __name__ == "__main__":
    main()
