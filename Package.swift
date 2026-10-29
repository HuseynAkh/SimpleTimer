// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SimpleTimerCore", products: [.library(name: "TimerCore", targets: ["TimerCore"])], targets: [.target(name: "TimerCore", path: "Core"), .testTarget(name: "TimerCoreTests", dependencies: ["TimerCore"], path: "Tests/TimerCoreTests")])
