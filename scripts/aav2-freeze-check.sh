#!/usr/bin/env bash
# 门1补: AAV2 freeze check — Sources/AAV2/**.swift must stay byte-identical to AA upstream tag.
#
# BATCH-B (2026-09-22) 盲区修复. 旧版有两个假绿口子，这里全部堵上：
#  (a) 只遍历 manifest 行 → 往 AAV2/ 新增一个未登记 .swift 文件、或从 manifest 删一行，
#      两种模式下都零告警。现在有结构性断言（磁盘 .swift 集合 ⇔ manifest 行集合，含计数）。
#  (b) CI 拿不到 MV_CLOUD 时静默降级成"仅 manifest 自洽"还打 OK —— 而 manifest 本身
#      可以被重新 sha256sum 覆盖（实测：MarkdownBlockSizing/TimelineHistoryPull 两文件
#      早已偏离 v2.0.0，manifest 却与磁盘一致 → CI 绿）。现在比对的"上游字节基准"是
#      提交进本仓的 scripts/aav2-freeze-baseline.txt（一次性从官方仓 tag 生成），
#      runner 无需任何外部仓库即可做真字节级比对。
#
# Modes:
#   default           : structure + manifest digest + pinned-upstream baseline
#                       (+ strong per-file git diff when MV_CLOUD is set)
#   --structure-only  : structure + manifest digest, NO upstream byte comparison.
#                       Blocking CI step only while the baseline reds are pending
#                       disposition; prints a loud coverage warning. Never use alone.
#   --write-baseline  : regenerate the baseline from $MV_CLOUD @ $BASE_TAG (requires MV_CLOUD).
#                       Review the diff of scripts/aav2-freeze-baseline.txt before committing —
#                       regenerating it from a tampered source is how this gate dies.
# All modes are fail-closed: missing inputs (manifest / baseline / toolchain) = exit non-zero.
set -euo pipefail
BASE_TAG="${AAV2_BASE_TAG:-v2.0.0}"
IOS_SUB="ios/Agents Anywhere/Agents Anywhere"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="$ROOT/Packages/RemoteKit/Sources/AAV2"
MANIFEST="$A/FREEZE-MANIFEST.txt"
BASELINE="$ROOT/scripts/aav2-freeze-baseline.txt"
BASELINE_TAG_FIELD='pinned-upstream-tag:'
MODE=full
case "${1:-}" in
  '') ;;
  --structure-only) MODE=structure ;;
  --write-baseline) MODE=write-baseline ;;
  *) echo "[gate] FATAL: unknown mode '${1:-}' (expected --structure-only or --write-baseline)" >&2; exit 2 ;;
esac
cd "$A"

command -v sha256sum >/dev/null || { echo "[gate] FATAL: sha256sum unavailable — gate is fail-closed" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "[gate] FATAL: $MANIFEST missing — nothing to check" >&2; exit 2; }

echo "[gate] AAV2 freeze check (base tag $BASE_TAG, mode $MODE${MV_CLOUD:+, MV_CLOUD=$MV_CLOUD})"

# ---------- 0) provenance helpers ----------
# RC = accumulated verdict of the non-fatal sections (1 = freeze violated).
RC=0
# Expected upstream bytes for a frozen file, with ONLY the documented approved
# transforms applied. Single source of truth for strong-mode diff and baseline
# generation, so the two can never disagree about what "verbatim" means.
upstream_bytes() { # $1 = path relative to AAV2/
  local p="$1"
  git -C "$MV_CLOUD" show "$BASE_TAG:$IOS_SUB/$p" 2>/dev/null \
    || { echo "[gate] FATAL: $BASE_TAG:$IOS_SUB/$p not found in $MV_CLOUD" >&2; return 3; }
}
expected_bytes() { # $1 = path relative to AAV2/
  case "$1" in
    Network/HTTPTransport.swift)
      # Approved deviation AAV2-AWAIT-1 (pp-signed 2026-09-15 「行」): upstream-tag
      # content with EXACTLY this sed applied. Revoking the await OR adding a second
      # deviation fails every mode of this gate.
      upstream_bytes "$1" | sed "s/retryPolicy\.permitsRetry(error)/await retryPolicy.permitsRetry(error)/" ;;
    *) upstream_bytes "$1" ;;
  esac
}
# Valid manifest/baseline row = '<64-hex>  <path>'. Anything else is ignored as comment,
# never silently trusted.
rows_of() { awk 'NF == 2 && length($1) == 64 && $1 !~ /[^0-9a-f]/ { print }' "$1"; }
paths_of() { rows_of "$1" | awk '{ print $2 }' | sort; }

