#!/usr/bin/env bash
# Generic verbatim-freeze gate. One implementation, many zones.
#
# A "zone" is a set of files that must stay byte-identical to a pinned upstream
# revision of the official Agents Anywhere repo ($MV_CLOUD). Zones differ only in
# WHERE their files live locally, WHAT upstream path each maps to, and whether the
# scanned directories are frozen in full or only in part (allow-listed).
#
# Callers do NOT invoke this directly. Thin per-zone wrappers set FREEZE_ZONE and
# forward the mode argument:
#   scripts/aav2-freeze-check.sh     -> FREEZE_ZONE=aav2
#   scripts/authaa-freeze-check.sh   -> FREEZE_ZONE=authaa
#
# Modes (identical across zones, fail-closed in every one):
#   (none)            : structure + local manifest digest + pinned-upstream baseline
#                       (+ strong per-file git diff when MV_CLOUD is set)
#   --structure-only  : structure + local manifest digest, NO upstream byte comparison.
#   --write-baseline  : regenerate the baseline from $MV_CLOUD @ $BASE_TAG (requires MV_CLOUD).
#   --help            : print this header's operator-facing summary and exit 0.
#
# Environment:
#   FREEZE_BASE_TAG           override the pinned upstream rev for THIS zone.
#                             Legacy alias AAV2_BASE_TAG is still honoured as a
#                             fallback (it never was AAV2-only: it controlled the
#                             anchor of every zone that sourced it), but new
#                             callers/scripts should set FREEZE_BASE_TAG.
#   MV_CLOUD                  path to moonveil-cloud; enables strong mode.
#   FREEZE_ALLOW_TRANSITION   set to 1 to acknowledge a manifest-shrink or
#                             allow-list-growth transition (see sections 1b/1c).
#
# Manifest / baseline row grammar: '<64-hex sha256>  <local-spec>'.
#   <local-spec> = <path-relative-to-zone-cwd>  OR  <path>@<upstream-relpath-under-IOS_SUB>
#   When the '@<upstream>' part is omitted the upstream path defaults to the local
#   path (the AAV2 rule: the frozen dir mirrors the upstream layout 1:1). The AuthAA
#   zone carries an explicit '@...' because its verbatim files map to scattered
#   upstream subpaths (Views/Components, Views/Auth, Services, Resources/Fonts, ...).
#   Specs with >=2 '@' are malformed and rejected; basename(local) MUST equal
#   basename(upstream) or the run fails (an '@' pointing at a different-named
#   upstream file is how one file's bytes would be laundered under another's name).
#
# Allow-list row grammar (partially-frozen zones), deliberately different from
# the manifest's so no parser can cross-consume the other's file:
#   '<local-path>  <64-hex sha256 at registration>  <one-line ASCII reason>'
# The registered sha makes 'skin files change over time' a DATED, deliberate
# re-registration: if the file on disk diverges from its registered sha the gate
# goes red until the sha (and, if stale, the reason) is updated. The entry count
# is capped per zone (ALLOWLIST_MAX); growth beyond the cap is a VIOLATION.
#
# Why baseline lives separately from the manifest: the manifest holds OUR local
# digests and can be re-sha256'd to launder an edit; the baseline holds UPSTREAM's
# digests, committed, and strong mode re-derives it from $MV_CLOUD to catch tampering.
set -euo pipefail

