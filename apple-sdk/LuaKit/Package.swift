// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LuaKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "LuaKit",
            targets: ["LuaKit"]
        ),
    ],
    targets: [
        .target(
            name: "CLua",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .define("LUA_USE_POSIX", .when(platforms: [.macOS, .iOS])),
            ]
        ),
        .target(
            name: "LuaKit",
            dependencies: ["CLua"]
        ),
        .testTarget(
            name: "LuaKitTests",
            dependencies: ["LuaKit"]
        ),
    ]
)

