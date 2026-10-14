// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VideoWallpaper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "VideoWallpaper", targets: ["VideoWallpaperApp"]),
               .executable(name: "WallFlowPlayer", targets: ["WallFlowPlayer"])],
    targets: [
        .target(name: "WallpaperCore"),
        .target(name: "WallpaperRuntime", dependencies: ["WallpaperCore"]),
        .executableTarget(name: "VideoWallpaperApp", dependencies: ["WallpaperCore", "WallpaperRuntime"]),
        .executableTarget(name: "WallFlowPlayer", dependencies: ["WallpaperCore", "WallpaperRuntime"]),
        .testTarget(name: "WallpaperCoreTests", dependencies: ["WallpaperCore"]),
        .testTarget(name: "WallpaperRuntimeTests", dependencies: ["WallpaperRuntime", "WallpaperCore"])
    ],
    swiftLanguageModes: [.v5]
)