ZONE="${FREEZE_ZONE:-aav2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ---------- zone configuration ----------
# Per zone we resolve:
#   CWD              : directory all relative paths live under
#   IOS_SUB          : upstream repo subpath prefix
#   SCAN_DIRS        : directories (relative to CWD) scanned for structure assertions
#   SCAN_EXPR        : find predicate selecting frozen-eligible files
#   MANIFEST/BASELINE: committed list files (paths absolute)
#   ALLOWLIST        : spec of files in SCAN_DIRS that are INTENTIONALLY local (not frozen);
#                      empty for a zone whose scanned dirs are frozen in full.
#   ALLOWLIST_MAX    : hard cap on allow-list entries; exceeding it is a VIOLATION.
#                      Raising the cap must happen HERE, in a reviewable one-line edit.
#   MANIFEST_ROWS_PINNED / ALLOWLIST_ROWS_PINNED : exact expected row counts,
#                      pinned in THIS engine file. Section 1b's shrink/growth watch
#                      compares against git HEAD, which goes naked when the ledger
#                      is not yet committed (a new zone's first run) or when the
#                      checkout has no .git at all. Pinning the count here means the
#                      "delete a manifest row, re-register that file in the allow
#                      list" laundering -- structure-clean and count-conserving --
#                      still trips an assertion whose baseline lives in a different
#                      file that must be edited in full view. Changing coverage
#                      requires editing BOTH the ledger and this constant.
#   BASE_TAG_DEFAULT : pinned upstream revision for this zone
case "$ZONE" in
  aav2)
    CWD="$ROOT/Packages/RemoteKit/Sources/AAV2"
    IOS_SUB="ios/Agents Anywhere/Agents Anywhere"
    SCAN_DIRS=(.)
    SCAN_EXPR=(-name '*.swift')
    MANIFEST="$CWD/FREEZE-MANIFEST.txt"
    BASELINE="$ROOT/scripts/aav2-freeze-baseline.txt"
    ALLOWLIST_FILE=""   # whole dir frozen: disk set must equal manifest set exactly
    ALLOWLIST_MAX=0
    MANIFEST_ROWS_PINNED=103
    ALLOWLIST_ROWS_PINNED=0
    BASE_TAG_DEFAULT="1bc11f45"
    ;;
  authaa)
    CWD="$ROOT"
    IOS_SUB="ios/Agents Anywhere/Agents Anywhere"
    SCAN_DIRS=(src/ios/Views/AuthAA src/ios/Views/SettingsSkin)
    SCAN_EXPR=(\( -name '*.swift' -o -name '*.ttf' \))
    MANIFEST="$ROOT/scripts/authaa-freeze-manifest.txt"
    BASELINE="$ROOT/scripts/authaa-freeze-baseline.txt"
    ALLOWLIST_FILE="$ROOT/scripts/authaa-skin-allowlist.txt"
    ALLOWLIST_MAX=10    # registered 2026-09-22 (8 diverged skins + 2 no-counterpart files)
    MANIFEST_ROWS_PINNED=8
    ALLOWLIST_ROWS_PINNED=10
    BASE_TAG_DEFAULT="1bc11f45"
    ;;
  *)
    echo "[gate] FATAL: unknown FREEZE_ZONE='$ZONE' (expected aav2 or authaa)" >&2
    exit 2
    ;;
esac

BASE_TAG="${FREEZE_BASE_TAG:-${AAV2_BASE_TAG:-$BASE_TAG_DEFAULT}}"   # AAV2_BASE_TAG = legacy alias, see header
BASELINE_TAG_FIELD='pinned-upstream-rev:'

MODE=full
case "${1:-}" in
  '') ;;
  --structure-only) MODE=structure ;;
  --write-baseline) MODE=write-baseline ;;
  --help|-h) MODE=help ;;
  *) echo "[gate] FATAL: unknown mode '${1:-}' (expected --structure-only, --write-baseline or --help)" >&2; exit 2 ;;
esac

if [ "$MODE" = help ]; then
  cat <<'EOF'
usage: scripts/{aav2,authaa}-freeze-check.sh [--structure-only|--write-baseline|--help]

Verbatim-freeze gate engine: scripts/freeze-check.sh (do not call directly;
FREEZE_ZONE selects the zone, the wrappers pin it).

Modes:
  (none)            structure + manifest digest + committed baseline
                    (+ strong per-file upstream diff when MV_CLOUD is set)
  --structure-only  coverage reduced to disk<->list structure + local digests.
                    Never rely on it alone.
  --write-baseline  regenerate the committed baseline from $MV_CLOUD @ base rev.
  --help            this text.

Environment:
  FREEZE_BASE_TAG           override the pinned upstream rev (legacy alias:
                            AAV2_BASE_TAG, still honoured as fallback; it was
                            never AAV2-only -- it anchors every zone that read it).
  MV_CLOUD=/path/to/moonveil-cloud
                            strong mode: re-derive upstream bytes via git show and
                            audit the committed baseline itself.
  FREEZE_ALLOW_TRANSITION=1
                            acknowledge a TRANSITION (manifest row-count shrink or
                            skin allow-list growth vs committed HEAD). Transitions
                            are refused without this; setting it does NOT silence
                            the warning -- it must accompany pp sign-off in the
                            commit message.

List files:
  manifest/baseline row: '<64-hex sha256>  <local-path>[@<upstream-relpath>]'
                         (at most one '@'; basename(local) must equal basename(upstream))
  allow-list row:        '<local-path>  <64-hex sha256 at registration>  <ASCII reason>'
                         (count capped by ALLOWLIST_MAX in the engine; stale
                         registered sha = VIOLATION, re-register on every skin edit)
EOF
  exit 0
fi

