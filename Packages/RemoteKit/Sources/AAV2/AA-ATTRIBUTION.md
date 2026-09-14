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
- Upgrade flow: AA ships new tag → re-copy seeds → regenerate manifest → review `git diff`
  → bump `AAV2_BASE_TAG` (gate script) + this file → contracts fixtures 对拍 before prod.

## Batch 1 (2026-09-15, G3) — 6 seed files, 1,245 lines
Upstream path root = `ios/Agents Anywhere/Agents Anywhere/`:

| local path | lines | role |
|---|---|---|
| `Repositories/V2SessionRepository.swift` | 668 | coalescing/bounded cache/live recovery (D1 injection target: `init(localStore:)`) |
| `Repositories/V2LocalStore.swift` | 58 | JSON-file archive store (atomic + FileProtection) |
| `Repositories/V2LocalArchive.swift` | 70 | archive layout (meta/items/cursor/Pending) |
| `Models/Session/V2SessionModel.swift` | 291 | session state model |
| `Models/Session/V2SessionReadCoordinator.swift` | 146 | read/older-pages coordinator |
| `Views/Components/StableViewModel.swift` | 12 | StateObject lazy holder (no UI deps) |

All seeds import only `Foundation` / `Observation` / `Combine` — **zero AppState coupling**
(god-object check: 0 hits).

## Status: frozen zone, NOT yet compiled
`Package.swift` declares **no AAV2 target** yet. Dependency-closure analysis (2026-09-15,
identifier-graph over the v2.0.0 ios tree): seeds transitively reference **144 files /
15,366 lines** — AA's app module is monolithic, and the closure drags in the whole SwiftUI
chat/view tree (ChatTimelineView, SidebarDrawer, …) which must not enter RemoteKit.
Wiring plan (Glue batches): pull a compilable sub-closure layer at a time —
Domain/ models → Network/API → Repositories — declaring the AAV2 target only when `swift build` passes.

## Deliberately not in batch 1
`V2SessionDetailService` / `V2RuntimeInteractionService` / Auth suite / `SessionChatModel` /
presentation-layer files — each drags UI or service closure; scheduled per D2/D1 wiring batches,
not dropped (功能完整性总纲: 排期≠弃用).
