// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CappitolianHttpLocalServerSwifter",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CappitolianHttpLocalServerSwifter",
            targets: ["HttpLocalServerSwifterPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0"),
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "HttpLocalServerSwifterPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .product(name: "Swifter", package: "swifter")
            ],
            path: "ios/Sources/HttpLocalServerSwifterPlugin"),
        .testTarget(
            name: "HttpLocalServerSwifterPluginTests",
            dependencies: ["HttpLocalServerSwifterPlugin"],
            path: "ios/Tests/HttpLocalServerSwifterPluginTests")
    ]
)