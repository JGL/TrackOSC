//
//  RecordingFileTests.swift
//  PoseioscSharedTests
//
//  The .trackosc format is a compatibility contract with the Python tools
//  in Examples/Python, so the byte layout is pinned here.
//

import Foundation
import Testing
@testable import PoseioscShared

@Suite("Recording file format")
struct RecordingFileTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString)")
            .appendingPathExtension(RecordingFormat.fileExtension)
    }

    @Test func headerLayoutIsPinned() throws {
        let header = RecordingHeader(createdAt: Date(timeIntervalSince1970: 1_700_000_000.5))
        let bytes = [UInt8](header.encoded())
        #expect(bytes.count == 32)
        #expect(Array(bytes[0..<4]) == Array("TOSC".utf8))
        #expect(Array(bytes[4..<6]) == [0, 1])          // version 1
        #expect(Array(bytes[6..<8]) == [0, 0])          // flags
        #expect(Array(bytes[8..<12]) == [0, 0, 0, 32])  // header length
        // f64 1_700_000_000.5 big-endian
        #expect(Array(bytes[12..<20]) == [0x41, 0xD9, 0x54, 0xFC, 0x40, 0x20, 0x00, 0x00])
        #expect(Array(bytes[20..<32]) == [UInt8](repeating: 0, count: 12))
        let parsed = try RecordingHeader(parsing: Data(bytes))
        #expect(parsed == header)
    }

    @Test func recordLayoutIsPinned() {
        let record = RecordingRecord(time: .milliseconds(1_500), datagram: Data("/x\0\0,\0\0\0".utf8))
        let bytes = [UInt8](record.encoded())
        #expect(Array(bytes[0..<8]) == [0, 0, 0, 0, 0, 0x16, 0xE3, 0x60])   // 1_500_000 µs
        #expect(Array(bytes[8..<12]) == [0, 0, 0, 8])
        #expect(Array(bytes[12...]) == Array("/x\0\0,\0\0\0".utf8))
    }

    @Test func headerRejectsBadInput() {
        #expect(throws: RecordingError.truncatedHeader) { try RecordingHeader(parsing: Data([1, 2, 3])) }
        var wrongMagic = RecordingHeader(createdAt: .now).encoded()
        wrongMagic[0] = 0x58
        #expect(throws: RecordingError.badMagic) { try RecordingHeader(parsing: wrongMagic) }
        var wrongVersion = RecordingHeader(createdAt: .now).encoded()
        wrongVersion[5] = 9
        #expect(throws: RecordingError.unsupportedVersion(9)) { try RecordingHeader(parsing: wrongVersion) }
    }

    @Test func writerThenReaderRoundTrip() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let writer = try RecordingWriter(url: url, createdAt: created, flushInterval: .seconds(100))
        let datagrams = (0..<50).map { i in Data("/poses/arr\0\0,iii\0\0\0\0".utf8) + Data([UInt8(i)]) }
        for (i, datagram) in datagrams.enumerated() {
            try writer.append(RecordingRecord(time: .milliseconds(33 * i), datagram: datagram))
        }
        #expect(writer.recordCount == 50)
        try writer.close()

        let reader = try RecordingReader(url: url)
        #expect(reader.header.createdAt == created)
        #expect(reader.records.count == 50)
        #expect(reader.wasTruncated == false)
        #expect(reader.records.map(\.datagram) == datagrams)
        #expect(reader.records[10].time == .milliseconds(330))
        #expect(reader.duration == .milliseconds(33 * 49))
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        #expect(size == writer.byteCount)
    }

    @Test func truncatedTailIsTolerated() throws {
        var data = RecordingHeader(createdAt: .now).encoded()
        data += RecordingRecord(time: .seconds(1), datagram: Data([1, 2, 3, 4])).encoded()
        data += RecordingRecord(time: .seconds(2), datagram: Data([5, 6, 7, 8])).encoded().prefix(14)
        let reader = try RecordingReader(data: data)
        #expect(reader.records.count == 1)
        #expect(reader.wasTruncated == true)
    }

    @Test func seekingByTimeAndPriming() throws {
        var data = RecordingHeader(createdAt: .now).encoded()
        func message(_ address: String) -> Data {
            var bytes = Data(address.utf8)
            while bytes.count % 4 != 0 || bytes.last != 0 { bytes.append(0) }
            return bytes + Data(",\0\0\0".utf8)
        }
        data += RecordingRecord(time: .seconds(0), datagram: message("/camerainfo")).encoded()
        data += RecordingRecord(time: .seconds(1), datagram: message("/poses/arr")).encoded()
        data += RecordingRecord(time: .seconds(2), datagram: message("/poses/arr")).encoded()
        data += RecordingRecord(time: .seconds(3), datagram: message("/camerainfo")).encoded()
        data += RecordingRecord(time: .seconds(4), datagram: message("/poses/arr")).encoded()
        let reader = try RecordingReader(data: data)
        #expect(reader.index(atOrAfter: .zero) == 0)
        #expect(reader.index(atOrAfter: .milliseconds(1_500)) == 2)
        #expect(reader.index(atOrAfter: .seconds(4)) == 4)
        #expect(reader.index(atOrAfter: .seconds(9)) == 5)
        #expect(reader.lastIndex(of: "/camerainfo", before: 2) == 0)
        #expect(reader.lastIndex(of: "/camerainfo", before: 5) == 3)
        #expect(reader.lastIndex(of: "/camerainfo", before: 0) == nil)
        #expect(reader.lastIndex(of: "/camera", before: 5) == nil)   // prefix must end at the NUL
    }
}
