#!/usr/bin/env python3
# Case-spelling heuristic: a bare identifier that (1) is not declared anywhere in
# the compiled surface, (2) case-insensitively equals a declared type or top-level
# func that differs in case, and (3) is not a known inherited/foreign member, is
# almost always a "cannot find 'X' in scope" build break of the contentmodifier
# class (e850456-era SessionInteractionDock.swift:11). This is a grep-level
# heuristic, NOT scope resolution: it cannot see local scopes, so it is strictly
# advisory-grade except for the exact case-mirror pattern it targets.
# ALLOWLIST = UIKit/ObjC inherited members invisible to a declaration grep.
import re, os, sys, subprocess
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLOW = {"contentview", "superview", "bounds", "frame", "alpha", "hidden", "tag",
         "subviews", "window", "layer", "gesturerecognizers", "tintColor",
         "backgroundcolor", "isuserinteracting"}  # compared casefolded
ALLOW_CF = {a.lower() for a in ALLOW}

TYPE_DECL = re.compile(r'^\s*(?:(?:@[\w.]+(?:\([^)]*\))?\s*)+)?(?:(?:public|internal|fileprivate|private|final|static|class|actor|nonisolated|indirect|open)\s+)*(?:class|struct|enum|protocol|actor)\s+([A-Za-z_]\w*)', re.M)
FUNC_DECL = re.compile(r'^\s*(?:(?:public|internal|private|fileprivate|static|final|open)\s+)*func\s+([A-Za-z_]\w*)', re.M)

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
    pool, declared_any, srcs = {}, set(), {}
    for f in files:
        try:
            s = open(f, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        srcs[f] = s
        for t in TYPE_DECL.findall(s) + FUNC_DECL.findall(s):
            pool.setdefault(t.lower(), set()).add(t)
    for s in srcs.values():
        declared_any |= set(re.findall(r'\b(?:let|var|func|case|init|class|struct|enum)\s+([A-Za-z_]\w*)', s))
        declared_any |= set(re.findall(r'\b([A-Za-z_]\w*)\s*[:=]', s))
        declared_any |= {x for xs in pool.values() for x in xs}
    hits = 0
    for f, s in srcs.items():
        s2 = re.sub(r'""".*?"""|"(?:[^"\\\n]|\\.)*"|//[^\n]*|/\*.*?\*/', " ", s, flags=re.S)
        for m in re.finditer(r'(?<![.\w])([a-z]\w{3,})(?![\w:=])', s2):
            # '(' NOT excluded: an undeclared call 'foo(' is the same scope error class.
            ident = m.group(1)
            cf = ident.lower()
            if cf in ALLOW_CF or ident in declared_any:
                continue
            cands = sorted(t for t in pool.get(cf, set()) if t != ident)
            if cands:
                line = s2[:m.start()].count("\n") + 1
                print(f"{f}:{line}: case-spelling suspect: '{ident}' used but undeclared; "
                      f"declared near-match: {', '.join(cands)}")
                hits += 1
    print(f"[spelling] files={len(files)} suspects={hits}")
    sys.exit(1 if hits else 0)

if __name__ == "__main__":
    main()