command -v sha256sum >/dev/null || { echo "[gate] FATAL: sha256sum unavailable -- gate is fail-closed" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "[gate] FATAL: $MANIFEST missing -- nothing to check" >&2; exit 2; }
if [ -n "$ALLOWLIST_FILE" ]; then
  [ -f "$ALLOWLIST_FILE" ] || { echo "[gate] FATAL: $ALLOWLIST_FILE missing -- allow-listed zone cannot verify coverage" >&2; exit 2; }
fi

cd "$CWD"
echo "[gate] freeze check (zone=$ZONE, base rev $BASE_TAG, mode $MODE${MV_CLOUD:+, MV_CLOUD=$MV_CLOUD})"

# ---------- 0) provenance helpers ----------
RC=0   # accumulated verdict of the non-fatal sections (1 = freeze violated)

# split a <local-spec> into local path and upstream-relative path.
# No '@' -> upstream defaults to the local path (AAV2 1:1 layout rule).
local_of() { printf '%s' "${1%@*}"; }
upstream_of() { local s="$1"; if [[ "$s" == *"@"* ]]; then printf '%s' "${s#*@}"; else printf '%s' "$s"; fi; }

# Expected upstream bytes for a frozen file, with ONLY the documented approved
# transforms applied. Single source of truth for strong-mode diff AND baseline
# generation, so the two can never disagree about what "verbatim" means.
upstream_bytes() { # $1 = local-spec
  local up; up="$(upstream_of "$1")"
  git -C "$MV_CLOUD" show "$BASE_TAG:$IOS_SUB/$up" 2>/dev/null \
    || { echo "[gate] FATAL: $BASE_TAG:$IOS_SUB/$up not found in $MV_CLOUD" >&2; return 3; }
}
expected_bytes() { # $1 = local-spec
  case "$1" in
    Network/HTTPTransport.swift)
      # Approved deviation AAV2-AWAIT-1 (pp-signed 2026-09-15): upstream-tag
      # content with EXACTLY this sed applied. Revoking the await OR adding a second
      # deviation fails every mode of this gate.
      upstream_bytes "$1" | sed "s/retryPolicy\.permitsRetry(error)/await retryPolicy.permitsRetry(error)/" ;;
    *) upstream_bytes "$1" ;;
  esac
}

# A valid manifest/baseline row = '<64-hex>  <local-spec>' with AT MOST ONE '@'
# in the spec (two '@' would make local_of/upstream_of ambiguous -- reject, never
# guess). Anything else is a comment, never silently trusted.
rows_of()   { awk 'NF == 2 && length($1) == 64 && $1 !~ /[^0-9a-f]/ && split($2, _a, "@") < 3 { print }' "$1"; }
specs_of()  { rows_of "$1" | awk '{ print $2 }' | sort; }
# local paths ( '@upstream' stripped) -- what find on disk actually yields.
locals_of() { rows_of "$1" | awk '{ sub(/@.*$/, "", $2); print $2 }' | sort; }
# row-count under the allow-list grammar (3+ fields, path first, '#' comments).
list_rows() { awk 'NF && !/^#/ { n++ } END { print n+0 }' "$1"; }
# shared manifest/baseline row validator: prints offending rows, rc 1 if any.
validate_list() { # $1 = file
  awk 'NF && !/^#/ {
        if (NF != 2 || length($1) != 64 || $1 ~ /[^0-9a-f]/ || split($2, _a, "@") > 2) { print "  " $0; bad=1 }
      } END { exit bad ? 1 : 0 }' "$1"
}

TMPDIR_ZONE="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_ZONE" "$BASELINE.tmp" 2>/dev/null || true; }
trap cleanup EXIT

# ---------- 1) structure: disk <-> (manifest + allow-list) (fail-closed, both modes) ----------
MANIFEST_PLAIN="$TMPDIR_ZONE/manifest.plain"; : > "$MANIFEST_PLAIN"
DISK_L="$TMPDIR_ZONE/disk"; MAN_L="$TMPDIR_ZONE/man"; ALLOW_L="$TMPDIR_ZONE/allow"; EXPECT_L="$TMPDIR_ZONE/expect"

# Reject malformed manifest rows first (a truncated/corrupted list is not coverage).
if ! validate_list "$MANIFEST" > "$TMPDIR_ZONE/bad"; then
  echo "VIOLATION: $MANIFEST has malformed rows (expect '<64-hex sha256>  <local-spec>', at most one '@' in the spec):"
  cat "$TMPDIR_ZONE/bad"; exit 1
fi

# disk: every frozen-eligible file on disk (relative to CWD, no leading ./)
find "${SCAN_DIRS[@]}" "${SCAN_EXPR[@]}" | sed 's|^\./||' | sort > "$DISK_L"

