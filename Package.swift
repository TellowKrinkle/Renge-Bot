// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "Renge",
	dependencies: [
		// Dependencies declare other packages that this package depends on.
		.package(url: "https://github.com/nuclearace/SwiftDiscord.git", from: "5.0.0"),
		.package(url: "https://github.com/glessard/swift-atomics.git", from: "4.0.0")
	],
	targets: [
		// Targets are the basic building blocks of a package. A target can define a module or a test suite.
		// Targets can depend on other targets in this package, and on products in packages which this package depends on.
		.target(
			name: "Renge",
			dependencies: ["SwiftDiscord", "Atomics"]
		),
		.target(
			name: "RengeMain",
			dependencies: ["Renge"]
		),
		.testTarget(
			name: "RengeTests",
			dependencies: ["Renge"]
		)
	]
)