# ---------- 1) structure: disk ⇔ manifest (fail-closed, both modes) ----------
DISK_L=$(mktemp); MAN_L=$(mktemp); BASE_L=$(mktemp); UPB=$(mktemp); trap 'rm -f "${DISK_L:-}" "${MAN_L:-}" "${BASE_L:-}" "${UPB:-}" "$BASELINE.tmp"' EXIT
find . -name '*.swift' | sed 's|^\./||' | sort > "$DISK_L"
awk 'NF && !/^#/ { if (NF != 2 || length($1) != 64 || $1 ~ /[^0-9a-f]/) { print "  " $0; bad=1 } } END { if (bad) exit 1 }' "$MANIFEST" > "$MAN_L.bad" || {
  echo "VIOLATION: FREEZE-MANIFEST.txt has malformed rows (expect '<64-hex sha256>  <path>'):"
  cat "$MAN_L.bad"; rm -f "$MAN_L.bad"; exit 1
}
rm -f "$MAN_L.bad"
paths_of "$MANIFEST" > "$MAN_L"
if [ "$(wc -l < "$DISK_L")" != "$(wc -l < "$MAN_L")" ]; then
  echo "VIOLATION: file-count mismatch — AAV2 has $(wc -l < "$DISK_L") .swift on disk, FREEZE-MANIFEST.txt lists $(wc -l < "$MAN_L")"
fi
if ! comm -13 "$DISK_L" "$MAN_L" | grep -q .; then :; else
  echo "VIOLATION: manifest lists files that are NOT on disk (deleted without de-registering):"
  comm -13 "$DISK_L" "$MAN_L" | sed 's/^/  /'
fi
if ! comm -23 "$DISK_L" "$MAN_L" | grep -q .; then :; else
  echo "VIOLATION: .swift files on disk that are NOT registered in FREEZE-MANIFEST.txt (unregistered frozen code = zero coverage):"
  comm -23 "$DISK_L" "$MAN_L" | sed 's/^/  /'
fi
{ [ "$(wc -l < "$DISK_L")" = "$(wc -l < "$MAN_L")" ] \
  && [ -z "$(comm -13 "$DISK_L" "$MAN_L")" ] \
  && [ -z "$(comm -23 "$DISK_L" "$MAN_L")" ]; } || exit 1
echo "[gate] structure OK: $(wc -l < "$DISK_L") .swift ⇔ $(wc -l < "$MAN_L") manifest rows (bidirectional)"

# ---------- 2) manifest digest vs disk (fail-closed, both modes) ----------
if ! sha256sum -c FREEZE-MANIFEST.txt --status; then
  echo "VIOLATION: AAV2 file diverged from FREEZE-MANIFEST.txt (verbatim zone — changes belong in Glue)"
  sha256sum -c FREEZE-MANIFEST.txt 2>/dev/null | grep -v OK$ || true
  RC=1
else
  echo "[gate] disk == FREEZE-MANIFEST.txt digests"
fi

