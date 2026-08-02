import Foundation

private final class ResourceBundleFinder {}

extension Bundle {
    /// Resources ship in the SwiftPM-generated `Kvist_Kvist.bundle`, which sits in
    /// `Contents/Resources` inside the packaged app, beside the binary in a plain
    /// build directory, and beside the `.xctest` bundle under `swift test`. The
    /// accessor SwiftPM generates for executable targets only looks beside the
    /// binary — relative to `Bundle.main.bundleURL`, which for an app is the `.app`
    /// itself — so it misses the packaged layout and traps. Falling back to `.main`
    /// keeps a missing bundle to missing icons rather than a crash on launch; every
    /// call site already tolerates absent resources.
    static nonisolated let kvistResources: Bundle = {
        let bundleName = "Kvist_Kvist.bundle"
        let hostBundle = Bundle(for: ResourceBundleFinder.self)
        let searchDirectories = [
            main.resourceURL,
            main.bundleURL,
            main.executableURL?.deletingLastPathComponent(),
            hostBundle.resourceURL,
            hostBundle.bundleURL.deletingLastPathComponent()
        ]
        for case let directory? in searchDirectories {
            if let bundle = Bundle(url: directory.appendingPathComponent(bundleName)) {
                return bundle
            }
        }
        return main
    }()
}
