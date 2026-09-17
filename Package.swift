// swift-tools-version: 5.9
import PackageDescription

// Bağımlılık yok: PTY için Darwin, render için WebKit, arayüz için SwiftUI/AppKit.
// xterm.js Resources/vendor altında statik dosya olarak taşınıyor, SPM paketi değil.
// Resources hedefin İÇİNDE olmak zorunda; dışarıdaysa SPM uyarı vermeden atlar
// ve Bundle.module hiç üretilmez.
let package = Package(
    name: "Reeve",
    platforms: [.macOS(.v14)],   // @Observable macOS 14+ istiyor
    targets: [
        .executableTarget(
            name: "Reeve",
            path: "Sources/Reeve",
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "ReeveTests", dependencies: ["Reeve"])
    ]
)
