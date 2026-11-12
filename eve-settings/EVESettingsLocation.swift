//
//  EVESettingsLocation.swift
//  eve-operator
//
//  Finding, validating and enumerating EVE's local settings folder — the directory holding
//  `settings_<Profile>/core_char_*.dat`. See `docs/eve-settings-files.md` §1.
//

import Foundation

nonisolated enum EVESettingsLocation {

    /// Where the client keeps every install's settings, one mangled-path directory each.
    static let root = ("~/Library/Application Support/CCP/EVE" as NSString).expandingTildeInPath

    /// Profile EVE creates on a fresh install, and the one we assume until told otherwise.
    static let defaultProfile = "Default"

    /// A settings folder is one holding a `settings_Default` directory. That is also what
    /// tells the real thing apart from the sibling stub folder EVE leaves behind, which
    /// contains only `settings/` with a couple of placeholder files in it.
    static func isValid(_ path: String) -> Bool {
        !path.isEmpty && isDirectory(profileDirectory(in: path, profile: defaultProfile))
    }

    static func profileDirectory(in path: String, profile: String) -> String {
        (path as NSString).appendingPathComponent("settings_\(profile)")
    }

    /// The profile names present, newest first is not attempted — alphabetical, with
    /// `Default` pulled to the front because it is the one almost everyone is using.
    static func profiles(in path: String) -> [String] {
        guard !path.isEmpty else { return [] }
        let children = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        let found =
            children
            .filter { $0.hasPrefix("settings_") }
            .filter { isDirectory((path as NSString).appendingPathComponent($0)) }
            .map { String($0.dropFirst("settings_".count)) }
            .filter { !$0.isEmpty }
            .sorted()
        guard found.contains(defaultProfile) else { return found }
        return [defaultProfile] + found.filter { $0 != defaultProfile }
    }

    // MARK: - Autodetect

    enum DetectionFailure: Error, CustomStringConvertible {
        /// EVE has never run on this machine, or ran under a different user.
        case rootMissing
        /// `CCP/EVE` exists but nothing under it holds a `settings_Default`.
        case noProfilesFound

        var description: String {
            switch self {
            case .rootMissing: return "No EVE settings in ~/Library/Application Support/CCP/EVE"
            case .noProfilesFound: return "Nothing in CCP/EVE looks like a settings folder"
            }
        }
    }

    struct Detection {
        let path: String
        /// True when the folder was found by scanning rather than derived from the configured
        /// client, so the UI can admit that it made a choice.
        let wasGuessed: Bool
    }

    /// Finds the settings folder belonging to the client at `bundlePath`.
    ///
    /// The folder's name is the install path with `/`, `:` and spaces replaced by `_` and the
    /// whole thing lowercased, so the first attempt derives the name outright. That is both
    /// the fast path and the unambiguous one: with Tranquility and Singularity both installed
    /// it picks the shard the rest of the app is pointed at, rather than whichever was touched
    /// most recently.
    static func autodetect(bundlePath: String) -> Result<Detection, DetectionFailure> {
        guard isDirectory(root) else { return .failure(.rootMissing) }

        let derived = (root as NSString).appendingPathComponent(mangled(bundlePath: bundlePath))
        if isValid(derived) { return .success(Detection(path: derived, wasGuessed: false)) }

        let candidates =
            ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
            .map { (root as NSString).appendingPathComponent($0) }
            .filter(isValid)

        guard !candidates.isEmpty else { return .failure(.noProfilesFound) }
        if candidates.count == 1 {
            return .success(Detection(path: candidates[0], wasGuessed: false))
        }

        // Several installs and none of them the configured one: the most recently written
        // profile is the best guess available, and the UI says that a guess was made.
        let newest = candidates.max { lhs, rhs in
            modificationDate(of: profileDirectory(in: lhs, profile: defaultProfile))
                < modificationDate(of: profileDirectory(in: rhs, profile: defaultProfile))
        }
        return .success(Detection(path: newest ?? candidates[0], wasGuessed: true))
    }

    /// EVE's own mangling of an install path into a directory name.
    static func mangled(bundlePath: String) -> String {
        let full = (bundlePath as NSString)
            .appendingPathComponent("Contents/Resources/build/tranquility")
        return String(
            full.lowercased().map { character in
                character == "/" || character == ":" || character == " " ? "_" : character
            })
    }

    // MARK: - Access

    enum Access: Equatable {
        case ok
        case notConfigured
        case notASettingsFolder
        /// The folder is there and shaped right, but the filesystem said no. This is the one
        /// case where a real macOS permission could be involved.
        case denied(String)
        case empty
    }

    /// Whether the configured folder can actually be read, established by listing the chosen
    /// profile and opening one file — a `fileExists` check would pass under a TCC denial.
    static func checkAccess(path: String, profile: String) -> Access {
        guard !path.isEmpty else { return .notConfigured }
        guard isValid(path) else { return .notASettingsFolder }

        let directory = profileDirectory(in: path, profile: profile)
        let children: [String]
        do {
            children = try FileManager.default.contentsOfDirectory(atPath: directory)
        } catch {
            return .denied(error.localizedDescription)
        }

        guard
            let probe = children.first(where: {
                $0.hasPrefix("core_") && $0.hasSuffix(".dat")
            })
        else { return .empty }

        let file = (directory as NSString).appendingPathComponent(probe)
        guard let handle = FileHandle(forReadingAtPath: file) else {
            return .denied("Could not open \(probe)")
        }
        try? handle.close()
        return .ok
    }

    // MARK: - Enumeration

    /// Full paths of the `core_char_<id>.dat` files in a profile, paired with the character
    /// ID in the name. The placeholder files EVE leaves behind — `core_char__.dat` and
    /// `core_char_('char', None, 'dat').dat` — have no numeric ID and drop out here.
    static func characterFiles(in directory: String) -> [(id: Int64, path: String)] {
        numberedFiles(in: directory, prefix: "core_char_")
    }

    /// The same for `core_user_<accountID>.dat`.
    static func accountFiles(in directory: String) -> [(id: Int64, path: String)] {
        numberedFiles(in: directory, prefix: "core_user_")
    }

    private static func numberedFiles(
        in directory: String, prefix: String
    ) -> [(id: Int64, path: String)] {
        let children = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return
            children
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".dat") }
            .compactMap { name in
                let middle = name.dropFirst(prefix.count).dropLast(".dat".count)
                guard let id = Int64(middle) else { return nil }
                return (id, (directory as NSString).appendingPathComponent(name))
            }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Filesystem

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    private static func modificationDate(of path: String) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }
}