# manifest local paths, plus plain manifest for sha256sum -c.
# '@' mapping integrity: basename(local) MUST equal basename(upstream). Without
# this, pointing '@' at SOME OTHER upstream file whose bytes were copied locally
# launders an edit even in strong mode (manifest and baseline would agree on the
# swapped mapping and the git diff would compare against the wrong source file).
# Every registered row satisfies basename equality by construction; all '@'
# mappings are echoed for human review of the mapping direction itself.
MAP_BAD=0
: > "$TMPDIR_ZONE/mappings"
while read -r sha spec; do
  lp="$(local_of "$spec")"; up="$(upstream_of "$spec")"
  if [ "$(basename -- "$lp")" != "$(basename -- "$up")" ]; then
    echo "VIOLATION: manifest row '$spec': basename(local) != basename(upstream) -- '@' mapping rejected (one upstream file's bytes registered under another's name?)"
    MAP_BAD=1
  fi
  case "$spec" in *@*) printf '  %s  ->  %s\n' "$lp" "$up" >> "$TMPDIR_ZONE/mappings" ;; esac
  printf '%s  %s\n' "$sha" "$lp" >> "$MANIFEST_PLAIN"
done < <(rows_of "$MANIFEST")
[ "$MAP_BAD" = 0 ] || exit 1
if [ -s "$TMPDIR_ZONE/mappings" ]; then
  echo "[gate] explicit @mappings ($(wc -l < "$TMPDIR_ZONE/mappings"); basename equality enforced above, shown for human review):"
  cat "$TMPDIR_ZONE/mappings"
fi

# manifest local paths ( '@upstream' stripped), consumed by the structure asserts
locals_of "$MANIFEST" > "$MAN_L"

# allow-list (zone with partially-frozen dirs); empty for full-dir zones.
# Grammar is intentionally DIFFERENT from manifest rows (3+ fields, path first,
# sha SECOND) so rows_of() can never consume allow-list lines and this parser
# rejects manifest-shaped lines ($1 must not be a bare 64-hex).
ALLOW_ROWS=0
if [ -n "$ALLOWLIST_FILE" ]; then
  if ! awk 'NF && !/^#/ {
        if (NF < 3 || length($2) != 64 || $2 ~ /[^0-9a-f]/ || (length($1) == 64 && $1 !~ /[^0-9a-f]/) || $0 ~ /[^ -~]/) { print "  " $0; bad=1 }
      } END { exit bad ? 1 : 0 }' "$ALLOWLIST_FILE" > "$TMPDIR_ZONE/allow-bad"; then
    echo "VIOLATION: $ALLOWLIST_FILE has malformed rows (expect '<path>  <64-hex sha256 at registration>  <one-line ASCII reason>'):"
    cat "$TMPDIR_ZONE/allow-bad"; exit 1
  fi
  ALLOW_ROWS="$(list_rows "$ALLOWLIST_FILE")"
  if [ "$ALLOW_ROWS" -gt "$ALLOWLIST_MAX" ]; then
    echo "VIOLATION: $ALLOWLIST_FILE holds $ALLOW_ROWS entries -- cap is $ALLOWLIST_MAX."
    echo "  The allow-list must not expand silently; each entry costs a registered sha + reason and trips the pinned-count / TRANSITION watches (sections 1b/1c). If the cap itself must move, edit ALLOWLIST_MAX in scripts/freeze-check.sh so the growth is a reviewable one-line diff."
    exit 1
  fi
  # Registered-sha check: skin files ARE expected to change -- that is what the
  # allow-list is for -- but each change must be a deliberate re-registration.
  # Stale registered sha = this file moved after someone signed off on its
  # content, i.e. the allow-list is being used as an unchecked dump site.
  while read -r lp rsha _rest; do
    case "$lp" in ''|'#'*) continue ;; esac
    [ -f "$lp" ] || continue   # missing file is reported by the structure assertion below
    have=$(sha256sum "$lp" | cut -d' ' -f1)
    if [ "$have" != "$rsha" ]; then
      echo "VIOLATION: allow-listed skin file changed after registration: $lp"
      echo "  registered at $rsha, disk now $have"
      echo "  the skin edit itself is legal -- re-register it: write the new sha256 (sha256sum $lp | cut -d' ' -f1) and, if stale, the reason into $ALLOWLIST_FILE"
      exit 1
    fi
  done < "$ALLOWLIST_FILE"
  awk 'NF && !/^#/ { print $1 }' "$ALLOWLIST_FILE" | sort > "$ALLOW_L"
