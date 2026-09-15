// swift-tools-version:6.0
import PackageDescription

// Moonveil RemoteKit — isolated SwiftPM package (D4 门1: App→RemoteKit one-way).
// SINGLE-MODULE DESIGN (2026-09-15, claudio precedent — its app target compiles
// RemoteHistoryKit sources directly into the app module, no package dependency):
// Sources/AAV2/** + Sources/Glue/** compile as ONE target, mirroring exactly how
// the app will compile them. Internal access works across the seam; the public
// surface = our Glue facades only (frozen files stay upstream-internal by design).
// Sources/AAV2/ = official AA iOS V2 layer (MIT, verbatim port; AAV2/AA-ATTRIBUTION.md).
//   The `sources:` whitelist IS the wiring ledger: a frozen file compiles only once its
//   dependency closure is proven. Files in the dir but off the list = ported, not wired.
// Sources/Glue/ = our only seam work (SessionBackend binding + D1 sqlite adapter + D2 out-seam).
// Freeze integrity: scripts/aav2-freeze-check.sh (CI gate), independent of compilation —
// it walks Sources/AAV2/** on disk, which this restructure does not touch.
let package = Package(
    name: "RemoteKit",
    platforms: [.iOS(.v17), .macOS(.v14)], // v17 = Observation floor of frozen AAV2 (iOS Build exit-65 forensics 2026-09-15; pp compat call pending)
    products: [.library(name: "RemoteKit", targets: ["RemoteKit"])],
    // Language mode pinned to Swift 5 = upstream's SWIFT_VERSION (5.0 in the
    // v2.0.0 Xcode project, verified 2026-09-15). The frozen AAV2 code leans on
    // Swift-5 warning-level actor isolation (HTTPReadRetryPolicy.permitsRetry is
    // @MainActor, called from a nonisolated retry loop; HTTPTransport.swift:56).
    // tools-version 6.0 defaults every target to Swift 6 mode, which hard-errors
    // the verbatim official sources — align the build config, freeze zone untouched.
    targets: [
        .target(
            name: "RemoteKit",
            dependencies: [],
            path: "Sources",
            sources: [
                // batch2 (2026-09-15): Domain leaf closure + error family + StableViewModel
                "AAV2/Domain/Common",
                "AAV2/Domain/Session",
                "AAV2/Domain/Runtime",
                "AAV2/Domain/Connector",
                "AAV2/Domain/Realtime",
                "AAV2/Domain/Attachment",
                "AAV2/Network",
                "AAV2/Business",
                // batch3 (2026-09-15): API/V2 transport-facing layer + WS client
                // (closure of V2APIClient composition root; no UI deps — verified)
                "AAV2/API/V2",
                // batch4 (2026-09-15): auth (v1 mobile-login trio) + session-creation
                // orchestration — closure verified = 0 extra pulls (all deps placed)
                "AAV2/API/APIClient.swift",
                "AAV2/Domain/Account",
                "AAV2/Models/APIModels.swift",
                "AAV2/Models/WorkspaceDownloadedFile.swift",
                // batch8a (2026-09-15): login-page service pair (local-network probe
                // + keychain token store); Foundation-only, consumed by Glue engine
                "AAV2/Services",
                "AAV2/Stores",
                "AAV2/Views/Components/StableViewModel.swift",
                // batch5 (2026-09-15): the seam itself (first real Glue)
                "Glue",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
