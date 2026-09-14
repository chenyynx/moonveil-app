// swift-tools-version:6.0
import PackageDescription

// Moonveil RemoteKit — isolated SwiftPM package (D4 门1: App→RemoteKit one-way).
// AAV2/ = official AA iOS V2 layer (MIT, verbatim port, AA-ATTRIBUTION.md);
// Glue/ = our only seam work (SessionBackend binding + D1 sqlite adapter + D2 out-seam).
let package = Package(
    name: "RemoteKit",
    platforms: [.iOS(.v18)],
    products: [.library(name: "RemoteKit", targets: ["RemoteKit"])],
    targets: [
        .target(name: "RemoteKit", dependencies: [], path: "Sources/Glue"),
        .target(name: "AAV2", dependencies: [], path: "Sources/AAV2"),
    ]
)
