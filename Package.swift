// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CloseYourLaptop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CloseYourLaptop", targets: ["CloseYourLaptop"]),
        .executable(name: "CloseYourLaptopWatcher", targets: ["CloseYourLaptopWatcher"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .target(name: "CloseYourLaptopCore"),
        .executableTarget(
            name: "CloseYourLaptop",
            dependencies: [
                "CloseYourLaptopCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .executableTarget(
            name: "CloseYourLaptopWatcher",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "CloseYourLaptopCoreTests",
            dependencies: ["CloseYourLaptopCore"]
        )
    ]
)
