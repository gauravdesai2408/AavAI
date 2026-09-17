// swift-tools-version: 6.2
import PackageDescription
import Foundation

let developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? ProcessInfo.processInfo.environment["XCODE_DEVELOPER_DIR_PATH"]
    ?? "/Library/Developer/CommandLineTools"
let developerFrameworks = "\(developerDirectory)/Library/Developer/Frameworks"
let developerLibraries = "\(developerDirectory)/Library/Developer/usr/lib"

let package = Package(
    name: "AavAI",
    platforms: [.macOS(.v14), .iOS(.v26)],
    products: [.executable(name: "AavAI", targets: ["AavAI"]),
               .executable(name: "aavai-native-eval", targets: ["AavAINativeEval"]),
               .library(name: "AavAICore", targets: ["AavAICore"])],
    targets: [
        .target(name: "AavAICore"),
        .executableTarget(name: "AavAINativeEval", dependencies: ["AavAICore"]),
        .executableTarget(name: "AavAI", dependencies: ["AavAICore"]),
        .testTarget(
            name: "AavAITests",
            dependencies: ["AavAI"],
            swiftSettings: [.unsafeFlags(["-F", developerFrameworks])],
            linkerSettings: [
                .unsafeFlags([
                    "-F", developerFrameworks,
                    "-Xlinker", "-rpath",
                    "-Xlinker", developerFrameworks,
                    "-Xlinker", "-rpath",
                    "-Xlinker", developerLibraries
                ])
            ]
        )
    ]
)
