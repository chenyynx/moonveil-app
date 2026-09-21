#!/usr/bin/env bash
# swiftc -parse sweep over the app-build .swift surface (list owned by
# audit-swift-registration.py --list-compiled, so registration and syntax gates
# can never drift to different file sets).
# COVERAGE: SYNTAX ONLY. swiftc -parse does not resolve symbols or types — a
# scope error like "cannot find 'contentmodifier' in scope" passes this gate.
# Type-level errors remain iOS Build's job. Honest layer statement, no exceptions.
# Known grammar divergence: swiftc 6.0.3 rejects trailing commas in arg/collection
# literals (SE-0439 landed in Swift 6.1; Xcode 26.2 accepts them — AAV2 upstream
# code uses them). An error whose reported position sits on a closing bracket and
# whose message is exactly "unexpected ',' separator" is downgraded to a warning;
# every other diagnostic fails the gate.
# Modes: default = full sweep (content-hash cache makes re-runs seconds);
#        --changed = only `git diff --name-only HEAD` ∩ app surface (read-only git).
# Env: SWIFTC (toolchain binary), SWIFT_VERSION_FLAG (default 5 = pbxproj/CI SWIFT_VERSION),
#      JOBS (default nproc), MOONVEIL_PARSE_CACHE (cache root).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-/home/ubuntu/swift-6.0.3/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc}"
SV="${SWIFT_VERSION_FLAG:-5}"
JOBS="${JOBS:-$(nproc)}"
MODE=full
if [ "${1:-}" = "--changed" ]; then MODE=changed
elif [ "${1:-}" = "--files" ]; then MODE=files; shift; fi
if [ ! -x "$SWIFTC" ]; then
  echo "[swift-parse] FATAL: no swiftc at $SWIFTC (set SWIFTC=...) — gate is fail-closed" >&2
  exit 2
fi
FLAGS="-parse -swift-version $SV -enable-bare-slash-regex" # bare-slash-regex: PATCHES.md:209 (Xcode 26.2 default-on)

SURFACE="$("$ROOT/scripts/audit-swift-registration.py" --list-compiled)"
if [ -z "$SURFACE" ]; then echo "[swift-parse] FATAL: empty app-surface list" >&2; exit 2; fi
LIST=$(mktemp /tmp/swift-parse-list.XXXXXX)
if [ "$MODE" = changed ]; then
  CHANGED=$(mktemp /tmp/swift-parse-changed.XXXXXX)
  git -C "$ROOT" diff --name-only HEAD | sed "s|^|$ROOT/|" | sort > "$CHANGED"
  printf '%s\n' "$SURFACE" | sort > "$LIST"
  comm -12 "$LIST" "$CHANGED" > "$LIST.f" && mv "$LIST.f" "$LIST"
  rm -f "$CHANGED"
  if [ ! -s "$LIST" ]; then echo "[swift-parse] --changed: no app-surface .swift in HEAD diff, nothing to do"; exit 0; fi
elif [ "$MODE" = files ]; then
  printf '%s\n' "$@" | sed "/^$/d" > "$LIST"
else
  printf '%s\n' "$SURFACE" > "$LIST"
fi

CACHE="${MOONVEIL_PARSE_CACHE:-$HOME/.cache/moonveil-swift-parse}"
TCID="$( { "$SWIFTC" --version; echo "$FLAGS"; } | sha256sum | cut -c1-16)"
CDIR="$CACHE/$TCID"
mkdir -p "$CDIR"
OUT=$(mktemp -d /tmp/swift-parse-out.XXXXXX)
trap 'rm -rf "$OUT" "$LIST"' EXIT
export SWIFTC FLAGS CDIR OUT

worker() {
  f="$1"
  key=$(sha256sum "$f" | cut -d' ' -f1)
  if [ -f "$CDIR/$key.status" ]; then
    st=$(cat "$CDIR/$key.status")
    [ "$st" = ok ] && return 0
    if [ "$st" = div ]; then cp "$CDIR/$key.div" "$OUT/div-$key"; return 0; fi
    cp "$CDIR/$key.diag" "$OUT/fail-$key"; echo "$f" >> "$OUT/fail-hits"
    return 0
  fi
  # shellcheck disable=SC2086
  diag=$($SWIFTC $FLAGS "$f" 2>&1) || {
    # classify: downgrade iff EVERY error is a trailing-comma reported AT a closer
    div=1
    nerr=0
    while IFS= read -r eline; do
      nerr=$((nerr+1))
      ef=$(printf '%s' "$eline" | cut -d: -f1); el=$(printf '%s' "$eline" | cut -d: -f2)
      ec=$(printf '%s' "$eline" | cut -d: -f3)
      case "$eline" in *"error: unexpected ',' separator"*) ;; *) div=0; break ;; esac
      at=$(awk -v l="$el" -v c="$ec" 'NR==l{print substr($0,c,1); exit}' "$ef" 2>/dev/null)
      case "$at" in [\)\]\}]) ;; *) div=0; break ;; esac
    done < <(printf '%s\n' "$diag" | grep -E '^[^[:space:]].*: error: ')
    [ "$nerr" = 0 ] && div=0
    if [ "$nerr" = 0 ]; then div=0; fi
    if [ "$div" = 1 ]; then
      { echo "$f"; printf '%s\n' "$diag" | grep -cE "^[^[:space:]].*error: unexpected ',' separator"; } > "$OUT/div-$key"
      cp "$OUT/div-$key" "$CDIR/$key.div"; echo div > "$CDIR/$key.status"
      return 0
    fi
    printf '%s\n' "$diag" > "$CDIR/$key.diag"; echo fail > "$CDIR/$key.status"
    cp "$CDIR/$key.diag" "$OUT/fail-$key"; echo "$f" >> "$OUT/fail-hits"
    return 0
  }
  [ -z "$diag" ] || : # warnings-only: pass (Xcode parity — e.g. upcoming-feature notes)
  echo ok > "$CDIR/$key.status"
}
export -f worker

xargs -a "$LIST" -d'\n' -P"$JOBS" -I{} bash -c 'worker "$@"' _ {} >/dev/null 2>&1

NFAIL=$(ls "$OUT"/fail-* 2>/dev/null | grep -cv 'hits$' || true)
NDIV=$(ls "$OUT"/div-* 2>/dev/null | wc -l)
NTOT=$(wc -l < "$LIST")
[ "$NDIV" -gt 0 ] && { echo "[swift-parse] toolchain-divergence (downgraded; Xcode 26.2 grammar accepts):"
  for d in "$OUT"/div-*; do echo "  $(head -1 "$d") — $(tail -1 "$d") comma-errors"; done; }
if [ "$NFAIL" -gt 0 ]; then
  echo "[swift-parse] SYNTAX FAILURES:"
  while IFS= read -r f; do echo "  $f"; done < "$OUT/fail-hits"
  for d in "$OUT"/fail-*; do
    case "$d" in *hits) continue ;; esac
    hits=$(grep -E '(error|warning):' "$d" | grep -v '^[[:space:]]' | head -10 | sed 's/^/    /')
    if [ -n "$hits" ]; then echo "$hits"; else head -3 "$d" | sed 's/^/    /'; fi
  done
fi
echo "[swift-parse] files=$NTOT fail=$NFAIL divergence=$NDIV toolchain=$("$SWIFTC" --version | head -1)"
[ "$NFAIL" -gt 0 ] && exit 1
exit 0
