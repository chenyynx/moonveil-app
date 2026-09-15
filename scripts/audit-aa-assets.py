#!/usr/bin/env python3
# AA asset completeness audit — the 8b debt lesson, codified.
# Every aa-* image referenced by AppSymbolAssets.names (incl. AppSymbol's
# aa-CircleHelp fallback) must ship as a real imageset with Contents.json +
# a drawable. Missing entries do NOT fail the compile — they silently degrade
# to blank icons at runtime (功能静默短缺), which is why this gate exists.
import re, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAT = os.path.join(ROOT, "src/ios/Assets.xcassets")
SRC = os.path.join(ROOT, "src/ios/Views/SettingsSkin/AppSymbolAssets.swift")
if not (os.path.isfile(SRC) and os.path.isdir(CAT)):
    print("[gate] aa-assets: files moved? SRC/CAT not found"); sys.exit(1)
s = open(SRC).read()
vals = set(re.findall(r'"(aa-[A-Za-z0-9]+)"', s))
vals.add("aa-CircleHelp")
fail = 0
for v in sorted(vals):
    d = os.path.join(CAT, v + ".imageset")
    if not os.path.isdir(d):
        print(f"VIOLATION: missing imageset {v}"); fail = 1; continue
    files = os.listdir(d)
    if "Contents.json" not in files:
        print(f"VIOLATION: {v}.imageset has no Contents.json"); fail = 1
    if not any(f.endswith((".svg", ".pdf", ".png")) for f in files):
        print(f"VIOLATION: {v}.imageset has no drawable"); fail = 1
print(f"[gate] aa-assets {'OK' if not fail else 'FAILED'} ({len(vals)} referenced)")
sys.exit(fail)
