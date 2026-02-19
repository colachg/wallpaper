// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Wallpaper",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Wallpaper"
        ),
        .testTarget(
            name: "WallpaperTests",
            dependencies: ["Wallpaper"]
        ),
    ]
)
