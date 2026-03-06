// swift-tools-version: 6.0
// IPMsgX — Modern Swift macOS IP Messenger

import PackageDescription

let package = Package(
    name: "IPMsgX",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "IPMsgX",
            path: "IPMsgX",
            exclude: [
                "Resources/Info.plist",
                "Resources/IPMsgX.entitlements",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .process("Resources/en.lproj"),
                .process("Resources/ja.lproj"),
                .copy("Resources/AppIcon.png"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("Network"),
            ]
        )
    ]
)
