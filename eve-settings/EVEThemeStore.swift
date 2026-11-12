//
//  EVEThemeStore.swift
//  eve-operator
//
//  Reads the custom UI colour theme each character has selected, out of EVE's own settings
//  files. Read-only: nothing here ever writes to EVE's folder.
//
//  EVE holds these settings in memory while it runs and only writes them out on logout or a
//  profile switch, so a theme changed in-game shows up here late. That is not something this
//  side can fix; the Labels tab says so.
//
//  Nothing re-reads on a timer, on a file-system event or on app activation. The folder is
//  read once at launch, whenever the configured folder or profile changes, and otherwise only
//  when the user asks for it — "Update theme colors" in the Labels tab.
//

import Foundation
import Observation
import SwiftUI
import os

@MainActor
@Observable
final class EVEThemeStore {

    static let shared = EVEThemeStore()

    nonisolated enum Status: Equatable, Sendable {
        case notConfigured
        case loading
        /// Read successfully at this moment, finding this many characters.
        case ok
        case failed(String)
    }

    /// Every character the profile has a file for, with the theme it selected. A character
    /// using one of EVE's built-in themes is absent: we do not reproduce stock palettes.
    private(set) var themesByCharacterID: [Int64: EVETheme] = [:]

    /// Every `core_char_<id>.dat` in the profile, themed or not. The Labels tab offers these
    /// when an ESI lookup could not say which ID a character name belongs to.
    private(set) var knownCharacterIDs: [Int64] = []

    private(set) var status: Status = .notConfigured

    private let settings = OverlaySettings.shared

