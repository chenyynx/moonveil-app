#!/usr/bin/env bash
# 门1: App must not import RemoteKit internals; RemoteKit must not import App.
# Fails (exit 1) on any forbidden edge.
echo "[gate] import-direction scan"
viol=0
# D4 seam registry (2026-09-15, B8-FIX): `import RemoteKit` is legal ONLY from
# these directories (the two fork-point shells). `import AAV2` stays banned
# everywhere (frozen internals must never be touched directly). Gate teeth
# proven by counter-evidence test (add a RemoteKit import to any other file ->
# must FAIL).
SEAM_DIRS="src/ios/Views/ModeTabs/|src/ios/Views/AuthAA/"
if grep -rEn "import RemoteKit" --include=*.swift src/ios 2>/dev/null | grep -Ev "$SEAM_DIRS" | grep -q .; then
  echo "VIOLATION: App source imports RemoteKit outside registered seams"; viol=1
fi
if grep -rEn "import AAV2" --include=*.swift src/ios 2>/dev/null | grep -q .; then
  echo "VIOLATION: App source imports AAV2 internals (frozen zone)"; viol=1
fi
if grep -rEn "import (Minis|Claude|App)" --include=*.swift Packages 2>/dev/null | grep -v "import Foundation"; then
  echo "VIOLATION: RemoteKit imports App internals"; viol=1
fi
[ "$viol" = 0 ] && echo "[gate] import-scan OK"
exit $viol
