//
//  CharacterRoster.swift
//  eve-operator
//
//  Every character this app has seen, by name, and — where it could be worked out — the
//  character ID that names the settings file holding that character's colour theme.
//
//  Window titles give a name; `core_char_<id>.dat` gives an ID; nothing on disk joins the
//  two. The `.dat` files do not carry the character's name, and neither the launcher's
//  `launcher-data.json` nor its `state.json` does either — all three were checked. So the
//  join goes through ESI's public name-to-ID endpoint, once per never-before-seen name, with
//  a manual assignment as the fallback when that is unavailable.
//

import Foundation
import Observation
import os

@MainActor
@Observable
final class CharacterRoster {

    static let shared = CharacterRoster()

    nonisolated enum Resolution: Equatable, Sendable {
        /// Not looked up yet.
        case pending
        case resolving
        case resolved
        /// Looked up and failed; the row offers manual assignment instead of retrying.
        case failed(String)
    }

    struct Entry: Identifiable, Equatable {
        let name: String
        var characterID: Int64?
        var isOnline: Bool
        var resolution: Resolution

        var id: String { name }
    }

    /// Names first seen most recently last, so the list does not reshuffle under the pointer.
    private(set) var characters: [Entry] = []

    private let defaults: UserDefaults

    /// Character IDs never change, so a successful lookup is cached for good.
    @ObservationIgnored private var identifiers: [String: Int64] {
        didSet { defaults.set(identifiers.mapValues(NSNumber.init(value:)), forKey: Key.ids) }
    }

    /// Names currently on screen, kept so `note(_:)` can return without touching anything on
    /// the overwhelming majority of polls.
    @ObservationIgnored private var onlineNames: Set<String> = []

    @ObservationIgnored private var resolveTask: Task<Void, Never>?

    @ObservationIgnored nonisolated private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "eve-operator", category: "roster")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.identifiers =
            (defaults.dictionary(forKey: Key.ids) as? [String: NSNumber])?
            .mapValues(\.int64Value) ?? [:]

        let remembered = defaults.stringArray(forKey: Key.names) ?? []
        characters = remembered.map {
            Entry(
                name: $0, characterID: identifiers[$0], isOnline: false,
                resolution: identifiers[$0] == nil ? .pending : .resolved)
        }
    }

    // MARK: - Live windows

    /// Called from `OperatorModel.refresh`, which runs five times a second. Everything past
    /// the first comparison only happens when a client has actually come or gone.
    func note(_ windows: [EVEWindow]) {
        let names = Set(windows.compactMap(\.characterName))
        guard names != onlineNames else { return }
        onlineNames = names

        let known = Set(characters.map(\.name))
        let appeared = names.subtracting(known).sorted()

        for index in characters.indices {
            characters[index].isOnline = names.contains(characters[index].name)
        }
        for name in appeared {
            characters.append(
                Entry(
                    name: name, characterID: identifiers[name], isOnline: true,
                    resolution: identifiers[name] == nil ? .pending : .resolved))
        }

        if !appeared.isEmpty {
            defaults.set(characters.map(\.name), forKey: Key.names)
            resolvePending()
        }
    }

    // MARK: - Editing

    func assign(id: Int64, to name: String) {
        identifiers[name] = id
        update(name) {
            $0.characterID = id
            $0.resolution = .resolved
        }
    }

    func forget(_ name: String) {
        characters.removeAll { $0.name == name }
        identifiers[name] = nil
        defaults.set(characters.map(\.name), forKey: Key.names)
    }

    /// Retries every unresolved name. Only ever called from a button — a failed lookup is
    /// never retried on a timer.
    func resolvePending() {
        let unresolved = characters.filter { $0.characterID == nil }.map(\.name)
        guard !unresolved.isEmpty, resolveTask == nil else { return }

        for name in unresolved { update(name) { $0.resolution = .resolving } }

        resolveTask = Task { [weak self] in
            defer { self?.resolveTask = nil }
            do {
                let found = try await ESI.characterIDs(for: unresolved)
                guard let self else { return }
                for name in unresolved {
                    if let id = found[name] {
                        self.identifiers[name] = id
                        self.update(name) {
                            $0.characterID = id
                            $0.resolution = .resolved
                        }
                    } else {
                        self.update(name) { $0.resolution = .failed("Not found on Tranquility") }
                    }
                }
            } catch {
                Self.log.notice(
                    "ESI name lookup failed: \(error.localizedDescription, privacy: .public)")
                guard let self else { return }
                let reason = error.localizedDescription
                for name in unresolved { self.update(name) { $0.resolution = .failed(reason) } }
            }
        }
    }

    private func update(_ name: String, _ change: (inout Entry) -> Void) {
        guard let index = characters.firstIndex(where: { $0.name == name }) else { return }
        var entry = characters[index]
        change(&entry)
        guard entry != characters[index] else { return }
        characters[index] = entry
    }

    private enum Key {
        static let names = "roster.characters"
        static let ids = "roster.characterIDs"
    }
}

// MARK: - ESI

/// The one network call this app makes, and only for a character name it has never seen.
nonisolated enum ESI {

    private static let endpoint = URL(
        string: "https://esi.evetech.net/latest/universe/ids/?datasource=tranquility")!

    static func characterIDs(for names: [String]) async throws -> [String: Int64] {
        guard !names.isEmpty else { return [:] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // ESI asks that clients identify themselves so CCP can get in touch about a
        // misbehaving one. A real contact address belongs here before this ships.
        request.setValue(
            "eve-operator/\(appVersion) (macOS; \(Bundle.main.bundleIdentifier ?? "unknown"))",
            forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(names)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw Failure.badStatus(code)
        }

        // The response buckets matches by kind; characters is the only one that can be a
        // pilot, and a corporation sharing a pilot's name would otherwise be a wrong answer.
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return Dictionary(
            (decoded.characters ?? []).map { ($0.name, $0.id) },
            uniquingKeysWith: { first, _ in
                first
            })
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private struct Response: Decodable {
        let characters: [Match]?
    }

    private struct Match: Decodable {
        let id: Int64
        let name: String
    }

    enum Failure: Error, LocalizedError {
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "ESI returned HTTP \(code)"
            }
        }
    }
}
