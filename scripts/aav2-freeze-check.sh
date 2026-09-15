#!/usr/bin/env bash
# 门1补: AAV2 freeze check — Sources/AAV2/**.swift must stay byte-identical to AA upstream tag.
# Strong mode (local exec env): MV_CLOUD=/path/to/moonveil-cloud → per-file byte diff vs git show $BASE_TAG:<ios>/<path>
# CI mode (default): recompute sha256 and check against FREEZE-MANIFEST.txt (trust anchored by code review + commit provenance).
# Exit non-zero on ANY divergence. Edits in the freeze zone are forbidden — adapt in Sources/Glue.
set -euo pipefail
BASE_TAG="${AAV2_BASE_TAG:-v2.0.0}"
IOS_SUB="ios/Agents Anywhere/Agents Anywhere"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="$ROOT/Packages/RemoteKit/Sources/AAV2"
cd "$A"

echo "[gate] AAV2 freeze check (base tag $BASE_TAG)"

if ! sha256sum -c FREEZE-MANIFEST.txt --status; then
  echo "VIOLATION: AAV2 file diverged from FREEZE-MANIFEST.txt (verbatim zone — changes belong in Glue)"
  sha256sum -c FREEZE-MANIFEST.txt 2>/dev/null | grep -v OK$ || true
  exit 1
fi

if [ -n "${MV_CLOUD:-}" ]; then
  fail=0
  while read -r _sha path; do
    case "$path" in ''|\#*) continue ;; esac
    [ -f "$path" ] || { echo "MISSING: $path"; fail=1; continue; }
    if [ "$path" = "Network/HTTPTransport.swift" ]; then
      # Approved deviation AAV2-AWAIT-1 (pp-signed 2026-09-15 「行」): our file must
      # equal upstream-tag content with EXACTLY the documented sed applied.
      # Revoking the await OR any second deviation fails this check either way.
      if diff -q <(git -C "$MV_CLOUD" show "$BASE_TAG:$IOS_SUB/$path" \
          | sed "s/retryPolicy\.permitsRetry(error)/await retryPolicy.permitsRetry(error)/") \
          "$path" >/dev/null 2>&1; then
        echo "[gate] HTTPTransport.swift == upstream + AAV2-AWAIT-1 (approved) only"
        continue
      fi
      echo "VIOLATION: HTTPTransport.swift diverges BEYOND the approved AAV2-AWAIT-1"
      fail=1
      continue
    fi
    if ! diff -q <(git -C "$MV_CLOUD" show "$BASE_TAG:$IOS_SUB/$path") "$path" >/dev/null 2>&1; then
      echo "VIOLATION: $path diverges from $BASE_TAG in $MV_CLOUD"
      fail=1
    fi
  done < <(grep -v '^#' FREEZE-MANIFEST.txt)
  if [ "$fail" = 1 ]; then exit 1; fi
  echo "[gate] AAV2 vs upstream tag: byte-identical (strong)"
else
  echo "[gate] manifest-only mode (export MV_CLOUD=/path/to/moonveil-cloud for strong byte diff)"
fi
echo "[gate] AAV2 freeze OK"
