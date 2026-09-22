#!/usr/bin/env bash
# SEAM-LOSSLESS gate: the four remote archive write paths must carry real session
# data end to end (Glue write surface -> device-detail callback -> list incremental
# merge). Scope is honestly bounded: this is a TEXTUAL/STRUCTURAL check. It cannot
# type-check (the Linux toolchain here only parses; type-level regressions such as
# Bool/Void returns are caught by the macOS iOS Build in CI), and it cannot prove
# semantic correctness of the derived change sets. What it does guarantee: the
# payload-carrying wiring patterns this repo converged on are still present, and
# the specific silent degradations listed below turn the gate red:
#   - Glue writers gutted (return []), mapping call removed, repository write or
#     the projectId-filter / local-draft-exclusion anchors removed
#   - device-detail trigger sites passing a literal empty array, an argument-less
#     call, an unknown payload variable, or a `changed` binding that no longer
#     originates from a Glue write call
#   - a trigger site deleted outright (exact-count check on the four sites)
#   - the list consumer regressing to a force reload or dropping applyRemoteChange
#   - the loader losing its in-flight-load replay anchors (changeLog/startGen) or
#     reintroducing a date-only archived-row sort
# It does NOT catch: a structurally-plausible-but-wrong payload source (e.g. a new
# write path wired with an unrelated non-empty list), or upstream server changes;
# the "archive-all returns the full affected set" premise of the lossless claim is
# evidenced in V2RemoteChatServices.archiveProject's doc comment, not by this script.
# Rationale ledger: PATCHES.md (remote-line seam), ci.yml deep-scan step.
echo "[gate] remote archive write-path losslessness"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GLUE="$ROOT/Packages/RemoteKit/Sources/Glue/V2RemoteChatServices.swift"
DETAIL="$ROOT/src/ios/Views/RemoteSessions/RemoteDeviceDetailView.swift"
LIST="$ROOT/src/ios/Views/RemoteSessions/RemoteSessionListView.swift"
LOADER="$ROOT/src/ios/Views/RemoteSessions/RemoteSessionLoader.swift"
viol=0
fail() { echo "VIOLATION: $1"; viol=1; }

# body FILE SIGREX -- print a 4-space-indented function body (from the line
# matching SIGREX up to the first line that is exactly "^    }").
body() {
  awk -v pat="$2" '$0 ~ pat {inb=1} inb {print} inb && /^    \}$/ {exit}' "$1"
}

# 1) Glue write surface returns the public mirror, not Bool/Void.
grep -qE 'func setSessionsArchived\(sessionIds: \[V2SessionID\], archived: Bool\) async -> \[RemoteSessionMeta\]\?' "$GLUE" \
  || fail "V2RemoteChatServices.setSessionsArchived must return [RemoteSessionMeta]? (nil = failure)"
grep -qE 'func archiveProject\(id: String, archived: Bool\) async throws -> \[RemoteSessionMeta\]' "$GLUE" \
  || fail "V2RemoteChatServices.archiveProject(id:archived:) must return [RemoteSessionMeta] (frozen repo writer stays the sole mutator; meta derived from its repository write-back)"
grep -qE 'func updateSessions\(_ updated: \[V2SessionMeta\]\) -> \[RemoteSessionMeta\]' "$GLUE" \
  || fail "V2RemoteChatServices.updateSessions must return the mirrored change set"

# 1b) Glue writer BODIES must stay real. Signature checks above are shape-only;
# without these, a gutted body (return []) keeps every signature intact.
UPD="$(body "$GLUE" 'func updateSessions')"
case "$UPD" in *"return []"*) fail "updateSessions body returns a literal empty array (payload gutted)";; esac
echo "$UPD" | grep -q 'dashboardRepository.upsert(' \
  || fail "updateSessions body lost its dashboard-repository write-back (upsert)"
echo "$UPD" | grep -q 'RemoteService.mapSession' \
  || fail "updateSessions body no longer mirrors its input to RemoteSessionMeta"
ARC="$(body "$GLUE" 'func setSessionsArchived')"
case "$ARC" in *"return []"*) fail "setSessionsArchived body returns a literal empty array on some path (payload gutted)";; esac
echo "$ARC" | grep -q 'dashboard.archive(sessionIds: sessionIds)' \
  || fail "setSessionsArchived body lost the dashboard.archive write"
echo "$ARC" | grep -q 'dashboard.unarchive(sessionIds: sessionIds)' \
  || fail "setSessionsArchived body lost the dashboard.unarchive write"
echo "$ARC" | grep -q 'RemoteService.mapSession' \
  || fail "setSessionsArchived body no longer mirrors the server-returned change set"
PROJ="$(body "$GLUE" 'func archiveProject')"
case "$PROJ" in *"return []"*) fail "archiveProject body returns a literal empty array (payload gutted)";; esac
echo "$PROJ" | grep -q 'dashboardRepository.archiveProject(' \
  || fail "archiveProject body must keep the frozen repository writer as its sole mutator"
# Derivation anchor: the change set must be scoped to the project the write
# targeted. Losing this turns the derivation into a whole-repository dump that
# silently overwrites unrelated rows' merge decisions downstream.
echo "$PROJ" | grep -q 'projectId == id' \
  || fail "archiveProject lost the projectId filter (derivation no longer scoped to the archived project)"
