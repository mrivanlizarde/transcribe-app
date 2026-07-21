// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "transcribe-app",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TranscribeCore", targets: ["TranscribeCore"]),
        .executable(name: "diarize-proto", targets: ["diarize-proto"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
    ],
    targets: [
        .target(
            name: "TranscribeCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .executableTarget(name: "diarize-proto", dependencies: ["TranscribeCore"]),
    ]
)