# ---------- 3) manifest path set ⇔ baseline path set, then byte-vs-baseline ----------
if [ "$MODE" = write-baseline ]; then
  [ -n "${MV_CLOUD:-}" ] || { echo "[gate] FATAL: --write-baseline needs MV_CLOUD=/path/to/moonveil-cloud" >&2; exit 2; }
  command -v git >/dev/null || { echo "[gate] FATAL: git unavailable, cannot read upstream tag" >&2; exit 2; }
  OUT="$BASELINE.tmp"
  # FINDING-1 fix (2026-09-22 adversarial review): never hash through a command-
  # substitution pipeline — `$(expected_bytes|sha256sum|cut)` returns cut's status
  # (always 0), so an unreadable upstream file used to land as sha256("") in the
  # baseline with exit 0. Upstream bytes now go to $UPB first; ANY read failure
  # aborts the whole write (all-or-nothing) with a non-zero exit.
  UP_FAILS=0
  UP_FAILED_PATHS=""
  {
    echo "# GENERATED by scripts/aav2-freeze-check.sh --write-baseline — review the diff before committing."
    echo "# sha256 of the EXPECTED upstream bytes for every file in AAV2/FREEZE-MANIFEST.txt."
    echo "# This is the CI-side anchor: the runner has no copy of the official repo, so the"
    echo "#   byte-level freeze guarantee is only as good as this committed list."
    echo "# Strong mode re-derives it from \$MV_CLOUD and fails on any mismatch (baseline tamper check)."
    echo "# $BASELINE_TAG_FIELD $BASE_TAG"
    echo "# upstream-remote: $(git -C "$MV_CLOUD" remote get-url origin 2>/dev/null || echo 'unknown')"
    echo "# upstream-commit: $(git -C "$MV_CLOUD" rev-parse "$BASE_TAG^{commit}" 2>/dev/null || echo 'unknown')"
    echo "# generated-at: $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S %z')"
    while read -r path; do
      if ! expected_bytes "$path" > "$UPB"; then
        UP_FAILS=$((UP_FAILS + 1))
        UP_FAILED_PATHS="$UP_FAILED_PATHS  $path"$'\n'
        continue
      fi
      # NB: standalone assignment, NOT a substitution inside printf args —
      # errexit+pipefail can only see the status of the former.
      line_sha=$(sha256sum "$UPB" | cut -d' ' -f1)
      printf '%s  %s\n' "$line_sha" "$path"
    done < <(paths_of "$MANIFEST")
  } > "$OUT"
  if [ "$UP_FAILS" != 0 ]; then
    rm -f "$OUT"
    echo "[gate] write-baseline ABORTED: upstream-read failures: $UP_FAILS — $BASELINE left UNTOUCHED (fail-closed, no partial/poisoned baseline):"
    printf '%s' "$UP_FAILED_PATHS" | sed 's/^/  /'
    exit 2
  fi
  mv "$OUT" "$BASELINE"
  echo "[gate] baseline regenerated: $BASELINE ($(rows_of "$BASELINE" | wc -l) rows, tag $BASE_TAG, upstream-read failures: $UP_FAILS)"
  [ "$RC" = 0 ] || echo "[gate] NOTE: local bytes currently FAIL the digest check — the baseline was derived from $BASE_TAG in \$MV_CLOUD, never from local files."
  exit 0
fi

if [ "$MODE" = structure ]; then
  echo "[gate] WARNING: --structure-only — coverage = disk⇔manifest + digests only, NO upstream byte comparison."
  echo "[gate] WARNING: stale/whitelaundered manifest is NOT detected by this mode. Known-red crutch,"
  echo "[gate] WARNING: remove the flag from ci.yml once the baseline reds are dispositioned."
  [ "$RC" = 0 ] && echo "[gate] AAV2 freeze OK (structure-only, reduced coverage)" || echo "[gate] AAV2 freeze FAILED (structure/manifest)"
  exit $RC
fi

[ -f "$BASELINE" ] || { echo "[gate] FATAL: $BASELINE missing — baseline check cannot run (regenerate with --write-baseline)" >&2; exit 2; }
if ! grep -q "^# $BASELINE_TAG_FIELD $BASE_TAG$" "$BASELINE"; then
  pinned=$(grep "^# $BASELINE_TAG_FIELD" "$BASELINE" 2>/dev/null | awk '{print $3}' || true)
  echo "VIOLATION: baseline is pinned to '${pinned:-<none>}', but this run checks BASE_TAG='$BASE_TAG'"
  echo "  Bump AAV2_BASE_TAG only together with a regenerated, reviewed baseline."
  exit 1
fi
paths_of "$BASELINE" > "$BASE_L"
if [ -n "$(comm -3 "$MAN_L" "$BASE_L")" ]; then
  echo "VIOLATION: FREEZE-MANIFEST.txt and aav2-freeze-baseline.txt cover different file sets"
  echo "  manifest-only:"; comm -23 "$MAN_L" "$BASE_L" | sed 's/^/    /'
  echo "  baseline-only:"; comm -13 "$MAN_L" "$BASE_L" | sed 's/^/    /'
  exit 1
