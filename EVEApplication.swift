//
//  EVEApplication.swift
//  eve-operator
//
//  Describes the application whose windows this app operates on.
//

import AppKit

/// The application eve-operator attaches to.
enum EVEApplication {

    /// Location of the EVE Online client bundle, as chosen in Settings → Other.
    static var bundlePath: String { OverlaySettings.shared.eveBundlePath }

    static var bundleURL: URL { resolved.url }

    /// Read from the bundle on disk; `nil` when EVE is not installed at `bundlePath`.
    static var bundleIdentifier: String? { resolved.identifier }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: bundlePath)
    }

    // MARK: - Resolving the configured path

    /// Everything `classify` needs about the configured bundle. Reading `Info.plist` and
    /// resolving symlinks both touch the disk, and the answers are wanted on every poll, so
    /// they are worked out once per path rather than once per question.
    private struct Resolved {
        let path: String
        let url: URL
        let canonicalURL: URL
        let identifier: String?
    }

    private static var cache: Resolved?

    /// Recomputed whenever the setting changes, taking the scan and every verdict with it:
    /// those were reached against a bundle this app is no longer attached to.
    private static var resolved: Resolved {
        let path = bundlePath
        if let cache, cache.path == path { return cache }

        let url = URL(fileURLWithPath: path)
        let resolved = Resolved(
            path: path,
            url: url,
            canonicalURL: canonical(url),
            identifier: Bundle(url: url)?.bundleIdentifier)

        cache = resolved
        scan = nil
        verdicts = [:]

        return resolved
    }

    // MARK: - Running clients

    /// The last scan, held until it can have gone stale — see `processIdentifiers()`.
    private static var scan: Set<pid_t>?

    /// Whether a pid is a client. A process cannot change bundle, so this is decided once.
    private static var verdicts: [pid_t: Bool] = [:]

    /// Every running process launched from `bundleURL` (EVE supports multiple concurrent clients).
    ///
    /// Scanning for them is expensive. `NSWorkspace` hands out fresh `NSRunningApplication`
    /// instances on every access, and `processIdentifier`, `bundleURL` and `bundleIdentifier` are
    /// all fetched lazily through `_LSCopyApplicationInformation`, a synchronous XPC round-trip to
    /// LaunchServices — so one scan is several hundred round-trips, there being 139 processes on
    /// this machine, plus a `realpath` of every bundle path it finds. `OperatorModel` polls five
    /// times a second, which measured 10% CPU with no clients running at all: the poll has to get
    /// this far before it can tell that there is nothing to do.
    ///
    /// The answer only changes when an application launches or quits, which is a human-paced
    /// event, so it is scanned once and then held until `NSWorkspace` says otherwise. Polling is
    /// free in the steady state.
    static func processIdentifiers() -> Set<pid_t> {
        _ = watcher
        // Before the early return, and only once per scan: a changed setting drops both the
        // held scan and the verdict table, and the loop below must see one settled bundle.
        let bundle = resolved
        if let scan { return scan }

        let running = NSWorkspace.shared.runningApplications
        var current: [pid_t: Bool] = Dictionary(minimumCapacity: running.count)
        var identifiers: Set<pid_t> = []

        for app in running {
            let pid = app.processIdentifier
            // An undecidable process is left out of the table rather than recorded, so it is
            // looked at again on the next scan.
            guard let isEVE = verdicts[pid] ?? classify(app, against: bundle) else { continue }
            current[pid] = isEVE
            if isEVE { identifiers.insert(pid) }
        }

        // The table is keyed on pid, so entries for processes that have exited have to go: it
        // would otherwise grow for the life of the app, and a recycled pid would inherit the
        // verdict of whatever held it before.
        verdicts = current
        scan = identifiers

        return identifiers
    }

    /// Drops the scan whenever an application launches or quits. Installed on first use, and a
    /// `static let` so that happens exactly once.
    ///
    /// A notification missed for some other application would only mean eve-operator goes on
    /// ignoring a process it is already ignoring; EVE clients are ordinary foreground
    /// applications, and `NSWorkspace` always announces those.
    private static let watcher: Void = {
        let centre = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            centre.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { scan = nil }
            }
        }
    }()

    /// `nil` when the process reports no bundle at all, which means LaunchServices does not know
    /// about it yet; recording that as a "no" would be wrong for the rest of its life. No process
    /// on a normal desktop is in that state for long, so re-asking costs nothing in practice.
    private static func classify(_ app: NSRunningApplication, against bundle: Resolved) -> Bool? {
        let url = app.bundleURL
        let identifier = app.bundleIdentifier
        guard url != nil || identifier != nil else { return nil }

        if let url, canonical(url) == bundle.canonicalURL { return true }
        // Fall back to the bundle id so clients launched from a copy/symlink are still found.
        return bundle.identifier != nil && identifier == bundle.identifier
    }

    private static func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}
