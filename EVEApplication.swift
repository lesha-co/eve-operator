//
//  EVEApplication.swift
//  eve-operator
//
//  Describes the application whose windows this app operates on.
//

import AppKit

/// The application eve-operator attaches to.
enum EVEApplication {

    /// Location of the EVE Online client bundle.
    static let bundlePath =
        ("~/Library/Application Support/EVE Online/SharedCache/tq/EVE.app" as NSString)
        .expandingTildeInPath

    static let bundleURL = URL(fileURLWithPath: bundlePath)

    /// Read from the bundle on disk; `nil` when EVE is not installed at `bundlePath`.
    static let bundleIdentifier: String? = Bundle(url: bundleURL)?.bundleIdentifier

    static let displayName = "EVE Online"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: bundlePath)
    }

    /// Every running process launched from `bundleURL` (EVE supports multiple concurrent clients).
    static func runningInstances() -> [NSRunningApplication] {
        let target = canonical(bundleURL)
        return NSWorkspace.shared.runningApplications.filter { app in
            if let url = app.bundleURL, canonical(url) == target { return true }
            // Fall back to the bundle id so clients launched from a copy/symlink are still found.
            return bundleIdentifier != nil && app.bundleIdentifier == bundleIdentifier
        }
    }

    static func processIdentifiers() -> Set<pid_t> {
        Set(runningInstances().map(\.processIdentifier))
    }

    private static func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}
