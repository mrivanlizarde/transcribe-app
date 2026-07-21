// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hark",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TranscribeCore", targets: ["TranscribeCore"]),
        .executable(name: "Hark", targets: ["Hark"]),
        .executable(name: "diarize-proto", targets: ["diarize-proto"]),
        .executable(name: "make-icon", targets: ["make-icon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
    ],
    targets: [
        .target(
            name: "TranscribeCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .executableTarget(name: "Hark", dependencies: ["TranscribeCore"]),
        .executableTarget(name: "diarize-proto", dependencies: ["TranscribeCore"]),
        .executableTarget(name: "make-icon"),
    ]
)
