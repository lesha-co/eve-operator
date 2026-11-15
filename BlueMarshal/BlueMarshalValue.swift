//
//  BlueMarshalValue.swift
//  eve-operator
//
//  One decoded object from a `blue.Marshal` stream — the format EVE writes its
//  `core_char_*.dat` / `core_user_*.dat` settings files in. See
//  `docs/eve-settings-files.md`.
//
//  Ported from TrueBrain's `blue-marshal` Rust crate (MIT), which is itself a port of CCP's
//  `Marshal.cpp`: https://github.com/truebrain/blue-marshal-rs
//
//  Read-only by design. Nothing in this app writes an EVE settings file, which is what keeps
//  us clear of the "EVE clobbers external edits on logout" hazard entirely.
//

import Foundation

nonisolated indirect enum MarshalValue: Sendable {
    case none
    case bool(Bool)
    case int(Int64)
    /// `TY_LONG` — Python 2's arbitrary-precision `long`, kept as its raw signed
    /// little-endian bytes. No bignum library: `int64` covers every FILETIME in these files,
    /// and `decimalString` covers printing the rest.
    case long([UInt8])
    case double(Double)
    /// A Python 2 byte string (`str` / `buffer`). EVE writes section and setting names as these.
    case bytes([UInt8])
    /// A Python `unicode` string (`TY_UNICODE` / `TY_UTF8`).
    case string(String)
    case tuple([MarshalValue])
    case list([MarshalValue])
    /// Stream order is preserved, and keys can be any value, so this is a list of pairs
    /// rather than a `Dictionary`. Sections hold a few hundred keys and we look up three.
    case dict([Pair])
    /// `TY_GLOBAL`: a class or function named by `module.name`. Never resolved, never called.
    case global(String)
    /// `TY_INSTANCE`: an old-style class instance, kept as its class name and its state.
    case instance(className: String, state: MarshalValue)
    /// `TY_REDUCE` / `TY_NEWOBJ`: the `__reduce__` pickle protocol, kept verbatim.
    case reduce(Reduce)
    /// `TY_CALLBACK`: payload that went through a save/load callback. We keep the payload.
    case callback(MarshalValue)

    nonisolated struct Pair: Sendable {
        let key: MarshalValue
        let value: MarshalValue
    }

    nonisolated struct Reduce: Sendable {
        /// True when the stream said `TY_NEWOBJ`, in which case `callable` is implicit.
        let isNewObject: Bool
        let callable: MarshalValue
        let arguments: MarshalValue
        let state: MarshalValue?
        let listItems: [MarshalValue]
        let dictItems: [Pair]
    }
}

// MARK: - Accessors

nonisolated extension MarshalValue {

    /// Looks a dict key up by name, matching either a byte string or a unicode string: EVE
    /// writes most keys as byte strings but not all of them, and no call site should care.
    subscript(key: String) -> MarshalValue? {
        guard case .dict(let pairs) = self else { return nil }
        return pairs.first { $0.key.textValue == key }?.value
    }

    /// Settings are stored as `(timestamp, value)` — format doc §3. Unwraps the value half.
    var settingValue: MarshalValue? {
        guard case .tuple(let items) = self, items.count == 2 else { return nil }
        return items[1]
    }

    /// The timestamp half of a `(timestamp, value)` setting, as a date.
    var settingTimestamp: Date? {
        guard case .tuple(let items) = self, items.count == 2 else { return nil }
        return items[0].filetime
    }

    /// Byte strings and unicode strings both read as text; everything else is `nil`.
    var textValue: String? {
        switch self {
        case .bytes(let bytes): return String(decoding: bytes, as: UTF8.self)
        case .string(let text): return text
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var intValue: Int64? {
        switch self {
        case .int(let value): return value
        case .long(let bytes): return Self.int64(signedLittleEndian: bytes)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    /// Lists and tuples alike — EVE is inconsistent about which it uses for a sequence.
    var arrayValue: [MarshalValue]? {
        switch self {
        case .list(let items), .tuple(let items): return items
        default: return nil
        }
    }

    var pairs: [Pair]? {
        if case .dict(let pairs) = self { return pairs }
        return nil
    }

    /// A Windows FILETIME — 100 ns ticks since 1601-01-01 UTC — as a `Date`.
    var filetime: Date? {
        guard let ticks = intValue, ticks > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600)
    }
}

// MARK: - Long arithmetic

nonisolated extension MarshalValue {

    /// Sign-extends up to eight signed little-endian bytes; wider values do not fit and the
    /// caller gets `nil` rather than a silently truncated answer.
    static func int64(signedLittleEndian bytes: [UInt8]) -> Int64? {
        guard !bytes.isEmpty else { return 0 }
        guard bytes.count <= 8 else { return nil }
        var value: UInt64 = 0
        for byte in bytes.reversed() { value = (value << 8) | UInt64(byte) }
        let isNegative = bytes[bytes.count - 1] & 0x80 != 0
        if isNegative && bytes.count < 8 {
            // Fill the unused high bytes with the sign bit.
            let usedBits = UInt64(bytes.count) * 8
            value |= ~UInt64(0) << usedBits
        }
        return Int64(bitPattern: value)
    }

    /// Decimal rendering of an arbitrarily wide signed little-endian integer. Schoolbook
    /// division by ten over the magnitude bytes — these values are at most a few words, so
    /// the quadratic cost is irrelevant and it saves taking on a bignum dependency.
    static func decimalString(signedLittleEndian bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "0" }

        let isNegative = bytes[bytes.count - 1] & 0x80 != 0
        var magnitude = bytes
        if isNegative {
            // Two's complement negation: invert, then add one.
            for index in magnitude.indices { magnitude[index] = ~magnitude[index] }
            var carry = true
            var index = magnitude.startIndex
            while carry && index < magnitude.endIndex {
                let (sum, overflow) = magnitude[index].addingReportingOverflow(1)
                magnitude[index] = sum
                carry = overflow
                index += 1
            }
        }

        while let last = magnitude.last, last == 0 { magnitude.removeLast() }

        var digits: [Character] = []
        while !magnitude.isEmpty {
            var remainder: UInt16 = 0
            for index in magnitude.indices.reversed() {
                let current = remainder << 8 | UInt16(magnitude[index])
                magnitude[index] = UInt8(current / 10)
                remainder = current % 10
            }
            digits.append(Character(String(remainder)))
            while let last = magnitude.last, last == 0 { magnitude.removeLast() }
        }

        if digits.isEmpty { return "0" }
        return (isNegative ? "-" : "") + String(digits.reversed())
    }
}
