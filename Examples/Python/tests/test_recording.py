"""Pins the .trackosc byte layout (shared with PoseioscShared's RecordingFileTests).

    cd Examples/Python && python3 -m unittest discover tests
"""

import os
import tempfile
import unittest

from trackosc.recording import (RecordingError, RecordingReader, RecordingWriter, datagrams_equal,
                                decode_header, encode_header, encode_record)


class HeaderTests(unittest.TestCase):
    def test_layout_is_pinned(self):
        data = encode_header(1_700_000_000.5)
        self.assertEqual(len(data), 32)
        self.assertEqual(data[0:4], b"TOSC")
        self.assertEqual(data[4:6], b"\x00\x01")
        self.assertEqual(data[6:8], b"\x00\x00")
        self.assertEqual(data[8:12], b"\x00\x00\x00\x20")
        self.assertEqual(data[12:20], bytes([0x41, 0xD9, 0x54, 0xFC, 0x40, 0x20, 0x00, 0x00]))
        self.assertEqual(data[20:32], bytes(12))
        self.assertEqual(decode_header(data), (1, 0, 32, 1_700_000_000.5))

    def test_rejects_bad_input(self):
        with self.assertRaises(RecordingError):
            decode_header(b"TOS")
        with self.assertRaises(RecordingError):
            decode_header(b"XOSC" + encode_header(0)[4:])
        bad_version = bytearray(encode_header(0))
        bad_version[5] = 9
        with self.assertRaises(RecordingError):
            decode_header(bytes(bad_version))


class RecordTests(unittest.TestCase):
    def test_layout_is_pinned(self):
        data = encode_record(1.5, b"/x\0\0,\0\0\0")
        self.assertEqual(data[0:8], bytes([0, 0, 0, 0, 0, 0x16, 0xE3, 0x60]))
        self.assertEqual(data[8:12], b"\x00\x00\x00\x08")
        self.assertEqual(data[12:], b"/x\0\0,\0\0\0")


class RoundTripTests(unittest.TestCase):
    def test_writer_then_reader(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "t.trackosc")
            datagrams = [b"/poses/arr\0\0,iii\0\0\0\0" + bytes([i]) for i in range(50)]
            with RecordingWriter(path, created_unix=1_800_000_000) as writer:
                for i, datagram in enumerate(datagrams):
                    writer.append(datagram, 0.033 * i)
            self.assertEqual(writer.record_count, 50)
            self.assertEqual(os.path.getsize(path), writer.byte_count)

            reader = RecordingReader(path)
            self.assertEqual(reader.created_unix, 1_800_000_000)
            self.assertEqual(len(reader), 50)
            self.assertFalse(reader.truncated)
            self.assertEqual([d for _, d in reader], datagrams)
            self.assertAlmostEqual(reader.records[10].time, 0.33, places=6)
            self.assertAlmostEqual(reader.duration, 0.033 * 49, places=6)
            self.assertTrue(datagrams_equal(reader.records, RecordingReader(path).records))

    def test_truncated_tail_is_tolerated(self):
        data = encode_header(0) + encode_record(1, b"\x01\x02\x03\x04") + encode_record(2, b"\x05\x06\x07\x08")[:14]
        reader = RecordingReader(data=data)
        self.assertEqual(len(reader), 1)
        self.assertTrue(reader.truncated)

    def test_seek_and_addresses(self):
        def message(address):
            padded = address.encode() + b"\0"
            while len(padded) % 4:
                padded += b"\0"
            return padded + b",\0\0\0"

        data = encode_header(0)
        for t, address in [(0, "/camerainfo"), (1, "/poses/arr"), (2, "/poses/arr"), (3, "/camerainfo"), (4, "/poses/arr")]:
            data += encode_record(t, message(address))
        reader = RecordingReader(data=data)
        self.assertEqual(reader.index_at_or_after(0), 0)
        self.assertEqual(reader.index_at_or_after(1.5), 2)
        self.assertEqual(reader.index_at_or_after(9), 5)
        self.assertEqual(reader.counts_by_address(), {"/camerainfo": 2, "/poses/arr": 3})


if __name__ == "__main__":
    unittest.main()
