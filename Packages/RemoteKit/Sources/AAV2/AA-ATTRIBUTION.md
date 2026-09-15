# AAV2 — official Agents Anywhere iOS V2 layer (MIT, verbatim port)

Source: `github.com/anywhere-labs/Agents-Anywhere` @ tag **v2.0.0**
(mirror: **chenyynx/moonveil-cloud**, branch `moonveil`, tag `v2.0.0`; upstream remote read-only).
License: upstream README「开源许可」declares **MIT** — note the repo ships **no root LICENSE file**
(only third-party subpackages carry their own); see `LICENSE-UPSTREAM.md` beside this file.

## Policy (D4 门1 / 架构 v1 §3 北极星默认判据)
- Every file in this dir is a **verbatim copy** of the tag. **Edits are forbidden** —
  adaptation belongs in `Sources/Glue/`, never here.
- Freeze gate: `scripts/aav2-freeze-check.sh`
  - strong (local exec env): `MV_CLOUD=/path/to/moonveil-cloud bash scripts/aav2-freeze-check.sh`
    → per-file byte diff against `git show v2.0.0:ios/Agents Anywhere/Agents Anywhere/<path>`;
  - CI: recompute sha256 vs `FREEZE-MANIFEST.txt`.
- **Wiring ledger** = the `sources:` whitelist in `Package.swift`. A file may exist in this
  dir yet be uncompilable-as-part-of-RemoteKit (its closure not ported). Compiled set is
  verified every push by the RemoteKit Build workflow (`swift build`).
- Upgrade flow: AA ships new tag → re-copy seeds → regenerate manifest → review `git diff`
  → bump `AAV2_BASE_TAG` (gate script) + this file → contracts fixtures 对拍 before prod.

## Batch 1 (2026-09-15, G3) — 6 seed files, 1,245 lines
Upstream path root = `ios/Agents Anywhere/Agents Anywhere/`:

| local path | lines | role | wired? |
|---|---|---|---|
| `Repositories/V2SessionRepository.swift` | 668 | coalescing/bounded cache/live recovery (D1 injection target: `init(localStore:)`) | no (batch4+, drags API/Network) |
| `Repositories/V2LocalStore.swift` | 58 | JSON-file archive store (atomic + FileProtection) | no (batch3: needs V2Archive types only — check) |
| `Repositories/V2LocalArchive.swift` | 70 | archive layout (meta/items/cursor/Pending) | no (batch3 candidate) |
| `Models/Session/V2SessionModel.swift` | 291 | session state model | no (imports SwiftUI in upstream form) |
| `Models/Session/V2SessionReadCoordinator.swift` | 146 | read/older-pages coordinator | no (depends on repository) |
| `Views/Components/StableViewModel.swift` | 12 | StateObject lazy holder (no UI deps) | **YES (batch2)** |

All seeds import only `Foundation` / `Observation` / `Combine` (except V2SessionModel's
SwiftUI line, which is why it stays off-wire until its view surface is decided).
AppState coupling: **zero** hits (god-object check done 2026-09-15).

## Batch 2 (2026-09-15) — Domain leaf closure, 19 files, ~1.5k lines — **compiled**
Whitelisted into the AAV2 target via `Package.swift` `sources:`:
- `Domain/Common/`: V2Identifiers, V2ClientFailure, RuntimeLocalizedCopy
- `Domain/Session/`: V2SessionData, V2SessionMeta, V2SessionTimeline, V2TimelineItem, V2Project
- `Domain/Runtime/`: V2RuntimeState, V2RuntimeCatalog, V2RuntimeCapability, V2RuntimeNotice,
  V2RuntimeMessage, V2RuntimeConfig
- `Domain/Connector/`: V2Connector
- `Domain/Realtime/`: V2RealtimeModels
- `Domain/Attachment/`: V2AttachmentModels
- error family leaves: `Network/HTTPError`, `Business/V2BusinessError`
- plus StableViewModel (from batch 1)

Closure provenance: identifier-fixpoint analysis (closure3) hand-adjudicated — the full
Domain seed exploded to 59 files dragging the API/Network/SwiftUI tree; this leaf set is the
maximal compile-closed subset without those layers. Final arbiter = CI `swift build`
(RemoteKit Build workflow), not the analysis script.

## Deliberately not ported yet (scheduled, not dropped — 功能完整性总纲)
`V2SessionRepository` wiring (needs API/V2 + Network transport family), Auth suite,
`SessionChatModel` presentation surface, device/connector management services —
each lands with its own closure in later batches per D1/D2 wiring plan.
