// swift-tools-version:5.9
import PackageDescription

// Open-core layout: Sources/ is MIT (see LICENSE); assets/ holds the characters and is
// licensed separately (see assets/LICENSE.md) so character packs can be sold later.
let package = Package(
    name: "TokenPet",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "TokenPetAssets",
            path: "assets",
            exclude: ["LICENSE.md", "PROVENANCE.md", "archive"]
        ),
        .executableTarget(name: "YugongSheet", dependencies: ["TokenPetAssets"], path: "Sources/YugongSheet"),
        .executableTarget(name: "TokenPet", dependencies: ["TokenPetAssets"], path: "Sources/TokenPet"),
    ]
)
