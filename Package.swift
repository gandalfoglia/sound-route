// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SoundRoute",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SoundRoute",
            path: "Sources/SoundRoute",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
