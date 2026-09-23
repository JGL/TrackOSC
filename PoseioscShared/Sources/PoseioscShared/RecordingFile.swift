//
//  RecordingFile.swift
//  PoseioscShared
//
//  The `.trackosc` recording format: raw OSC datagrams with arrival times,
//  so a recording plays back byte-for-byte as the sender sent it and any
//  receiver – native, Python, Processing – sees exactly what it would have
//  seen live. Specified in Examples/RECORDING_FORMAT.md.
//
//  Layout (all integers big-endian):
//
//    header, 32 bytes
//      0   "TOSC"            4 bytes magic
//      4   version           u16, currently 1
//      6   flags             u16, reserved (0)
//      8   headerLength      u32, 32
//      12  createdUnix       f64, seconds since 1970 when recording started
//      20  reserved          12 bytes (0)
//
//    records, repeated to end of file
//      t                     u64, microseconds since the recording started
//      length                u32, datagram length in bytes
//      datagram              length bytes, the OSC packet exactly as received
//
//  Append-only and crash-tolerant: a reader ignores a truncated final record.
//

import Foundation

public enum RecordingFormat {
    public static let magic: [UInt8] = Array("TOSC".utf8)
    public static let version: UInt16 = 1
    public static let headerLength: UInt32 = 32
    public static let fileExtension = "trackosc"
    public static let uniformTypeIdentifier = "com.joelgethinlewis.trackosc"
    /// Largest datagram a record may carry (UDP's own limit).
    public static let maximumDatagram: UInt32 = 65_536
}

public struct RecordingHeader: Equatable, Sendable {
    public var version: UInt16
    public var flags: UInt16
    public var createdAt: Date

    public init(version: UInt16 = RecordingFormat.version, flags: UInt16 = 0, createdAt: Date) {
        self.version = version
        self.flags = flags
        self.createdAt = createdAt
    }

    public func encoded() -> Data {
        var data = Data(capacity: Int(RecordingFormat.headerLength))
        data.append(contentsOf: RecordingFormat.magic)
        data.appendBigEndian(version)
        data.appendBigEndian(flags)
        data.appendBigEndian(RecordingFormat.headerLength)
        data.appendBigEndian(createdAt.timeIntervalSince1970.bitPattern)
        data.append(contentsOf: [UInt8](repeating: 0, count: 12))
        return data
    }

    /// Parses the fixed header; `data` may be longer than the header.
    public init(parsing data: Data) throws(RecordingError) {
        guard data.count >= Int(RecordingFormat.headerLength) else { throw .truncatedHeader }
        let bytes = [UInt8](data.prefix(Int(RecordingFormat.headerLength)))
        guard Array(bytes[0..<4]) == RecordingFormat.magic else { throw .badMagic }
        let version = UInt16(bigEndianBytes: bytes[4..<6])
        guard version == RecordingFormat.version else { throw .unsupportedVersion(version) }
        let headerLength = UInt32(bigEndianBytes: bytes[8..<12])
        guard headerLength >= RecordingFormat.headerLength else { throw .badHeaderLength(headerLength) }
        self.version = version
        self.flags = UInt16(bigEndianBytes: bytes[6..<8])
        self.createdAt = Date(timeIntervalSince1970: Double(bitPattern: UInt64(bigEndianBytes: bytes[12..<20])))
    }
}

public enum RecordingError: Error, Equatable, Sendable {
    case truncatedHeader
    case badMagic
    case unsupportedVersion(UInt16)
    case badHeaderLength(UInt32)
    case datagramTooLarge(Int)
    case closed
}

/// One datagram and when it arrived, relative to the recording's start.
public struct RecordingRecord: Equatable, Sendable {
    public var time: Duration
    public var datagram: Data

    public init(time: Duration, datagram: Data) {
        self.time = time
        self.datagram = datagram
    }

    public var microseconds: UInt64 {
        let components = time.components
        return UInt64(max(0, components.seconds)) * 1_000_000 + UInt64(max(0, components.attoseconds / 1_000_000_000_000))
    }

    /// The record's on-disk form (12-byte prefix + datagram).
    public func encoded() -> Data {
        var data = Data(capacity: 12 + datagram.count)
        data.appendBigEndian(microseconds)
        data.appendBigEndian(UInt32(datagram.count))
        data.append(datagram)
        return data
    }
}

/// Writes records as they arrive. Safe to call from any thread; the file
/// is flushed on a timer-like cadence (every `flushInterval` of appends)
/// and on close, and every append is complete on disk after `flush()`.
public final class RecordingWriter: @unchecked Sendable {
    public let url: URL
    public let header: RecordingHeader
    /// Appends are timed against this instant (the moment the writer was made).
    public let startInstant: ContinuousClock.Instant