fi
bl_fail=0
while read -r sha path; do
  [ -f "$path" ] || { echo "MISSING: $path (listed in baseline, absent from disk)"; bl_fail=1; continue; }
  have=$(sha256sum "$path" | cut -d' ' -f1)
  if [ "$have" != "$sha" ]; then
    echo "VIOLATION: $path differs from the pinned upstream $BASE_TAG bytes (baseline digest $sha)"
    bl_fail=1
  fi
done < <(rows_of "$BASELINE")
if [ "$bl_fail" = 1 ]; then
  echo "[gate] AAV2 vs pinned upstream baseline: DIVERGED (see VIOLATION lines above)"
  echo "[gate] NOTE: the manifest can be re-sha256'd to match local edits; the baseline cannot — it is upstream's digest, committed."
  RC=1   # keep going: strong mode below still re-derives from the official repo, so the
         # local run reports baseline AND git-diff evidence in one pass.
else
  echo "[gate] AAV2 == pinned upstream baseline ($BASE_TAG, $(wc -l < "$BASE_L") files, byte-level)"
fi

# ---------- 4) strong mode: re-derive from the official repo ----------
if [ -n "${MV_CLOUD:-}" ]; then
  command -v git >/dev/null || { echo "[gate] FATAL: MV_CLOUD set but git unavailable" >&2; exit 2; }
  fail=0
  while read -r _sha path; do
    [ -f "$path" ] || { echo "MISSING: $path"; fail=1; continue; }
    # FINDING-1 class fix: materialise upstream bytes BEFORE diffing. With
    # `diff <(expected_bytes …)`, a failed upstream read degenerates to comparing
    # /dev/null vs a (possibly empty) local file — a false-green hole. Status now checked explicitly.
    if ! expected_bytes "$path" > "$UPB"; then
      echo "VIOLATION: $path — cannot read upstream $BASE_TAG bytes from $MV_CLOUD (fail-closed)"
      fail=1; continue
    fi
    if ! diff -q "$UPB" "$path" >/dev/null 2>&1; then
      if [ "$path" = "Network/HTTPTransport.swift" ]; then
        echo "VIOLATION: HTTPTransport.swift diverges BEYOND the approved AAV2-AWAIT-1"
      else
        echo "VIOLATION: $path diverges from $BASE_TAG in $MV_CLOUD"
      fi
      fail=1
    fi
  done < <(rows_of "$MANIFEST")
  # baseline tamper check: committed list must equal what upstream actually says
  while read -r bsha path; do
    # FINDING-2 fix: the old `true_b=$(expected_bytes|sha256sum|cut) || …` guard was
    # unreachable (pipeline exits with cut's 0). Read failure is now detected at the
    # source, so a baseline line holding sha256("") can never pass as "integrity OK".
    if ! expected_bytes "$path" > "$UPB"; then
      echo "VIOLATION(baseline-integrity): $path — cannot read upstream $BASE_TAG bytes from $MV_CLOUD (fail-closed)"; fail=1; continue
    fi
    true_b=$(sha256sum "$UPB" | cut -d' ' -f1)
    if [ "$true_b" != "$bsha" ]; then
      echo "VIOLATION(baseline-integrity): $path — committed baseline says $bsha, upstream $BASE_TAG says $true_b"
      fail=1
    fi
  done < <(rows_of "$BASELINE")
  if [ "$fail" = 1 ]; then RC=1; else
    echo "[gate] AAV2 vs upstream tag: byte-identical (strong) + baseline integrity verified"
  fi
else
  echo "[gate] WEAK SOURCE MODE: no MV_CLOUD — upstream bytes come from the committed baseline only."
  echo "[gate]   (still a real byte check: baseline holds upstream's digests, not ours; export"
  echo "[gate]    MV_CLOUD=/path/to/moonveil-cloud to also re-derive and audit that baseline)"
fi
if [ "$RC" = 0 ]; then echo "[gate] AAV2 freeze OK"; else echo "[gate] AAV2 freeze VIOLATED"; fi
exit $RC
