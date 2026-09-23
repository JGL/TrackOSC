#!/usr/bin/env python3
"""Record a TrackOSC stream to a .trackosc file (no dependencies beyond the standard library).

    python3 trackosc_record.py out.trackosc                  # listen on 9527 until Ctrl-C
    python3 trackosc_record.py out.trackosc --port 9528 --seconds 30

Every datagram is stored exactly as received, so `trackosc_play.py` (or the
TrackOSC Recorder app) replays it byte for byte.
"""

import argparse
import socket
import time

from trackosc.recording import RecordingWriter


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("output", help="file to write (.trackosc)")
    parser.add_argument("--port", type=int, default=9527, help="UDP port to listen on (default 9527)")
    parser.add_argument("--seconds", type=float, default=None, help="stop after this long (default: until Ctrl-C)")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", args.port))
    sock.settimeout(0.25)
    print(f"Recording UDP {args.port} → {args.output} (Ctrl-C to stop)")

    deadline = None if args.seconds is None else time.monotonic() + args.seconds
    with RecordingWriter(args.output) as writer:
        try:
            while deadline is None or time.monotonic() < deadline:
                try:
                    datagram, _ = sock.recvfrom(65536)
                except socket.timeout:
                    continue
                writer.append(datagram)
        except KeyboardInterrupt:
            pass
    print(f"Wrote {writer.record_count} messages, {writer.byte_count} bytes")


if __name__ == "__main__":
    main()
