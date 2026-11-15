//
//  BlueMarshalReader.swift
//  eve-operator
//
//  Decodes a `blue.Marshal` stream into a `MarshalValue` tree. Ported from the reader in
//  TrueBrain's `blue-marshal` Rust crate (MIT) — https://github.com/truebrain/blue-marshal-rs —
//  which mirrors CCP's `Marshal.cpp`.
//
//  This is a pickle-shaped format, so the port is deliberately inert: `TY_GLOBAL` names are
//  kept as strings and never resolved, `TY_INSTANCE` and `TY_REDUCE` are kept as data and
//  never constructed, and the tags that can carry a real payload we cannot reason about
//  (`TY_DBROW`, `TY_WSTREAM`, `TY_PICKLE`, `TY_PICKLER`) are rejected outright. Nothing here
//  allocates on a length the stream claims without first checking the bytes are actually there.
//

import Foundation

nonisolated enum BlueMarshalError: Error, CustomStringConvertible {
    /// The stream ended inside an object.
    case endOfStream
    case invalid(String)
    /// A tag this port refuses to interpret rather than guess at.
    case unsupported(String)
    case badReference(Int64)
    case recursionLimit
    case checksumMismatch
    case tooLarge(Int)

    var description: String {
        switch self {
        case .endOfStream: return "unexpected end of marshal stream"
        case .invalid(let reason): return "malformed marshal stream: \(reason)"
        case .unsupported(let tag): return "unsupported marshal tag \(tag)"
        case .badReference(let id): return "marshal reference \(id) is out of range"
        case .recursionLimit: return "marshal stream nested deeper than allowed"
        case .checksumMismatch: return "marshal checksum mismatch"
        case .tooLarge(let bytes): return "marshal stream of \(bytes) bytes is too large"
        }
    }
}

