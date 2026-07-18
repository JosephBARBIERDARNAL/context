// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Context",
    platforms: [.macOS(.v26)],
    targets: [
        // Generated UniFFI C header + modulemap (see `just bindings`).
        .target(name: "ContextCoreFFI"),
        // Generated UniFFI Swift bindings.
        .target(name: "ContextCore", dependencies: ["ContextCoreFFI"]),
        .executableTarget(
            name: "Context",
            dependencies: ["ContextCore"],
            linkerSettings: [
                .unsafeFlags(["-L", "../core/target/release"]),
                .linkedLibrary("context_core"),
            ]
        ),
    ]
)
