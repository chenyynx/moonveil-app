# AAV2 — official Agents Anywhere iOS V2 layer (MIT, verbatim port)

Source: `github.com/anywhere-labs/Agents-Anywhere` @ tag **v2.0.0** (mirror: chenyynx/moonveil-cloud).
License: MIT (upstream `server`/iOS — confirm per-file header on copy).
Policy (D4 §5 / 架构 v1 §3): files in this dir are **verbatim copies only** — edits forbidden.
Upgrade = re-copy from new AA tag + run contracts fixtures diff. Diff-against-tag must stay clean
(see D4 门1: AAV2 subdir `git diff <v2.0.0> -- Packages/RemoteKit/Sources/AAV2` == empty).

Ported units (as we port): V2SessionRepository, V2SessionDetailService, V2RuntimeInteractionService,
V2LocalStore/V2LocalArchive, V2* models, SessionChatModel, StableViewModel, Auth suite.
