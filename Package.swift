// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "open-bot-avatar-swift",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OpenBotAvatar", targets: ["OpenBotAvatar"]),
        .library(name: "OpenBotAvatarUI", targets: ["OpenBotAvatarUI"])
    ],
    targets: [
        .target(name: "OpenBotAvatar"),
        .target(name: "OpenBotAvatarUI", dependencies: ["OpenBotAvatar"])
    ]
)