else
  : > "$ALLOW_L"
fi

# The expected on-disk set = frozen manifest set UNION allow-list set.
sort -u "$MAN_L" "$ALLOW_L" > "$EXPECT_L"

STRUCT_FAIL=0
if [ "$(wc -l < "$DISK_L")" != "$(wc -l < "$EXPECT_L")" ]; then
  echo "VIOLATION: file-count mismatch -- $ZONE scans $(wc -l < "$DISK_L") eligible files, manifest+allow-list expect $(wc -l < "$EXPECT_L")"
  STRUCT_FAIL=1
fi
if [ -n "$(comm -23 "$EXPECT_L" "$DISK_L")" ]; then
  echo "VIOLATION: manifest/allow-list lists files that are NOT on disk (deleted without de-registering):"
  comm -23 "$EXPECT_L" "$DISK_L" | sed 's/^/  /'
  STRUCT_FAIL=1
fi
if [ -n "$(comm -13 "$EXPECT_L" "$DISK_L")" ]; then
  echo "VIOLATION: files on disk that are NEITHER registered in the manifest NOR in the allow-list (unregistered verbatim code = zero coverage):"
  comm -13 "$EXPECT_L" "$DISK_L" | sed 's/^/  /'
  STRUCT_FAIL=1
fi
[ "$STRUCT_FAIL" = 0 ] || exit 1
# ---------- 1b) pinned coverage counts (HEAD-independent, not ackable) ----------
# Section 1c needs a committed ledger to compare against; this does not, so it
# also guards a zone's very first run and a checkout without .git. Placed before
# the transition branch so FREEZE_ALLOW_TRANSITION=1 cannot bypass it.
MAN_ROWS="$(rows_of "$MANIFEST" | wc -l)"
PIN_FAIL=0
if [ "$MAN_ROWS" != "$MANIFEST_ROWS_PINNED" ]; then
  echo "VIOLATION ($ZONE): manifest has $MAN_ROWS rows, engine pins $MANIFEST_ROWS_PINNED."
  echo "  Either coverage was silently removed (a verbatim file left the frozen zone)"
  echo "  or the zone legitimately changed size -- in which case edit MANIFEST_ROWS_PINNED"
  echo "  in scripts/freeze-check.sh in the same commit, with pp sign-off."
  PIN_FAIL=1
fi
if [ "$ALLOW_ROWS" != "$ALLOWLIST_ROWS_PINNED" ]; then
  echo "VIOLATION ($ZONE): allow-list has $ALLOW_ROWS rows, engine pins $ALLOWLIST_ROWS_PINNED."
  echo "  A file migrating from verbatim to local adds an allow-list row AND drops a"
  echo "  manifest row; the counts above are what make that swap impossible to hide."
  PIN_FAIL=1
fi
[ "$PIN_FAIL" = 0 ] || exit 1
echo "[gate] pinned counts OK: $MAN_ROWS frozen + $ALLOW_ROWS allow-listed (engine-pinned)"

# ---------- 1c) transition watch: coverage moving from verbatim to local ----------
# "drop a file from the manifest, register it in the allow-list" is the ONLY
# sanctioned escape from the byte freeze, so any manifest row-count SHRINK or
# allow-list GROWTH vs the committed (git HEAD) versions is flagged as a
# TRANSITION. Design decision (pp left it to the implementer, 2026-09-22):
# BLOCKED by default, ackable via FREEZE_ALLOW_TRANSITION=1. A mere warning would
# re-silence exactly the escape this section exists to watch -- CI swallows
# warnings on green runs. Migrations stay legal: the ack env var is the explicit
# gate, the TRANSITION lines print in both branches, and the commit message is
# required to carry pp sign-off. Files absent from HEAD (a zone being introduced)
# are skipped with a NOTE instead of a false transition.
git_head_list() { # $1 = abs list path, $2 = dest for HEAD copy; rc 0 = HEAD has it
  local rel="${1#"$ROOT/"}"
  command -v git >/dev/null 2>&1 && git -C "$ROOT" show "HEAD:$rel" > "$2" 2>/dev/null
}
git_head_rows() { # $1 = abs list path, $2 = grammar (manifest|allowlist); echoes count or NA
  local copy="$TMPDIR_ZONE/head-$2"
  if git_head_list "$1" "$copy"; then
    if [ "$2" = manifest ]; then rows_of "$copy" | wc -l; else list_rows "$copy"; fi
  else
    echo NA
  fi
}
MAN_HEAD_ROWS="$(git_head_rows "$MANIFEST" manifest)"
ALLOW_HEAD_ROWS="NA"
[ -n "$ALLOWLIST_FILE" ] && ALLOW_HEAD_ROWS="$(git_head_rows "$ALLOWLIST_FILE" allowlist)"

