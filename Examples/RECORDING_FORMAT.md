# The `.trackosc` recording format

TrackOSC Recorder (macOS) and the Python tools in
[`Examples/Python`](Python/) record and play back the tracking stream. A
recording stores the **raw UDP datagrams exactly as they arrived**, each
with its arrival time, so playback reproduces the stream byte for byte and
every receiver in this repository – native, Processing, Python, p5.js,
TouchDesigner, Max, Pure Data, openFrameworks, SuperCollider – sees what it
would have seen live. Nothing is decoded on the way in, so unknown or
future messages survive too.

The layout is pinned by tests on both sides
([`RecordingFileTests.swift`](../PoseioscShared/Tests/PoseioscSharedTests/RecordingFileTests.swift),
[`test_recording.py`](Python/tests/test_recording.py)).

## Layout

All integers are big-endian. The file is append-only: a recorder writes
the header once, then one record per datagram.

### Header (32 bytes)

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 4 | magic | ASCII `TOSC` |
| 4 | 2 | version | `1` |
| 6 | 2 | flags | reserved, `0` |
| 8 | 4 | headerLength | `32` (readers skip to this offset, so a later version can grow the header) |
| 12 | 8 | createdUnix | IEEE 754 double, seconds since 1970 when recording started |
| 20 | 12 | reserved | zero |

### Records (repeated to end of file)

| Size | Field | Value |
|---|---|---|
| 8 | t | unsigned, microseconds since the recording started |
| 4 | length | unsigned, datagram length in bytes (at most 65 536) |
| length | datagram | the OSC packet as received (a message or a `#bundle`) |

Records are in arrival order; `t` never decreases. A reader must accept a
file whose final record is incomplete (the recorder crashed, or is still
writing) and use everything before it.

## Reading and writing

- Swift: `RecordingWriter` / `RecordingReader` in
  [`PoseioscShared/RecordingFile.swift`](../PoseioscShared/Sources/PoseioscShared/RecordingFile.swift).
- Python: `trackosc.recording` – `RecordingWriter`, `RecordingReader`;
  [`trackosc_record.py`](Python/trackosc_record.py) and
  [`trackosc_play.py`](Python/trackosc_play.py) need nothing beyond the
  standard library.
- Anything else: 32-byte header, then `>QI` records. A minimal player is a
  loop of sleep-until-`t`, `sendto`.

## Playback notes

- Playing at another speed scales `t`; the datagrams are untouched.
- After seeking, re-send the most recent `/camerainfo` before the new
  position so the receiver knows the frame size (the native player and
  `RecordingReader.lastIndex(of:before:)` do this).
- Looping restarts the clock at the first record's time.