    @ObservationIgnored private var cache: [String: CacheEntry] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    @ObservationIgnored nonisolated private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "eve-operator", category: "eve-settings")

    private init() {
        // The folder's name is derived from wherever EVE was installed, so there is no
        // sensible default to ship — the common case is made to need no interaction instead.
        if settings.eveSettingsFolderPath.isEmpty { autodetect() }

        reload()
    }

    // MARK: - Colours

    func theme(forCharacterID id: Int64) -> EVETheme? {
        themesByCharacterID[id]
    }

    func color(forCharacterID id: Int64) -> Color? {
        themesByCharacterID[id]?.color
    }

    // MARK: - Loading

    /// Re-reads the configured profile. Safe to call repeatedly: unchanged files come out of
    /// a cache keyed on size and modification date, so a no-op reload costs one `stat` each.
    ///
    /// Called at launch, when the folder or profile changes, and from the Labels tab's
    /// "Update theme colors" button. Never from a timer or from the strip's poll.
    func reload() {
        let folder = settings.eveSettingsFolderPath
        let profile = settings.eveSettingsProfile

        guard !folder.isEmpty else {
            loadTask?.cancel()
            themesByCharacterID = [:]
            knownCharacterIDs = []
            if status != .notConfigured { status = .notConfigured }
            return
        }

        // Only announced for the very first read. Every later one is served from the cache
        // unless a file actually changed, so "Reading…" would be a flicker nobody can read.
        if status == .notConfigured { status = .loading }

        loadTask?.cancel()
        let cache = cache
        loadTask = Task { [weak self] in
            // Off the main actor: the largest of these files is about 100 KB, so this is
            // about never blocking the strip rather than about speed.
            let outcome = await Task.detached(priority: .utility) {
                Self.load(folder: folder, profile: profile, cache: cache)
            }.value

            guard !Task.isCancelled, let self else { return }
            self.cache = outcome.cache
            if self.themesByCharacterID != outcome.themesByCharacterID {
                self.themesByCharacterID = outcome.themesByCharacterID
            }
            if self.knownCharacterIDs != outcome.characterIDs {
                self.knownCharacterIDs = outcome.characterIDs
            }
            if self.status != outcome.status { self.status = outcome.status }
        }
    }

    /// Writes the detected folder into settings, or leaves it empty and says why.
    @discardableResult
    func autodetect() -> Result<EVESettingsLocation.Detection, EVESettingsLocation.DetectionFailure>
    {
        let result = EVESettingsLocation.autodetect(bundlePath: settings.eveBundlePath)
        if case .success(let detection) = result, settings.eveSettingsFolderPath != detection.path {
            settings.eveSettingsFolderPath = detection.path
        }
        return result
    }

    // MARK: - Parsing

    nonisolated private struct CacheEntry: Sendable {
        let size: Int
        let modified: Date
        /// Themes this file defines, for a `core_user_*.dat`.
        let themes: [EVETheme]
        /// The theme GUID this file selects, for a `core_char_*.dat`.
        let selectedThemeID: String?
    }

    nonisolated private struct Parsed: Sendable {
        var themes: [EVETheme] = []
        var selectedThemeID: String?
    }

    nonisolated private struct Outcome: Sendable {
        let themesByCharacterID: [Int64: EVETheme]
        let characterIDs: [Int64]
        let status: Status
        let cache: [String: CacheEntry]
    }

    private nonisolated static func load(
        folder: String, profile: String, cache: [String: CacheEntry]
    ) -> Outcome {
        switch EVESettingsLocation.checkAccess(path: folder, profile: profile) {
        case .notConfigured:
            return Outcome(
                themesByCharacterID: [:], characterIDs: [], status: .notConfigured, cache: [:])
        case .notASettingsFolder:
            return Outcome(
                themesByCharacterID: [:], characterIDs: [],
                status: .failed("No settings_Default in this folder"), cache: [:])
        case .denied(let reason):
            return Outcome(
                themesByCharacterID: [:], characterIDs: [], status: .failed(reason), cache: [:])
        case .empty, .ok:
            break
        }

        let directory = EVESettingsLocation.profileDirectory(in: folder, profile: profile)
        var fresh: [String: CacheEntry] = [:]

        // Themes live in the account files, the selection in the character files, and a GUID
        // is unique, so merging every account's palettes is enough — there is no need to work
        // out which account a character belongs to.
        var palettes: [String: EVETheme] = [:]
        for file in EVESettingsLocation.accountFiles(in: directory) {
            guard let entry = entry(for: file.path, cached: cache[file.path], parse: themes(in:))
            else { continue }
            fresh[file.path] = entry
            for theme in entry.themes { palettes[theme.id] = theme }
        }

        var themesByCharacterID: [Int64: EVETheme] = [:]
        var characterIDs: [Int64] = []
        for file in EVESettingsLocation.characterFiles(in: directory) {
            characterIDs.append(file.id)
            guard
                let entry = entry(for: file.path, cached: cache[file.path], parse: selection(in:))
            else { continue }
            fresh[file.path] = entry

            guard let guid = entry.selectedThemeID else { continue }
            if let theme = palettes[guid] {
                themesByCharacterID[file.id] = theme
            } else {
                // A theme defined on an account whose file is not in this profile. Nothing to
                // mirror, and guessing EVE's built-in palettes would be a fabrication.
                log.debug("character \(file.id) selects unknown theme \(guid, privacy: .public)")
            }
        }

        return Outcome(
            themesByCharacterID: themesByCharacterID,
            characterIDs: characterIDs,
            status: .ok,
            cache: fresh)
    }

    /// Returns the cached parse when the file has not changed, otherwise decodes it. A file
    /// that fails to decode yields `nil` rather than failing the whole read: one unreadable
    /// `.dat` should not cost the user every other character's colour.
    private nonisolated static func entry(
        for path: String, cached: CacheEntry?, parse: (MarshalValue) -> Parsed
    ) -> CacheEntry? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
        let modified = attributes?[.modificationDate] as? Date ?? .distantPast

        if let cached, cached.size == size, cached.modified == modified { return cached }

        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        do {
            let decoded = try BlueMarshal.decode(data)
            let parsed = parse(decoded)
            return CacheEntry(
                size: size, modified: modified,
                themes: parsed.themes, selectedThemeID: parsed.selectedThemeID)
        } catch {
            log.notice(
                "could not decode \((path as NSString).lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private nonisolated static func themes(in file: MarshalValue) -> Parsed {
        let list = file["ui"]?["custom_color_themes"]?.settingValue?["themes"]?.arrayValue ?? []
        return Parsed(themes: list.compactMap(EVETheme.init))
    }

    private nonisolated static func selection(in file: MarshalValue) -> Parsed {
        Parsed(selectedThemeID: file["windows"]?["wndColorThemeID"]?.settingValue?.textValue)
    }
}
