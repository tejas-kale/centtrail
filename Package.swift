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
        .library(name: "Interpreter", targets: ["Interpreter"]),
        .library(name: "CenttrailShell", targets: ["CenttrailShell"]),
        .executable(name: "Centtrail", targets: ["CenttrailMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.9.0"),
    ],
    targets: [
        .target(
            name: "Ledger",
            dependencies: [
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .target(
            name: "Interpreter",
            dependencies: ["Ledger"]
        ),
        .target(
            name: "CenttrailShell",
            dependencies: ["Ledger", "Interpreter"]
        ),
        .executableTarget(
            name: "CenttrailMac",
            dependencies: ["CenttrailShell"]
        ),
        .testTarget(
            name: "LedgerTests",
            dependencies: ["Ledger", "Interpreter"],
            resources: [
                .copy("Fixtures"),
            ],
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
