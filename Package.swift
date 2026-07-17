// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Recavia",
    defaultLocalization: "ja",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Recavia", targets: ["Recavia"]),
        .executable(name: "recavia-mcp", targets: ["RecaviaMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.10.0"),
    ],
    targets: [
        .target(
            name: "RecaviaRuntimeSupport",
            path: "Sources/RecaviaRuntimeSupport"
        ),
        .target(
            name: "RecaviaMeetingAccess",
            dependencies: [
                "RecaviaRuntimeSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/RecaviaMeetingAccess"
        ),
        .executableTarget(
            name: "RecaviaMCP",
            dependencies: ["RecaviaMeetingAccess"],
            path: "Sources/RecaviaMCP"
        ),
        .executableTarget(
            name: "Recavia",
            dependencies: [
                "RecaviaRuntimeSupport",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sentry", package: "sentry-cocoa"),
            ],
            path: "Sources/Recavia",
            exclude: [
                "AGENTS.md",
                "CLAUDE.md",
                "Database/AGENTS.md",
                "Database/CLAUDE.md",
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RecaviaTests",
            dependencies: ["Recavia", "RecaviaMeetingAccess", "RecaviaRuntimeSupport"],
            path: "Tests/RecaviaTests",
            exclude: [
                "AGENTS.md",
                "CLAUDE.md",
            ]
        )
    ]
)
