// swift-tools-version:5.9
// GossipCore = pure Swift game rules (no Apple UI frameworks, builds on Linux); coretest = parity check against the web sim.js.
// The iOS app is in App/ (XcodeGen, project.yml).
import PackageDescription
let package = Package(
  name: "GossipCore",
  products: [.library(name: "GossipCore", targets: ["GossipCore"])],
  targets: [
    .target(name: "GossipCore", path: "Sources/GossipCore"),
    .executableTarget(name: "coretest", dependencies: ["GossipCore"], path: "Sources/coretest"),
  ]
)
