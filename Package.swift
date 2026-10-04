// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Verger",
    platforms: [.macOS(.v14)],
    targets: [
        // Le contrat Verger <-> Cidre : appels a la CLI `cidre` + parsing JSON.
        // Foundation seul, pour rester testable sans interface.
        .target(name: "CidreBridge", path: "Verger/CidreBridge"),
        .executableTarget(
            name: "Verger",
            dependencies: ["CidreBridge"],
            path: "Verger",
            exclude: ["CidreBridge"]
        ),
        .testTarget(name: "CidreBridgeTests", dependencies: ["CidreBridge"]),
    ]
)