[ "$MAN_HEAD_ROWS" = NA ] && echo "[gate] NOTE: $MANIFEST has no committed version at HEAD (new file / no git) -- manifest-shrink watch skipped this run (pinned counts in 1b still applied)."
{ [ -n "$ALLOWLIST_FILE" ] && [ "$ALLOW_HEAD_ROWS" = NA ]; } && echo "[gate] NOTE: $ALLOWLIST_FILE has no committed version at HEAD -- allow-list-growth watch skipped this run."
TRANS=""
# Path-level delta, printed alongside the counts: an ack on "103 -> 102" with no
# names is a blind signature. Whoever acks must see WHICH file left the frozen
# zone and WHICH joined the allow list.
TRANS_DELTA="$TMPDIR_ZONE/transition-delta"; : > "$TRANS_DELTA"
if [ "$MAN_HEAD_ROWS" != NA ] && [ "$MAN_ROWS" -lt "$MAN_HEAD_ROWS" ]; then
  TRANS="manifest rows $MAN_HEAD_ROWS -> $MAN_ROWS (verbatim coverage REMOVED)"
  if git_head_list "$MANIFEST" "$TMPDIR_ZONE/hm"; then
    locals_of "$TMPDIR_ZONE/hm" > "$TMPDIR_ZONE/hm.l"; locals_of "$MANIFEST" > "$TMPDIR_ZONE/cur.l"
    {
      echo "  - left the manifest (no longer byte-frozen):"
      comm -23 "$TMPDIR_ZONE/hm.l" "$TMPDIR_ZONE/cur.l" | sed 's/^/      /'
      echo "  + entered the manifest (newly byte-frozen):"
      comm -13 "$TMPDIR_ZONE/hm.l" "$TMPDIR_ZONE/cur.l" | sed 's/^/      /'
    } >> "$TRANS_DELTA"
  fi
fi
if [ "$ALLOW_HEAD_ROWS" != NA ] && [ "$ALLOW_ROWS" -gt "$ALLOW_HEAD_ROWS" ]; then
  TRANS="${TRANS:+$TRANS; }allow-list rows $ALLOW_HEAD_ROWS -> $ALLOW_ROWS (local-file coverage ADDED)"
  if git_head_list "$ALLOWLIST_FILE" "$TMPDIR_ZONE/ha"; then
    awk 'NF && !/^#/ { print $1 }' "$TMPDIR_ZONE/ha" | sort > "$TMPDIR_ZONE/ha.l"
    {
      echo "  + newly allow-listed (now exempt from the byte freeze):"
      comm -13 "$TMPDIR_ZONE/ha.l" "$ALLOW_L" | sed 's/^/      /'
    } >> "$TRANS_DELTA"
  fi
fi
if [ -n "$TRANS" ]; then
  echo "*** TRANSITION ($ZONE): coverage moved from verbatim to local vs committed HEAD: $TRANS"
  [ -s "$TRANS_DELTA" ] && cat "$TRANS_DELTA"
  echo "***   This is the registered escape path out of the byte freeze; it must be a pp-approved, visibly-acknowledged act, never a silent one."
  if [ "${FREEZE_ALLOW_TRANSITION:-0}" = 1 ]; then
    echo "***   ACKNOWLEDGED via FREEZE_ALLOW_TRANSITION=1 -- continuing; the commit message MUST record the pp sign-off and which file migrated why."
  else
    echo "VIOLATION: TRANSITION refused. Re-run with FREEZE_ALLOW_TRANSITION=1 only AFTER pp signs off on the migration."
    exit 1
  fi
fi

# ---------- 2) manifest digest vs disk (fail-closed, both modes) ----------
if ! sha256sum -c "$MANIFEST_PLAIN" --status; then
  echo "VIOLATION: a $ZONE file diverged from FREEZE-MANIFEST.txt (verbatim zone -- changes belong in Glue/skin)"
  sha256sum -c "$MANIFEST_PLAIN" 2>/dev/null | grep -v ': OK$' || true
  RC=1
else
  echo "[gate] disk == FREEZE-MANIFEST.txt digests"
fi

