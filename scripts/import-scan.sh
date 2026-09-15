#!/usr/bin/env bash
# 门1 (B-plan, single-module): App must not touch RemoteKit internals.
# RemoteKit must not import App. Fails (exit 1) on any forbidden edge.
# 2026-09-15 B-FIX: RemoteKit sources now compile directly into the app target
# (upstream form / claudio precedent) — SPM package integration is gone, so
# `import RemoteKit` is illegal EVERYWHERE. Enforcement = word-list gate against
# the generated registry (scripts/rk-symbol-registry.txt), with the fork-point
# seam shell dirs as the only sanctioned consumers. Teeth proven by
# counter-evidence test (see B8-FIX5 receipt): inject a registry symbol into a
# non-seam app file -> must FAIL.
echo "[gate] single-module isolation scan"
viol=0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REG="$ROOT/scripts/rk-symbol-registry.txt"
[ -f "$REG" ] || { echo "VIOLATION: registry missing (run scripts/gen_rk_registry.py)"; viol=1; }

# 1) no module import of the merged package anywhere in the app
if grep -rEn "import RemoteKit" --include=*.swift "$ROOT/src" 2>/dev/null | grep -q .; then
  echo "VIOLATION: \`import RemoteKit\` is dead in single-module mode"; viol=1
fi
# 2) `import AAV2` stays banned everywhere (frozen internals never imported directly)
if grep -rEn "import AAV2" --include=*.swift "$ROOT/src" 2>/dev/null | grep -q .; then
  echo "VIOLATION: App source imports AAV2 internals (frozen zone)"; viol=1
fi
# 3) word-list: app files outside seams may not reference registry symbols
SEAM_DIRS="$ROOT/src/ios/Views/ModeTabs|$ROOT/src/ios/Views/AuthAA|$ROOT/Packages"
banned_words=$(sed -e '/^#/d' -e '/^$/d' "$REG" 2>/dev/null | tr '\n' ' ')
for w in $banned_words; do
  hits=$(grep -rnE "(^|[^.[:alnum:]_])${w}\b" --include=*.swift "$ROOT/src" 2>/dev/null | grep -Ev "$SEAM_DIRS" | grep -v "Minis.xcodeproj" || true)
  if [ -n "$hits" ]; then
    echo "VIOLATION: non-seam app code references RemoteKit symbol '$w':"
    echo "$hits" | head -3
    viol=1
  fi
done

# 4) RemoteKit must not import App internals (sandbox package still compiles it)
if grep -rEn "import (Minis|Claude|Moonveil)" --include=*.swift "$ROOT/Packages" 2>/dev/null | grep -qv "import Foundation"; then
  echo "VIOLATION: RemoteKit imports App internals"; viol=1
fi

[ "$viol" = 0 ] && echo "[gate] single-module isolation OK"
exit $viol