echo "$PROJ" | grep -q 'hasPrefix("local:")' \
  || fail "archiveProject lost the local-draft exclusion (ghost rows can leak into the list mirror)"

# 2) The callback slot is payload-bearing...
grep -qE 'var onSessionsChanged: \(\(\[RemoteSessionMeta\]\) -> Void\)\?' "$DETAIL" \
  || fail "RemoteDeviceDetailView.onSessionsChanged must carry [RemoteSessionMeta]"
# 2a) Whitelist: every trigger must pass one of the two known change-set
# sources. This single check subsumes the old argument-less-call ban and also
# catches inline literal payloads (`onSessionsChanged?([])`) and renames to an
# unknown variable. Failure mode it cannot cover: reusing the whitelisted names
# with a fake source -- that is what 2b/2c pin down.
CALLS=$(grep -nE 'onSessionsChanged\?\(' "$DETAIL" | grep -vE 'onSessionsChanged\?\((changed|services\.updateSessions\(sessions\))\)')
if [ -n "$CALLS" ]; then echo "$CALLS"; fail "onSessionsChanged trigger not passing a whitelisted change-set source"; fi
# 2b) Exact trigger-site count. A deleted site silently reopens that archive
# path's stale-list hole; adding a legitimate write path means updating 2a's
# whitelist and this count together.
NSITES=$(grep -cE 'onSessionsChanged\?\(' "$DETAIL")
[ "$NSITES" = 4 ] || fail "expected exactly 4 onSessionsChanged trigger sites, found $NSITES"
# 2c) Every `changed` binding must originate from a Glue write call. Catches
# `let changed: [RemoteSessionMeta] = []` (or any other fake) feeding the
# otherwise-whitelisted `onSessionsChanged?(changed)`.
BIND=$(grep -nE '(let|var)[[:space:]]+changed\b' "$DETAIL" | grep -vE 'services\.setSessionsArchived\(|services\.archiveProject\(')
if [ -n "$BIND" ]; then echo "$BIND"; fail "a 'changed' binding does not come from setSessionsArchived/archiveProject"; fi
# 2d) The flat archive-all path's `sessions` must come from the frozen model
# (server-returned change set), not a rebound fake -- the 2a whitelist alone
# cannot see a source swap behind updateSessions(sessions).
grep -qE 'if let sessions = await model\.archiveSessions' "$DETAIL" \
  || fail "device-detail flat archiveAll lost its server-authoritative sessions binding"
# 3) The three meta-producing write paths keep their lossless wiring.
for pat in \
  'if let changed = await services\.setSessionsArchived' \
  'try await services\.archiveProject\(' \
  'onSessionsChanged\?\(services\.updateSessions\(sessions\)\)'; do
  grep -qE "$pat" "$DETAIL" || fail "device-detail write path lost its lossless wiring (pattern: $pat)"
done

# 4) Consumer merges incrementally instead of force-reloading both tables.
grep -qE 'onSessionsChanged: \{ changed in' "$LIST" \
  || fail "RemoteSessionListView must bind the payload parameter of onSessionsChanged"
grep -qE 'loader\.applyRemoteChange\(changed\)' "$LIST" \
  || fail "RemoteSessionListView must merge the change set via loader.applyRemoteChange"
if grep -nE 'onSessionsChanged: \{[^}]*force: true' "$LIST"; then
  fail "onSessionsChanged regressed to a force reload (flashes the loading skeleton)"
fi
grep -qE 'func applyRemoteChange\(_ sessions: \[RemoteSessionMeta\]\)' "$LOADER" \
  || fail "RemoteSessionLoader.applyRemoteChange([RemoteSessionMeta]) missing"

# 4b) Replay guard against the load/applyRemoteChange race: a change set must be
# logged and any in-flight full-table response must replay the post-request
# entries before publishing. These anchors catch a "helpful" refactor that drops
# the replay while keeping the no-flicker merge (the resurrection bug returns
# with no force-reload to self-heal it).
grep -qE 'private var changeLog' "$LOADER" \
  || fail "RemoteSessionLoader lost its changeLog (in-flight load replay)"
NGEN=$(grep -cE 'let startGen = changeGeneration' "$LOADER")
[ "$NGEN" -ge 2 ] || fail "load() and loadArchived() must each capture changeGeneration before issuing the request (found $NGEN)"
NREPLAY=$(grep -cE 'replayed\(afterGen: startGen' "$LOADER")
[ "$NREPLAY" -ge 2 ] || fail "both full-table landing points must replay pending change sets (found $NREPLAY)"

# 4c) Row-order uniformity: archived rows must share the list comparator
# (pinned-first). A reintroduced ad-hoc date-only sort makes pinned archived
# rows jump position between an incremental merge and the next full refresh.
if grep -nE 'sort[[:space:]]*\{[[:space:]]*\$0\.sortDate[[:space:]]*>[[:space:]]*\$1\.sortDate[[:space:]]*\}' "$LOADER"; then
  fail "date-only sort reintroduced in the loader; use the shared listOrder comparator"
fi
grep -qE 'static func listOrder' "$LOADER" \
  || fail "RemoteSessionLoader.listOrder (shared pinned-first comparator) missing"

[ "$viol" = 0 ] && echo "[gate] remote archive write-path losslessness OK"
exit $viol