# ---------- 3) manifest spec set <-> baseline spec set, then byte-vs-baseline ----------
if [ "$MODE" = write-baseline ]; then
  [ -n "${MV_CLOUD:-}" ] || { echo "[gate] FATAL: --write-baseline needs MV_CLOUD=/path/to/moonveil-cloud" >&2; exit 2; }
  command -v git >/dev/null || { echo "[gate] FATAL: git unavailable, cannot read upstream" >&2; exit 2; }
  OUT="$BASELINE.tmp"
  UPB="$TMPDIR_ZONE/upb"
  # Never hash through a command-substitution pipeline -- cut's status (always 0)
  # would let an unreadable upstream file land as sha256("") with exit 0. Upstream
  # bytes go to $UPB first; ANY read failure aborts the whole write (all-or-nothing).
  UP_FAILS=0
  UP_FAILED_PATHS=""
  {
    echo "# GENERATED by scripts/freeze-check.sh (zone $ZONE) --write-baseline -- review the diff before committing."
    echo "# sha256 of the EXPECTED upstream bytes for every file in ${MANIFEST#"$ROOT/"}."
    echo "# This is the CI-side anchor: the runner has no copy of the official repo, so the"
    echo "#   byte-level freeze guarantee is only as good as this committed list."
    echo "# Strong mode re-derives it from \$MV_CLOUD and fails on any mismatch (baseline tamper check)."
    echo "# $BASELINE_TAG_FIELD $BASE_TAG"
    echo "# upstream-remote: $(git -C "$MV_CLOUD" remote get-url origin 2>/dev/null || echo 'unknown')"
    echo "# upstream-commit: $(git -C "$MV_CLOUD" rev-parse "$BASE_TAG^{commit}" 2>/dev/null || echo 'unknown')"
    echo "# generated-at: $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M:%S %z')"
    while read -r spec; do
      if ! expected_bytes "$spec" > "$UPB"; then
        UP_FAILS=$((UP_FAILS + 1))
        UP_FAILED_PATHS="$UP_FAILED_PATHS  $spec"$'\n'
        continue
      fi
      line_sha=$(sha256sum "$UPB" | cut -d' ' -f1)
      printf '%s  %s\n' "$line_sha" "$spec"
    done < <(specs_of "$MANIFEST")
  } > "$OUT"
  if [ "$UP_FAILS" != 0 ]; then
    rm -f "$OUT"
    echo "[gate] write-baseline ABORTED: upstream-read failures: $UP_FAILS -- $BASELINE left UNTOUCHED (fail-closed, no partial/poisoned baseline):"
    printf '%s' "$UP_FAILED_PATHS" | sed 's/^/  /'
    exit 2
  fi
  mv "$OUT" "$BASELINE"
  echo "[gate] baseline regenerated: $BASELINE ($(rows_of "$BASELINE" | wc -l) rows, rev $BASE_TAG, upstream-read failures: $UP_FAILS)"
  [ "$RC" = 0 ] || echo "[gate] NOTE: local bytes currently FAIL the digest check -- the baseline was derived from $BASE_TAG in \$MV_CLOUD, never from local files."
  exit 0
fi

if [ "$MODE" = structure ]; then
  echo "[gate] WARNING: --structure-only -- coverage = disk<->manifest+allow-list and digests only, NO upstream byte comparison."
  echo "[gate] WARNING: stale/whitelaundered manifest is NOT detected by this mode. Never rely on it alone."
  [ "$RC" = 0 ] && echo "[gate] freeze OK (structure-only, reduced coverage; zone=$ZONE)" || echo "[gate] freeze FAILED (structure/manifest; zone=$ZONE)"
  exit $RC
fi

[ -f "$BASELINE" ] || { echo "[gate] FATAL: $BASELINE missing -- baseline check cannot run (regenerate with --write-baseline)" >&2; exit 2; }
if ! validate_list "$BASELINE" > "$TMPDIR_ZONE/bad"; then
  echo "VIOLATION: $BASELINE has malformed rows (expect '<64-hex sha256>  <local-spec>', at most one '@' in the spec):"
  cat "$TMPDIR_ZONE/bad"; exit 1
fi
if ! grep -q "^# $BASELINE_TAG_FIELD $BASE_TAG$" "$BASELINE"; then
  pinned=$(grep "^# $BASELINE_TAG_FIELD" "$BASELINE" 2>/dev/null | awk '{print $3}' || true)
  echo "VIOLATION: baseline is pinned to '${pinned:-<none>}', but this run checks BASE_TAG='$BASE_TAG'"
  echo "  Bump FREEZE_BASE_TAG (legacy alias AAV2_BASE_TAG) only together with a regenerated, reviewed baseline."
  exit 1
