#!/usr/bin/env python3
"""Headless TrackOSC listener: one line per message, no window.

    python3 trackosc_print.py [--port 9527]

Handy for checking a sender reaches this machine, and as the smallest
possible starting point for your own receiver: replace ``summarise`` with
whatever you want to do with each frame.
"""

import argparse

from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer

from trackosc import (Barcode, Box, CameraInfo, Contour, FaceBox, Keypoints,
                      Pose3D, parse_message)


def summarise(frame) -> str:
    if isinstance(frame, CameraInfo):
        return (f"/camerainfo  {frame.width}x{frame.height} {frame.orientation_name} "
                f"{'front' if frame.facing == 1 else 'back'}")
    head = f"{frame.address:<16} {frame.frame_w}x{frame.frame_h} n={len(frame.detections)}"
    if not frame.detections:
        return head
    d = frame.detections[0]
    if isinstance(d, Pose3D):
        r = d.joints[0]
        return f"{head} conf={d.confidence:.2f} height={d.body_height:.2f}m root=({r.x:.2f},{r.y:.2f},{r.z:.2f})m"
    if isinstance(d, Keypoints):
        p = d.points[0]
        return f"{head} conf={d.confidence:.2f} p0=({p.x:.0f},{p.y:.0f},{p.c:.2f})"
    if isinstance(d, Barcode):
        return f'{head} {d.symbology} "{d.payload}"'
    if isinstance(d, FaceBox):
        return f"{head} conf={d.confidence:.2f} roll={d.roll:.0f}° yaw={d.yaw:.0f}° pitch={d.pitch:.0f}°"
    if isinstance(d, Contour):
        return f"{head} conf={d.confidence:.2f} m={len(d.points)}"
    if isinstance(d, Box):
        b = d.box
        return f'{head} "{d.label}" ({b.left:.0f},{b.top:.0f} {b.width:.0f}x{b.height:.0f})'
    return head


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=9527)
    args = ap.parse_args()

    def on_message(address, *osc_args):
        try:
            frame = parse_message(address, osc_args)
        except Exception as error:  # truncated / wrong types
            print(f"undecodable {address}: {error}")
            return
        print("unknown address " + address if frame is None else summarise(frame))

    dispatcher = Dispatcher()
    dispatcher.set_default_handler(on_message)
    server = BlockingOSCUDPServer(("0.0.0.0", args.port), dispatcher)
    server.max_packet_size = 65536  # /faces/arr with several faces exceeds the 8 KB default
    print(f"trackosc_print listening on UDP {args.port} (Ctrl-C to stop)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
