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
# Sanctioned internals consumers come from TWO different mechanisms, on purpose.
# ModeTabs / AuthAA / Packages stay whole-directory seams (pre-existing, small, and
# each one is a designated entry point -- the same per-file question arguably applies
# to them and is deliberately not settled here).
# Views/RemoteSessions is NOT a directory seam. pp decision 2026-09-22: the 41 files
# that actually reference RemoteKit internals are enumerated in scripts/rk-seam-files.txt.
# Why per-file: the refreshed 312-word registry put 100% of the 83 violating symbols
# inside that one directory (58 .swift files, 41 of them offenders), so registering the
# directory would leave the deep scan with a zero expected fire rate for the only place
# in the app that keeps growing RemoteKit references -- a new file there referencing
# RemoteSessionBackend (one of the 6 hardcoded shallow names) passed BOTH scans. The
# 17 clean files there stay under the gate, and any new offender has to add a line to
# the list, which makes the diff itself the review point.
SEAM_DIRS="$ROOT/src/ios/Views/ModeTabs|$ROOT/src/ios/Views/AuthAA|$ROOT/Packages"
SEAM_LIST="$ROOT/scripts/rk-seam-files.txt"
seam_abs=""
if [ ! -f "$SEAM_LIST" ]; then
  echo "VIOLATION: $SEAM_LIST missing -- the per-file seam list is what keeps this gate armed inside Views/RemoteSessions"; viol=1
else
  while IFS= read -r rel; do
    case "$rel" in ''|'#'*) continue ;; esac
    case "$rel" in /*) echo "VIOLATION: seam-list entry must be repo-relative, got: $rel"; viol=1; continue ;; esac
    if [ ! -f "$ROOT/$rel" ]; then
      # A stale row silently re-opens a hole for whatever file replaces it.
      echo "VIOLATION: seam-list row points at a deleted file: $rel -- delete the row"; viol=1; continue
    fi
    seam_abs="${seam_abs:+${seam_abs}|}${ROOT}/${rel}"
  done < "$SEAM_LIST"
fi
if [ "${RK_GATE_FULL_SCAN:-0}" = "1" ]; then
  # On-demand deep scan (312 words x 581 files is a CI-time landmine; the
  # compiler itself is the push-time backstop for unresolved RK names).
  # Run RK_GATE_FULL_SCAN=1 locally/in scheduled audits.
  banned_words=$(sed -e '/^#/d' -e '/^$/d' "$REG" 2>/dev/null | tr '\n' ' ')
else
  banned_words="RemoteSessionBackend RemoteSessionServing PublicRemoteService HTTPTransport WebSocketTransport V2APIClient"
fi
for w in $banned_words; do
  hits=$(grep -rnE "(^|[^.[:alnum:]_])${w}\b" --include=*.swift "$ROOT/src" 2>/dev/null \
    | grep -Ev "$SEAM_DIRS" \
    | grep -v "Minis.xcodeproj" \
    | awk -v skip="$seam_abs" 'BEGIN{n=split(skip,a,"|");for(i=1;i<=n;i++)s[a[i]]=1}
        { p=substr($0,1,index($0,":")-1); if (!(p in s)) print }' || true)
  if [ -n "$hits" ]; then
    echo "VIOLATION: non-seam app code references RemoteKit symbol '$w':"
    echo "$hits" | head -3
    viol=1
  fi
done

# 3b) reverse check: every seam-list row must still reference >=1 registry symbol.
# Without this the list only ever grows -- a file that stops touching RemoteKit
# internals keeps its exemption forever, and the next RemoteKit reference that
# lands in it is then invisible. Always uses the full registry (not the 6 shallow
# words) so a legitimately-narrow file is not falsely flagged. Cost: one grep per
# listed file (41 today), not per word.
if [ -f "$REG" ] && [ -f "$SEAM_LIST" ]; then
  words_alt=$(sed -e '/^#/d' -e '/^$/d' "$REG" | paste -sd'|' -)
  while IFS= read -r rel; do
    case "$rel" in ''|'#'*) continue ;; esac
    [ -f "$ROOT/$rel" ] || continue   # deleted rows are already a violation above
    if ! grep -qE "(^|[^.[:alnum:]_])(${words_alt})\b" "$ROOT/$rel"; then
      echo "VIOLATION: seam-list row references no RemoteKit symbol any more: $rel -- delete the row"
      viol=1
    fi
  done < "$SEAM_LIST"
fi

# 4) RemoteKit must not import App internals (sandbox package still compiles it)
if grep -rEn "import (Minis|Claude|Moonveil)" --include=*.swift "$ROOT/Packages" 2>/dev/null | grep -qv "import Foundation"; then
  echo "VIOLATION: RemoteKit imports App internals"; viol=1
fi

[ "$viol" = 0 ] && echo "[gate] single-module isolation OK"
exit $viol