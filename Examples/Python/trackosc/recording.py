"""Read and write TrackOSC recordings (`.trackosc` files).

A recording is the raw OSC datagrams a receiver got, each stamped with its
arrival time, so playing one back reproduces the stream byte for byte. The
layout is specified in Examples/RECORDING_FORMAT.md and pinned by
PoseioscShared's tests on the Swift side and tests/test_recording.py here.

    from trackosc.recording import RecordingReader, RecordingWriter

    with RecordingWriter("session.trackosc") as w:
        w.append(datagram_bytes, t_seconds)

    r = RecordingReader("session.trackosc")
    for t_seconds, datagram in r:
        ...
"""

from __future__ import annotations

import struct
import time
from dataclasses import dataclass
from typing import Iterator, Sequence

MAGIC = b"TOSC"
VERSION = 1
HEADER_LENGTH = 32
MAX_DATAGRAM = 65536
EXTENSION = ".trackosc"

_HEADER = struct.Struct(">4sHHId12x")     # magic, version, flags, headerLength, createdUnix, reserved
_RECORD = struct.Struct(">QI")            # microseconds, length


class RecordingError(ValueError):
    pass


@dataclass
class Record:
    time: float          # seconds since the recording started
    datagram: bytes

    def address(self) -> str:
        """The OSC address of a message, "#bundle" for a bundle, "?" otherwise."""
        if self.datagram[:1] == b"#":
            return "#bundle"
        if self.datagram[:1] != b"/":
            return "?"
        end = self.datagram.find(b"\0")
        return self.datagram[: end if end >= 0 else None].decode("utf-8", "replace")


def encode_header(created_unix: float, flags: int = 0) -> bytes:
    return _HEADER.pack(MAGIC, VERSION, flags, HEADER_LENGTH, created_unix)


def decode_header(data: bytes) -> tuple[int, int, int, float]:
    """Returns (version, flags, header_length, created_unix)."""
    if len(data) < HEADER_LENGTH:
        raise RecordingError("truncated header")
    magic, version, flags, header_length, created = _HEADER.unpack_from(data)
    if magic != MAGIC:
        raise RecordingError("not a TrackOSC recording (bad magic)")
    if version != VERSION:
        raise RecordingError(f"unsupported recording version {version}")
    if header_length < HEADER_LENGTH:
        raise RecordingError(f"bad header length {header_length}")
    return version, flags, header_length, created


def encode_record(t_seconds: float, datagram: bytes) -> bytes:
    if len(datagram) > MAX_DATAGRAM:
        raise RecordingError(f"datagram too large ({len(datagram)} bytes)")
    micro = max(0, int(round(t_seconds * 1_000_000)))
    return _RECORD.pack(micro, len(datagram)) + datagram


class RecordingWriter:
    """Append-only writer. Use as a context manager or call close()."""

    def __init__(self, path: str, created_unix: float | None = None, flush_interval: float = 1.0):
        self.path = path
        self.created_unix = time.time() if created_unix is None else created_unix
        self._file = open(path, "wb")
        self._file.write(encode_header(self.created_unix))
        self._file.flush()
        self._start = time.monotonic()
        self._last_flush = self._start
        self._flush_interval = flush_interval
        self.record_count = 0
        self.byte_count = HEADER_LENGTH

    def append(self, datagram: bytes, t_seconds: float | None = None) -> None:
        """Append a datagram; `t_seconds` defaults to the time since the writer was made."""
        if t_seconds is None:
            t_seconds = time.monotonic() - self._start
        encoded = encode_record(t_seconds, datagram)
        self._file.write(encoded)
        self.record_count += 1
        self.byte_count += len(encoded)
        now = time.monotonic()
        if now - self._last_flush >= self._flush_interval:
            self._file.flush()
            self._last_flush = now

    def close(self) -> None:
        if self._file:
            self._file.flush()
            self._file.close()
            self._file = None

    def __enter__(self) -> "RecordingWriter":
        return self

    def __exit__(self, *exc) -> None:
        self.close()


class RecordingReader:
    """Loads a whole recording; iterate for (t_seconds, datagram) pairs."""

    def __init__(self, path: str | None = None, data: bytes | None = None):
        if data is None:
            if path is None:
                raise ValueError("path or data required")
            with open(path, "rb") as f:
                data = f.read()
        self.path = path
        self.version, self.flags, header_length, self.created_unix = decode_header(data)
        self.records: list[Record] = []
        self.truncated = False
        offset = header_length
        end = len(data)
        while offset < end:
            if end - offset < _RECORD.size:
                self.truncated = True
                break
            micro, length = _RECORD.unpack_from(data, offset)
            start = offset + _RECORD.size
            if length > MAX_DATAGRAM or end - start < length:
                self.truncated = True
                break
            self.records.append(Record(micro / 1_000_000, data[start:start + length]))
            offset = start + length

    @property
    def duration(self) -> float:
        return self.records[-1].time if self.records else 0.0

    def __len__(self) -> int:
        return len(self.records)

    def __iter__(self) -> Iterator[tuple[float, bytes]]:
        for record in self.records:
            yield record.time, record.datagram

    def index_at_or_after(self, t_seconds: float) -> int:
        lo, hi = 0, len(self.records)
        while lo < hi:
            mid = (lo + hi) // 2
            if self.records[mid].time < t_seconds:
                lo = mid + 1
            else:
                hi = mid
        return lo

    def counts_by_address(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for record in self.records:
            key = record.address()
            counts[key] = counts.get(key, 0) + 1
        return counts


def datagrams_equal(a: Sequence[Record], b: Sequence[Record]) -> bool:
    """True when two recordings carry the same datagrams in the same order (times may differ)."""
    return len(a) == len(b) and all(x.datagram == y.datagram for x, y in zip(a, b))
