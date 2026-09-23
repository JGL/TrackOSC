#!/usr/bin/env python3
"""Play a .trackosc recording to a receiver (standard library only).

    python3 trackosc_play.py session.trackosc                       # → 127.0.0.1:9527, once
    python3 trackosc_play.py session.trackosc --loop --speed 2
    python3 trackosc_play.py session.trackosc --host 192.168.1.20 --port 9527
"""

import argparse
import socket
import time

from trackosc.recording import RecordingReader


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("recording", help="the .trackosc file to play")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9527)
    parser.add_argument("--loop", action="store_true", help="play again from the start when the end is reached")
    parser.add_argument("--speed", type=float, default=1.0, help="playback speed multiplier (default 1)")
    args = parser.parse_args()

    reader = RecordingReader(args.recording)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    note = " (file was truncated; playing what is intact)" if reader.truncated else ""
    print(f"Playing {len(reader)} messages, {reader.duration:.1f} s → {args.host}:{args.port}"
          f" at {args.speed}×{' looping' if args.loop else ''}{note}")

    try:
        while True:
            start = time.monotonic()
            for t, datagram in reader:
                due = start + t / args.speed
                delay = due - time.monotonic()
                if delay > 0:
                    time.sleep(delay)
                sock.sendto(datagram, (args.host, args.port))
            if not args.loop:
                break
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
