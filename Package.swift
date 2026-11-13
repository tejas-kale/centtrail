// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Centtrail",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(name: "Ledger", targets: ["Ledger"]),
    ],
    targets: [
        .target(
            name: "Ledger",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "LedgerTests",
            dependencies: ["Ledger"],
            swiftSettings: [
                // Swift Build drops TestingMacros for this package unless the
                // plugin is named on the test target. `swift test` needs it to
                // expand @Test.
                .unsafeFlags([
                    "-load-plugin-library",
                    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib",
                ]),
            ]
        ),
    ]
)