nonisolated enum BlueMarshal {

    /// Ceiling on an input we will even look at. The largest file in a real profile is about
    /// 100 KB; this is the byte budget that keeps a corrupt or hostile file from turning into
    /// an allocation storm before the structural checks get a chance to fire.
    static let maximumInputSize = 32 * 1024 * 1024

    static func decode(_ data: Data) throws -> MarshalValue {
        guard data.count <= maximumInputSize else { throw BlueMarshalError.tooLarge(data.count) }
        var reader = Reader(buffer: [UInt8](data))
        try reader.readHeader()
        let value = try reader.readObject()
        if reader.sawCRC && reader.version > 0 {
            try reader.verifyCRC(end: reader.position)
        }
        return value
    }

    // MARK: - Tags

    /// `enum PYTYPES` from `Marshal.h`, kept whole so an unhandled tag is a named error.
    private enum Tag {
        static let signature: UInt8 = 126
        static let signature2: UInt8 = 125

        static let none: UInt8 = 1
        static let global: UInt8 = 2
        static let int64: UInt8 = 3
        static let int32: UInt8 = 4
        static let int16: UInt8 = 5
        static let int8: UInt8 = 6
        static let intNegative1: UInt8 = 7
        static let int0: UInt8 = 8
        static let int1: UInt8 = 9
        static let float: UInt8 = 10
        static let float0: UInt8 = 11
        static let complex: UInt8 = 12
        static let str: UInt8 = 13
        static let strEmpty: UInt8 = 14
        static let strChar: UInt8 = 15
        static let strShort: UInt8 = 16
        static let strTable: UInt8 = 17
        static let unicode: UInt8 = 18
        static let buffer: UInt8 = 19
        static let tuple: UInt8 = 20
        static let list: UInt8 = 21
        static let dict: UInt8 = 22
        static let instance: UInt8 = 23
        static let callback: UInt8 = 25
        static let pickle: UInt8 = 26
        static let reference: UInt8 = 27
        static let crcCheck: UInt8 = 28
        static let `true`: UInt8 = 31
        static let `false`: UInt8 = 32
        static let pickler: UInt8 = 33
        static let reduce: UInt8 = 34
        static let newObject: UInt8 = 35
        static let tuple0: UInt8 = 36
        static let tuple1: UInt8 = 37
        static let list0: UInt8 = 38
        static let list1: UInt8 = 39
        static let unicode0: UInt8 = 40
        static let unicode1: UInt8 = 41
        static let dbRow: UInt8 = 42
        static let wStream: UInt8 = 43
        static let tuple2: UInt8 = 44
        static let mark: UInt8 = 45
        static let utf8: UInt8 = 46
        static let long: UInt8 = 47

        static let sharedFlag: UInt8 = 0x40
        static let typeMask: UInt8 = 0x3F
    }

    private static let recursionLimit = 1000

    // MARK: - Reader

    private struct Reader {
        let buffer: [UInt8]
        var position = 0
        /// Usable content length. For version 0 this stops short of the trailing
        /// shared-object index map, which lives at the very end of the buffer.
        var size: Int
        var version: UInt8 = 0
        var shared: [MarshalValue] = []
        /// Version 0 only: the tail-of-buffer index map.
        var mapping: [Int32] = []
        var sharedSeen = 0
        var recursion = 0
        var sawCRC = false
        var crcPosition = 0
        var crcValue: Int32 = 0

        init(buffer: [UInt8]) {
            self.buffer = buffer
            self.size = buffer.count
        }

        // MARK: Primitives

        private var remaining: Int { max(0, size - position) }

        private func checkSpace(_ count: Int) throws {
            if count < 0 || count > remaining { throw BlueMarshalError.endOfStream }
        }

        private mutating func readUInt8() throws -> UInt8 {
            try checkSpace(1)
            defer { position += 1 }
            return buffer[position]
        }

        private mutating func readBytes(_ count: Int) throws -> ArraySlice<UInt8> {
            try checkSpace(count)
            defer { position += count }
            return buffer[position..<(position + count)]
        }

        private mutating func readInt32() throws -> Int32 {
            let bytes = Array(try readBytes(4))
            let value =
                UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            return Int32(bitPattern: value)
        }

        private mutating func readInt16() throws -> Int16 {
            let bytes = Array(try readBytes(2))
            return Int16(bitPattern: UInt16(bytes[0]) | UInt16(bytes[1]) << 8)
        }

        private mutating func readInt64() throws -> Int64 {
            let bytes = Array(try readBytes(8))
            var value: UInt64 = 0
            for byte in bytes.reversed() { value = value << 8 | UInt64(byte) }
            return Int64(bitPattern: value)
        }

        private mutating func readDouble() throws -> Double {
            Double(bitPattern: UInt64(bitPattern: try readInt64()))
        }

        /// `ReadStream::ReadInteger`: one byte, or a full `i32` when that byte is `0xFF`.
        private mutating func readCount() throws -> Int32 {
            let first = try readUInt8()
            return first == UInt8.max ? try readInt32() : Int32(first)
        }

        /// `ReadStream::GetBuff`: a length-prefixed byte string.
        private mutating func readBuffer() throws -> [UInt8] {
            let length = try readCount()
            guard length >= 0 else { throw BlueMarshalError.invalid("negative buffer length") }
            return Array(try readBytes(Int(length)))
        }

        private mutating func peekTag() throws -> UInt8 {
            try checkSpace(1)
            return buffer[position]
        }

        // MARK: Header

        mutating func readHeader() throws {
            let tag = try readUInt8()
            if tag == Tag.signature {
                version = 0
            } else if tag == Tag.signature2 {
                version = try readUInt8()
            } else {
                throw BlueMarshalError.invalid("missing marshal signature")
            }

            guard version == 0 else { return }

            let declared = try readInt32()
            guard declared >= 0 else { throw BlueMarshalError.invalid("negative shared count") }
            guard declared > 0 else { return }

            let count = Int(declared)
            let mapLength = count * 4
            guard mapLength <= buffer.count, remaining >= mapLength else {
                throw BlueMarshalError.invalid("truncated shared-object map")
            }

            let start = buffer.count - mapLength
            var mapping: [Int32] = []
            mapping.reserveCapacity(count)
            for index in 0..<count {
                let offset = start + index * 4
                let entry = Int32(
                    bitPattern: UInt32(buffer[offset])
                        | UInt32(buffer[offset + 1]) << 8
                        | UInt32(buffer[offset + 2]) << 16
                        | UInt32(buffer[offset + 3]) << 24)
                guard entry >= 1, Int(entry) <= count else {
                    throw BlueMarshalError.invalid("bogus shared-object map entry")
                }
                mapping.append(entry)
            }

            self.mapping = mapping
            self.size = start
            self.shared = Array(repeating: .none, count: count)
        }

        // MARK: Shared objects

        /// A slot for an object whose contents are known up front — strings, globals, longs.
        private mutating func store(_ value: MarshalValue) throws -> MarshalValue {
            let index = try allocateSharedSlot()
            shared[index] = value
            return value
        }

        /// A slot reserved before a container's contents are read, filled in afterwards.
        private mutating func allocateSharedSlot() throws -> Int {
            if version == 0 {
                guard sharedSeen < mapping.count else {
                    throw BlueMarshalError.invalid("shared object table overflow")
                }
                let index = Int(mapping[sharedSeen]) - 1
                sharedSeen += 1
                return index
            }
            shared.append(.none)
            return shared.count - 1
        }

        private func resolveReference(_ id: Int32) throws -> MarshalValue {
            let index = version == 0 ? Int(id) - 1 : Int(id)
            guard index >= 0, index < shared.count else {
                throw BlueMarshalError.badReference(Int64(id))
            }
            return shared[index]
        }

        func verifyCRC(end: Int) throws {
            let end = min(end, buffer.count)
            guard end >= crcPosition else { throw BlueMarshalError.invalid("crc range invalid") }
            let computed = Int32(bitPattern: Self.adler32(buffer[crcPosition..<end]))
            guard computed == crcValue else { throw BlueMarshalError.checksumMismatch }
        }

        /// zlib's `adler32(1, …)`, which is what `Marshal.cpp` uses for `TY_CRC_CHECK`.
        private static func adler32(_ data: ArraySlice<UInt8>) -> UInt32 {
            var a: UInt32 = 1
            var b: UInt32 = 0
            var index = data.startIndex
            while index < data.endIndex {
                // 5552 is zlib's NMAX: the most bytes that can be summed before the modulo
                // without risking a 32-bit overflow.
                let chunkEnd = min(index + 5552, data.endIndex)
                while index < chunkEnd {
                    a &+= UInt32(data[index])
                    b &+= a
                    index += 1
                }
                a %= 65521
                b %= 65521
            }
            return (b << 16) | a
        }

        // MARK: Objects

        mutating func readObject() throws -> MarshalValue {
            recursion += 1
            defer { recursion -= 1 }
            guard recursion <= BlueMarshal.recursionLimit else {
                throw BlueMarshalError.recursionLimit
            }
            return try readObjectBody()
        }

        private mutating func readObjectBody() throws -> MarshalValue {
            let raw = try readUInt8()
            let isShared = raw & Tag.sharedFlag != 0
            let tag = raw & Tag.typeMask

            switch tag {
            case Tag.none: return .none
            case Tag.true: return .bool(true)
            case Tag.false: return .bool(false)
            case Tag.intNegative1: return .int(-1)
            case Tag.int0: return .int(0)
            case Tag.int1: return .int(1)
            case Tag.int8: return .int(Int64(Int8(bitPattern: try readUInt8())))
            case Tag.int16: return .int(Int64(try readInt16()))
            case Tag.int32: return .int(Int64(try readInt32()))
            case Tag.int64: return .int(try readInt64())
            case Tag.float0: return .double(0)
            case Tag.float: return .double(try readDouble())

            case Tag.long:
                let value = MarshalValue.long(try readBuffer())
                return isShared ? try store(value) : value

            case Tag.strEmpty: return .bytes([])
            case Tag.strChar: return .bytes([try readUInt8()])
            case Tag.strShort:
                let length = Int(try readUInt8())
                return .bytes(Array(try readBytes(length)))

            case Tag.strTable:
                let index = try readUInt8()
                guard let string = BlueMarshalStringTable.lookup(index) else {
                    throw BlueMarshalError.invalid("invalid string table index \(index)")
                }
                return .bytes(Array(string.utf8))

            case Tag.str, Tag.buffer:
                let value = MarshalValue.bytes(try readBuffer())
                return isShared ? try store(value) : value

            case Tag.unicode0: return .string("")
            case Tag.unicode1:
                let bytes = Array(try readBytes(2))
                guard let text = Self.decodeUTF16([UInt16(bytes[0]) | UInt16(bytes[1]) << 8])
                else {
                    throw BlueMarshalError.invalid("bad utf-16 code unit")
                }
                return .string(text)

            case Tag.unicode:
                let length = try readCount()
                guard length >= 0 else {
                    throw BlueMarshalError.invalid("negative unicode length")
                }
                let bytes = Array(try readBytes(Int(length) * 2))
                var units: [UInt16] = []
                units.reserveCapacity(Int(length))
                for index in stride(from: 0, to: bytes.count, by: 2) {
                    units.append(UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8)
                }
                guard let text = Self.decodeUTF16(units) else {
                    throw BlueMarshalError.invalid("bad utf-16 data")
                }
                return .string(text)

            case Tag.utf8:
                let length = try readCount()
                guard length >= 0 else { throw BlueMarshalError.invalid("negative utf8 length") }
                let bytes = Array(try readBytes(Int(length)))
                guard let text = String(bytes: bytes, encoding: .utf8) else {
                    throw BlueMarshalError.invalid("bad utf-8 data")
                }
                return .string(text)

            case Tag.global:
                let bytes = try readBuffer()
                guard let name = String(bytes: bytes, encoding: .utf8) else {
                    throw BlueMarshalError.invalid("bad utf-8 in global name")
                }
                let value = MarshalValue.global(name)
                return isShared ? try store(value) : value

            case Tag.tuple0: return .tuple([])
            case Tag.tuple1: return try readSequence(count: 1, shared: isShared, kind: .tuple)
            case Tag.tuple2: return try readSequence(count: 2, shared: isShared, kind: .tuple)
            case Tag.tuple:
                let count = try readCount()
                guard count >= 0 else { throw BlueMarshalError.invalid("negative tuple length") }
                // Every element is at least one byte, so a length the buffer cannot hold is
                // a corrupt stream rather than something to go and allocate for.
                try checkSpace(Int(count))
                return try readSequence(count: Int(count), shared: isShared, kind: .tuple)

            case Tag.list0: return .list([])
            case Tag.list1: return try readSequence(count: 1, shared: isShared, kind: .list)
            case Tag.list:
                let count = try readCount()
                guard count >= 0 else { throw BlueMarshalError.invalid("negative list length") }
                try checkSpace(Int(count))
                return try readSequence(count: Int(count), shared: isShared, kind: .list)

            case Tag.dict:
                let count = try readCount()
                guard count >= 0 else { throw BlueMarshalError.invalid("negative dict length") }
                try checkSpace(Int(count) * 2)
                let slot = isShared ? try allocateSharedSlot() : nil
                var pairs: [MarshalValue.Pair] = []
                pairs.reserveCapacity(Int(count))
                for _ in 0..<Int(count) {
                    // The value is written before the key — see `WriteObject('d')`.
                    let value = try readObject()
                    let key = try readObject()
                    pairs.append(.init(key: key, value: value))
                }
                let dict = MarshalValue.dict(pairs)
                if let slot { shared[slot] = dict }
                return dict

            case Tag.instance:
                let slot = isShared ? try allocateSharedSlot() : nil
                guard let className = try readObject().textValue else {
                    throw BlueMarshalError.invalid("TY_INSTANCE class name isn't a string")
                }
                let value = MarshalValue.instance(className: className, state: try readObject())
                if let slot { shared[slot] = value }
                return value

            case Tag.reduce, Tag.newObject:
                let isNewObject = tag == Tag.newObject
                let slot = isShared ? try allocateSharedSlot() : nil
                guard case .tuple(let items) = try readObject() else {
                    throw BlueMarshalError.invalid("reduce payload isn't a tuple")
                }
                let callable: MarshalValue
                let arguments: MarshalValue
                let state: MarshalValue?
                if isNewObject {
                    guard let first = items.first else {
                        throw BlueMarshalError.invalid("empty newobj tuple")
                    }
                    callable = .none
                    arguments = first
                    state = items.count > 1 ? items[1] : nil
                } else {
                    guard items.count >= 2 else {
                        throw BlueMarshalError.invalid("reduce tuple too short")
                    }
                    callable = items[0]
                    arguments = items[1]
                    state = items.count > 2 ? items[2] : nil
                }
                let value = MarshalValue.reduce(
                    .init(
                        isNewObject: isNewObject,
                        callable: callable,
                        arguments: arguments,
                        state: state,
                        listItems: try readListIterator(),
                        dictItems: try readDictIterator()))
                if let slot { shared[slot] = value }
                return value

            case Tag.callback:
                return .callback(try readObject())

            case Tag.reference:
                return try resolveReference(try readCount())

            case Tag.crcCheck:
                crcValue = try readInt32()
                sawCRC = true
                crcPosition = position
                if version == 0 { try verifyCRC(end: buffer.count) }
                return try readObject()

            case Tag.dbRow: throw BlueMarshalError.unsupported("TY_DBROW")
            case Tag.wStream: throw BlueMarshalError.unsupported("TY_WSTREAM")
            case Tag.pickle: throw BlueMarshalError.unsupported("TY_PICKLE")
            case Tag.pickler: throw BlueMarshalError.unsupported("TY_PICKLER")
            case Tag.complex: throw BlueMarshalError.unsupported("TY_COMPLEX")
            default: throw BlueMarshalError.invalid("unknown type tag \(tag)")
            }
        }

        private enum SequenceKind { case tuple, list }

        private mutating func readSequence(
            count: Int, shared isShared: Bool, kind: SequenceKind
        ) throws -> MarshalValue {
            let slot = isShared ? try allocateSharedSlot() : nil
            var items: [MarshalValue] = []
            items.reserveCapacity(count)
            for _ in 0..<count { items.append(try readObject()) }
            let value: MarshalValue = kind == .tuple ? .tuple(items) : .list(items)
            if let slot { shared[slot] = value }
            return value
        }

        /// `ReadObjectListIter`: values until a `TY_MARK`.
        private mutating func readListIterator() throws -> [MarshalValue] {
            var items: [MarshalValue] = []
            while true {
                if try peekTag() & Tag.typeMask == Tag.mark {
                    position += 1
                    return items
                }
                items.append(try readObject())
            }
        }

        /// `ReadObjectDictIter`: key/value pairs until a `TY_MARK`.
        private mutating func readDictIterator() throws -> [MarshalValue.Pair] {
            var pairs: [MarshalValue.Pair] = []
            while true {
                if try peekTag() & Tag.typeMask == Tag.mark {
                    position += 1
                    return pairs
                }
                let key = try readObject()
                pairs.append(.init(key: key, value: try readObject()))
            }
        }

        /// `String(utf16CodeUnits:)` silently substitutes replacement characters, which would
        /// turn a corrupt stream into plausible-looking text, so unpaired surrogates fail.
        private static func decodeUTF16(_ units: [UInt16]) -> String? {
            var decoder = UTF16()
            var iterator = units.makeIterator()
            var scalars = String.UnicodeScalarView()
            while true {
                switch decoder.decode(&iterator) {
                case .scalarValue(let scalar): scalars.append(scalar)
                case .emptyInput: return String(scalars)
                case .error: return nil
                }
            }
        }
    }
}