fi
specs_of "$MANIFEST" > "$TMPDIR_ZONE/man-spec"
specs_of "$BASELINE" > "$TMPDIR_ZONE/base-spec"
if [ -n "$(comm -3 "$TMPDIR_ZONE/man-spec" "$TMPDIR_ZONE/base-spec")" ]; then
  echo "VIOLATION: manifest and baseline cover different file sets (zone=$ZONE)"
  echo "  manifest-only:"; comm -23 "$TMPDIR_ZONE/man-spec" "$TMPDIR_ZONE/base-spec" | sed 's/^/    /'
  echo "  baseline-only:"; comm -13 "$TMPDIR_ZONE/man-spec" "$TMPDIR_ZONE/base-spec" | sed 's/^/    /'
  exit 1
fi

BL_FAIL=0
while read -r sha spec; do
  lp="$(local_of "$spec")"
  [ -f "$lp" ] || { echo "MISSING: $lp (listed in baseline, absent from disk)"; BL_FAIL=1; continue; }
  have=$(sha256sum "$lp" | cut -d' ' -f1)
  if [ "$have" != "$sha" ]; then
    echo "VIOLATION: $lp differs from the pinned upstream $BASE_TAG bytes (baseline digest $sha)"
    BL_FAIL=1
  fi
done < <(rows_of "$BASELINE")
if [ "$BL_FAIL" = 1 ]; then
  echo "[gate] $ZONE vs pinned upstream baseline: DIVERGED (see VIOLATION lines above)"
  echo "[gate] NOTE: the manifest can be re-sha256'd to match local edits; the baseline cannot -- it is upstream's digest, committed."
  RC=1   # keep going: strong mode below still re-derives from the official repo, so a local
         # run reports baseline AND git-diff evidence in one pass.
else
  echo "[gate] $ZONE == pinned upstream baseline ($BASE_TAG, $(specs_of "$BASELINE" | wc -l) files, byte-level)"
fi

# ---------- 4) strong mode: re-derive from the official repo ----------
if [ -n "${MV_CLOUD:-}" ]; then
  command -v git >/dev/null || { echo "[gate] FATAL: MV_CLOUD set but git unavailable" >&2; exit 2; }
  UPB="$TMPDIR_ZONE/upb"
  fail=0
  while read -r _sha spec; do
    lp="$(local_of "$spec")"
    [ -f "$lp" ] || { echo "MISSING: $lp"; fail=1; continue; }
    # Materialise upstream bytes BEFORE diffing. With `diff <(expected_bytes ...)` a
    # failed upstream read degenerates to comparing /dev/null vs a local file -- a
    # false-green hole. Status is now checked explicitly.
    if ! expected_bytes "$spec" > "$UPB"; then
      echo "VIOLATION: $lp -- cannot read upstream $BASE_TAG bytes from $MV_CLOUD (fail-closed)"
      fail=1; continue
    fi
    if ! diff -q "$UPB" "$lp" >/dev/null 2>&1; then
      if [ "$spec" = "Network/HTTPTransport.swift" ]; then
        echo "VIOLATION: HTTPTransport.swift diverges BEYOND the approved AAV2-AWAIT-1"
      else
        echo "VIOLATION: $lp diverges from $BASE_TAG in $MV_CLOUD"
      fi
      fail=1
    fi
  done < <(rows_of "$MANIFEST")
  # baseline tamper check: committed list must equal what upstream actually says
  while read -r bsha spec; do
    if ! expected_bytes "$spec" > "$UPB"; then
      echo "VIOLATION(baseline-integrity): $(local_of "$spec") -- cannot read upstream $BASE_TAG bytes from $MV_CLOUD (fail-closed)"; fail=1; continue
    fi
    true_b=$(sha256sum "$UPB" | cut -d' ' -f1)
    if [ "$true_b" != "$bsha" ]; then
      echo "VIOLATION(baseline-integrity): $(local_of "$spec") -- committed baseline says $bsha, upstream $BASE_TAG says $true_b"
      fail=1
    fi
  done < <(rows_of "$BASELINE")
  if [ "$fail" = 1 ]; then RC=1; else
    echo "[gate] $ZONE vs upstream rev: byte-identical (strong) + baseline integrity verified"
  fi
else
  echo "[gate] WEAK SOURCE MODE: no MV_CLOUD -- upstream bytes come from the committed baseline only."
  echo "[gate]   (still a real byte check: baseline holds upstream's digests, not ours; export"
  echo "[gate]    MV_CLOUD=/path/to/moonveil-cloud to also re-derive and audit that baseline)"
fi
if [ "$RC" = 0 ]; then echo "[gate] freeze OK (zone=$ZONE)"; else echo "[gate] freeze VIOLATED (zone=$ZONE)"; fi
exit $RC
