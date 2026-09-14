#!/usr/bin/env bash
# 门3: every mode fork must sit inside Fusion/ / tab container; regex-audit.
echo "[gate] fork-point audit"
if grep -rEn "backend\s*==\s*\.remote|mode\s*==\s*\"remote\"" --include=*.swift src/ios | grep -v "Fusion" | grep -v "Tab"; then
  echo "VIOLATION: mode fork outside designated container"; exit 1
fi
echo "[gate] fork-point OK"
