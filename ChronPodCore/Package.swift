// swift-tools-version:5.9
// ChronPodCore — platform-neutral logic for ChronPod (feeds, OPML, search,
// Google News link resolution). Kept free of UIKit/SwiftUI so it can be unit
// tested with `swift test` on the GitHub macOS build machine.
import PackageDescription

let package = Package(
    name: "ChronPodCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ChronPodCore", targets: ["ChronPodCore"])
    ],
    targets: [
        .target(name: "ChronPodCore"),
        .testTarget(name: "ChronPodCoreTests", dependencies: ["ChronPodCore"])
    ]
)