    private let lock = NSLock()
    private var handle: FileHandle?
    private var buffer = Data()
    private var lastFlush: ContinuousClock.Instant
    private(set) public var recordCount: Int = 0
    private(set) public var byteCount: Int = Int(RecordingFormat.headerLength)
    private let flushInterval: Duration

    /// Creates (or truncates) the file and writes the header immediately.
    public init(url: URL, createdAt: Date = .now, flushInterval: Duration = .seconds(1)) throws {
        self.url = url
        self.header = RecordingHeader(createdAt: createdAt)
        self.startInstant = .now
        self.lastFlush = startInstant
        self.flushInterval = flushInterval
        try header.encoded().write(to: url, options: .atomic)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        self.handle = handle
    }

    /// Appends a datagram stamped with the time since the writer was made.
    public func append(_ datagram: Data, at instant: ContinuousClock.Instant = .now) throws {
        try append(RecordingRecord(time: instant - startInstant, datagram: datagram))
    }

    public func append(_ record: RecordingRecord) throws {
        guard record.datagram.count <= Int(RecordingFormat.maximumDatagram) else {
            throw RecordingError.datagramTooLarge(record.datagram.count)
        }
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { throw RecordingError.closed }
        buffer.append(record.encoded())
        recordCount += 1
        byteCount += 12 + record.datagram.count
        let now = ContinuousClock.now
        if now - lastFlush >= flushInterval {
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
            lastFlush = now
        }
    }

    public func flush() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }
        try handle.synchronize()
        lastFlush = .now
    }

    public func close() throws {
        try flush()
        lock.lock()
        defer { lock.unlock() }
        try handle?.close()
        handle = nil
    }

    deinit {
        try? close()
    }
}

/// Reads a whole recording into memory (mapped when the file system
/// allows) and indexes it for seeking by time.
public final class RecordingReader: Sendable {
    public let url: URL
    public let header: RecordingHeader
    public let records: [RecordingRecord]
    /// True when the file ended part-way through a record (a crash or a
    /// recording still in progress); everything before it is intact.
    public let wasTruncated: Bool

    public convenience init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(data: data, url: url)
    }

    public init(data: Data, url: URL = URL(fileURLWithPath: "/dev/null")) throws {
        self.url = url
        let header = try RecordingHeader(parsing: data)
        self.header = header
        var records: [RecordingRecord] = []
        var offset = data.startIndex + Int(RecordingFormat.headerLength)
        var truncated = false
        while offset < data.endIndex {
            guard data.endIndex - offset >= 12 else { truncated = true; break }
            let micro = UInt64(bigEndianBytes: data[offset..<offset + 8])
            let length = Int(UInt32(bigEndianBytes: data[offset + 8..<offset + 12]))
            guard length <= Int(RecordingFormat.maximumDatagram) else { truncated = true; break }
            let start = offset + 12
            guard data.endIndex - start >= length else { truncated = true; break }
            records.append(RecordingRecord(time: .microseconds(Int64(micro)), datagram: Data(data[start..<start + length])))
            offset = start + length
        }
        self.records = records
        self.wasTruncated = truncated
    }

    public var duration: Duration { records.last?.time ?? .zero }

    /// Index of the first record at or after `time`, or `records.count` when past the end.
    public func index(atOrAfter time: Duration) -> Int {
        var low = 0, high = records.count
        while low < high {
            let mid = (low + high) / 2
            if records[mid].time < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Index of the last record whose datagram is an OSC message to `address`
    /// before `index`, so playback can prime a receiver (e.g. with /camerainfo)
    /// after a seek. nil when none precedes it.
    public func lastIndex(of address: String, before index: Int) -> Int? {
        let needle = Array(address.utf8)
        var i = min(index, records.count) - 1
        while i >= 0 {
            let datagram = records[i].datagram
            if datagram.count > needle.count, datagram.starts(with: needle), datagram[datagram.startIndex + needle.count] == 0 {
                return i
            }
            i -= 1
        }
        return nil
    }
}

// MARK: - Big-endian helpers

extension Data {
    fileprivate mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
}

extension FixedWidthInteger {
    fileprivate init<C: Collection>(bigEndianBytes bytes: C) where C.Element == UInt8 {
        precondition(bytes.count == MemoryLayout<Self>.size)
        var value: Self = 0
        for byte in bytes {
            value = value << 8 | Self(byte)
        }
        self = value
    }
}
