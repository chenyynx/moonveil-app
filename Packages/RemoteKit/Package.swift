// swift-tools-version:6.0
// CIFIX-6 (2026-09-21): banner 5.9 → 6.0 — only way to get .defaultIsolation(MainActor.self),
// which official ClientCore uses (ios/Package.swift: swiftSettings: [.defaultIsolation(MainActor.self)]).
// TimelineGrouping.swift:12 ($0.structure.status.isActive) hard-errors without default
// isolation; file is verbatim-frozen so the setting had to move to build config.
// B8-FIX3 superseded: that note assumed Xcode resolves this package — it does NOT
// (Minis.xcodeproj packageReferences has no RemoteKit; sources are compiled directly
// into the app target via PBXGroup + per-file build files). The banner only feeds
// `swift build` (RemoteKit Build CI + local), which honors swiftLanguageVersions.
// Language mode stays Swift 5 = upstream's SWIFT_VERSION (5.0 in the v2.0.0 Xcode
// project). Frozen AAV2 leans on Swift-5 warning-level actor isolation
// (HTTPReadRetryPolicy.permitsRetry is @MainActor, called from a nonisolated retry
// loop; HTTPTransport.swift:56) — .v5 pin keeps that warning-level, 6.0 banner alone
// would hard-error the verbatim sources.
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
// CIFIX-6: official ClientCore uses swiftSettings: [.defaultIsolation(MainActor.self)]
// (ios/Package.swift, tools 6.2). AAV2 verbatim files assume MainActor default isolation —
// without it TimelineGrouping.swift:12 ($0.structure.status.isActive) and every
// @Observable model property reference fails to type-check under Xcode 26.2 / Swift 6.2.
// .defaultIsolation is a 6.1+ ManifestAPI and needs a 6.2 banner to even parse — the
// local Linux toolchain is 6.0.3 and enforces no such check, so gate on compiler version.
// unsafeFlags(["-default-isolation","MainActor"]) is the same frontend flag .defaultIsolation
// lowers to (and exactly what the Xcode project passes per-file via COMPILER_FLAGS).
#if swift(>=6.1)
let isolationSettings: [SwiftSetting] = [.unsafeFlags(["-default-isolation", "MainActor"])]
#else
let isolationSettings: [SwiftSetting] = []
#endif

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
            exclude: ["Glue/README.md"],  // doc file in source dir (swift build sanity; harmless elsewhere)
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
                "AAV2/Business/V2SessionPreparationService.swift", // wired 2026-09-20: Xcode 侧目录展开漏编的显式登记（iOS Build 124f73d forensics）
                // P1-CHAT (2026-09-20): 组合根 V2RemoteChatServices（Glue）的依赖闭包补全 —
                // Repositories（scope/restoration/dashboard repo，V2SessionRepository 的同伴）
                // + Models/Session（V2SessionModel，聊天页数据主语）+ Models/Devices
                // （WorkspaceDirectoryModel，官方文件页数据层，SessionChatView 文件按钮依赖）。
                "AAV2/Repositories",
                "AAV2/Models/Session",
                "AAV2/Models/Devices",
                // batch9 (2026-09-20): chat timeline/model layer (SessionChatModel + Timeline 全家
                // + Notice/Toast/Attachment stores + Markdown sizing) — Foundation/Observation-only,
                // 0 iOS18/26 API (verified by scan); consumed by P1 SessionChatView port
                "AAV2/Models/Chat",
                // batch3 (2026-09-15): API/V2 transport-facing layer + WS client
                // (closure of V2APIClient composition root; no UI deps — verified)
                "AAV2/API/V2",
                // batch4 (2026-09-15): auth (v1 mobile-login trio) + session-creation
                // orchestration — closure verified = 0 extra pulls (all deps placed)
                "AAV2/API/APIClient.swift",
                "AAV2/Domain/Account",
                "AAV2/Models/Auth/ServerNetworkPolicy.swift",
                "AAV2/Models/Auth/OAuthCallback.swift", // B8-FIX5r2: 8a closure (OAuthLoginError/OAuthCallback decls)
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
            swiftSettings: isolationSettings
        )
    ],
    swiftLanguageVersions: [.v5]  // pinned to Swift 5 (header note); 6.0 banner would default to v6
)
