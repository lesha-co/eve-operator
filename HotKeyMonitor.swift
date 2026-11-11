//
//  HotKeyMonitor.swift
//  eve-operator
//
//  System-wide hot keys that raise a client by its position in the strip.
//

import AppKit
import Carbon.HIToolbox

/// Modifiers a slot hot key can be qualified with.
///
/// Carbon's own masks are deliberately not the stored form: the plist is meant to stay legible,
/// and a preference file should not depend on the numbering in a C header.
nonisolated struct HotKeyModifiers: OptionSet, Sendable {
    let rawValue: Int

    static let control = HotKeyModifiers(rawValue: 1 << 0)
    static let option = HotKeyModifiers(rawValue: 1 << 1)
    static let shift = HotKeyModifiers(rawValue: 1 << 2)
    static let command = HotKeyModifiers(rawValue: 1 << 3)

    /// In the order macOS writes them in a menu, which is also the order `symbols` emits.
    static let all: [HotKeyModifiers] = [.control, .option, .shift, .command]

    /// "⌃", or "⌃⌥" for a combination.
    var symbols: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        default: Self.all.filter(contains).map(\.symbols).joined()
        }
    }

    /// The stored form: "control,option", or "" for no modifier at all.
    var names: String {
        Self.all.filter(contains).map(\.name).joined(separator: ",")
    }

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Unknown names are dropped rather than rejected, so a plist written by a later build
    /// degrades to the modifiers this one understands instead of to nothing at all.
    init(names: String) {
        self = names.split(separator: ",").reduce(into: []) { result, token in
            let name = token.trimmingCharacters(in: .whitespaces)
            if let match = Self.all.first(where: { $0.name == name }) { result.insert(match) }
        }
    }

    /// The `RegisterEventHotKey` mask.
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    private var name: String {
        switch self {
        case .control: "control"
        case .option: "option"
        case .shift: "shift"
        case .command: "command"
        default: ""
        }
    }
}

/// Registers F1…F12 as system-wide hot keys, one per position in the strip.
///
/// Carbon's hot keys are the only mechanism here that both works while another application is
/// frontmost and *consumes* the keystroke. `NSEvent.addGlobalMonitorForEvents` cannot swallow
/// what it sees, so every press would also reach EVE and fire the module in that slot, and a
/// `CGEventTap` — the other way to consume — would put this app in the path of every keystroke
/// on the system and need re-arming each time the tap is disabled for taking too long. Carbon
/// also needs no permission of its own: Accessibility is what raises the window afterwards, not
/// what reads the key.
@MainActor
final class HotKeyMonitor {

    /// Virtual key codes for F1…F12, in order. The length of this table is the number of
    /// clients that can be reached by hot key at all.
    private static let keyCodes: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    ]

    static var maxSlots: Int { keyCodes.count }

    /// `'evop'`. Hot keys are dispatched per-process, so the handler has to recognise its own.
    nonisolated fileprivate static let signature: OSType = 0x6576_6F70

    /// How the key for `slot` reads to a human — "F3", or "⌃⌥F3". `nil` past the end of the
    /// table, where there is no key to describe.
    static func label(forSlot slot: Int, modifiers: HotKeyModifiers) -> String? {
        guard keyCodes.indices.contains(slot) else { return nil }
        return modifiers.symbols + "F\(slot + 1)"
    }

    private let onActivate: (Int) -> Void

    private var registered: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    /// What `registered` was built from, so the poll driving this does nothing on the vast
    /// majority of passes, where nothing has changed.
    private var current: (slots: Int, modifiers: HotKeyModifiers)?

    /// Slots whose key another application had already claimed. Surfaced in Settings, because
    /// the alternative is a key that silently does nothing.
    private(set) var unavailableSlots: [Int] = []

    init(onActivate: @escaping (Int) -> Void) {
        self.onActivate = onActivate
    }

    deinit {
        for hotKey in registered { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Registers the first `slotCount` keys and nothing else.
    ///
    /// Unregistering the rest is the point as much as registering these: an unmodified F-key
    /// is a key every other application wants too, so one is only taken while there is a
    /// client it would actually raise.
    func sync(slotCount: Int, modifiers: HotKeyModifiers) {
        let slots = min(max(slotCount, 0), Self.maxSlots)
        guard current?.slots != slots || current?.modifiers != modifiers else { return }
        current = (slots, modifiers)

        unregisterAll()
        guard slots > 0 else { return }
        installHandler()

        var unavailable: [Int] = []
        for slot in 0..<slots {
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(slot))
            var hotKey: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(Self.keyCodes[slot]), modifiers.carbonFlags, id,
                GetEventDispatcherTarget(), 0, &hotKey)

            if status == noErr, let hotKey {
                registered.append(hotKey)
            } else {
                // Almost always `eventHotKeyExistsErr`: something else registered it first,
                // and whatever that is keeps it.
                unavailable.append(slot)
            }
        }
        unavailableSlots = unavailable
    }

    fileprivate func activate(slot: Int) {
        onActivate(slot)
    }

    // MARK: - Carbon plumbing

    /// Installed once and left in place: it costs nothing while no hot key is registered, and
    /// tearing it down on an empty strip would only mean building it again on the next client.
    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(), hotKeyEventHandler, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func unregisterAll() {
        for hotKey in registered { UnregisterEventHotKey(hotKey) }
        registered = []
        unavailableSlots = []
    }
}

/// A C callback, so it can capture nothing: the monitor arrives as the handler's user data.
/// Carbon dispatches hot keys on the main run loop, which is the main actor — hence
/// `assumeIsolated` rather than a hop, so the client is raised in the same turn as the press.
private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr, id.signature == HotKeyMonitor.signature else {
        return OSStatus(eventNotHandledErr)
    }

    MainActor.assumeIsolated {
        Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            .activate(slot: Int(id.id))
    }
    return noErr
}
