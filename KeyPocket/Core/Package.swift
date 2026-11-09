// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "KeyPocketCore", platforms: [.macOS(.v13), .iOS(.v16), .watchOS("11.0")], products: [.library(name: "KeyPocketCore", targets: ["KeyPocketCore"])], targets: [.target(name: "KeyPocketCore"), .testTarget(name: "KeyPocketCoreTests", dependencies: ["KeyPocketCore"])])
