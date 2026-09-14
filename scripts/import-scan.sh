#!/usr/bin/env bash
# 门1: App must not import RemoteKit internals; RemoteKit must not import App.
# Fails (exit 1) on any forbidden edge.
echo "[gate] import-direction scan"
viol=0
if grep -rEn "import (RemoteKit|AAV2)" --include=*.swift src/ios 2>/dev/null | grep -qv "Packages/RemoteKit"; then
  echo "VIOLATION: App source imports RemoteKit directly"; viol=1
fi
if grep -rEn "import (Minis|Claude|App)" --include=*.swift Packages 2>/dev/null | grep -v "import Foundation"; then
  echo "VIOLATION: RemoteKit imports App internals"; viol=1
fi
[ "$viol" = 0 ] && echo "[gate] import-scan OK"
exit $viol
