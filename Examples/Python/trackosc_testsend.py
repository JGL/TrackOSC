#!/usr/bin/env python3
"""Send a synthetic TrackOSC scene – all twelve messages – for testing receivers
without a camera or the Swift toolchain. Mirrors ``poseiosc-testsend``.

    python3 trackosc_testsend.py [host] [port] [--landscape] [--rate 30] [--only poses,hands]

Portrait frames (720×1280) by default. The scene: a walking stick figure,
a waving hand, a face ring with box + jawline, a HELLO text box, a Cat box,
a 3D figure 2 m from the camera, a QR code, a side-view quadruped, and a
human box.
"""

import argparse
import math
import time

from pythonosc.udp_client import SimpleUDPClient

MISSING_CONF = 0.0


def pose(t, w, h):
    cx = w / 2 + math.sin(t * 0.7) * w * 0.1
    sway = math.sin(t * 2) * 60
    step = math.sin(t * 4) * 80
    head_y, shoulder_y, hip_y, knee_y, ankle_y = h * 0.2, h * 0.32, h * 0.55, h * 0.72, h * 0.9
    pts = [
        (cx, head_y), (cx - 25, head_y - 15), (cx + 25, head_y - 15), (cx - 50, head_y), (cx + 50, head_y),
        (cx - 110, shoulder_y), (cx + 110, shoulder_y),
        (cx - 150 - sway, shoulder_y + 180), (cx + 150 + sway, shoulder_y + 180),
        (cx - 170 - sway * 1.5, shoulder_y + 360), (cx + 170 + sway * 1.5, shoulder_y + 360),
        (cx - 80, hip_y), (cx + 80, hip_y),
        (cx - 90 - step, knee_y), (cx + 90 + step, knee_y),
        (cx - 95 - step, ankle_y), (cx + 95 + step, ankle_y),
    ]
    return [0.95] + [v for (x, y) in pts for v in (float(x), float(y), 0.9)]


def hand(t, w, h):
    wx, wy = w * 0.75, h * 0.45
    wave = math.sin(t * 3) * 0.3
    values = [0.9, wx, wy, 0.9]
    for finger in range(5):
        angle = -math.pi / 2 + (finger - 2) * (0.28 + wave * 0.15)
        for segment in range(1, 5):
            r = segment * 45
            values += [wx + math.cos(angle) * r, wy + math.sin(angle) * r, 0.85]
    return values


def face(t, w, h):
    cx, cy = w * 0.3, h * 0.25 + math.sin(t) * 30
    values = [0.92]
    for i in range(76):
        a = i / 76 * 2 * math.pi
        r = 90 + math.sin(a * 3 + t * 2) * 12
        values += [cx + math.cos(a) * r, cy + math.sin(a) * r * 1.3, 0.8]
    return values


def face_box(t, w, h):
    cx, cy = w * 0.3, h * 0.25 + math.sin(t) * 30
    rx, ry = 102, 102 * 1.3
    return [0.92, cx - rx, cy - ry, rx * 2, ry * 2, math.sin(t) * 20, math.cos(t * 0.5) * 15, 0.0]


def face_contour(t, w, h):
    cx, cy = w * 0.3, h * 0.25 + math.sin(t) * 30
    values = [0.92, 17]
    for i in range(17):
        a = i / 16 * math.pi
        values += [cx + math.cos(a) * 95, cy + math.sin(a) * 95 * 1.3]
    return values


def text(t, w, h):
    return [0.88, w * 0.1 + math.sin(t * 0.5) * w * 0.05, h * 0.65, w * 0.35, h * 0.05, "HELLO"]


def animal(t, w, h):
    return [0.8, w * 0.55 + math.cos(t * 0.8) * w * 0.08, h * 0.75, w * 0.3, h * 0.15, "Cat"]


def pose3d(t, w, h):
    drift, swing, dist, focal, ry = math.sin(t * 0.5) * 0.4, math.sin(t * 4) * 0.15, 2.0, h * 0.7, -0.2

    def j(x, y, dz=0.0):
        z = dist + dz
        return [x, y, z, w / 2 + x * focal / z, h / 2 - y * focal / z]

    joints = [
        j(drift, ry), j(drift, ry + 0.25), j(drift, ry + 0.5), j(drift, ry + 0.65), j(drift, ry + 0.78),
        j(drift - 0.2, ry + 0.5), j(drift - 0.25, ry + 0.25, swing), j(drift - 0.28, ry, swing * 2),
        j(drift + 0.2, ry + 0.5), j(drift + 0.25, ry + 0.25, -swing), j(drift + 0.28, ry, -swing * 2),
        j(drift - 0.1, ry), j(drift - 0.12, ry - 0.45, -swing), j(drift - 0.12, ry - 0.9, -swing * 1.5),
        j(drift + 0.1, ry), j(drift + 0.12, ry - 0.45, swing), j(drift + 0.12, ry - 0.9, swing * 1.5),
    ]
    return [0.93, 1.75] + [float(v) for joint in joints for v in joint]


def barcode(t, w, h):
    cx, cy, half, a = w * 0.62, h * 0.58, 90, math.sin(t * 0.8) * 0.2
    corners = [(cx + dx * math.cos(a) - dy * math.sin(a), cy + dx * math.sin(a) + dy * math.cos(a))
               for dx, dy in ((-half, -half), (half, -half), (half, half), (-half, half))]
    xs, ys = [c[0] for c in corners], [c[1] for c in corners]
    return ([1.0, min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)]
            + [v for c in corners for v in c] + ["QR", "https://github.com/JGL/TrackOSC"])


def animal_pose(t, w, h):
    cx, cy = w * 0.7 + math.cos(t * 0.8) * w * 0.08, h * 0.82
    step, wag = math.sin(t * 4) * 18, math.sin(t * 6) * 12
    offsets = [
        (110, -40), (85, -60), None,
        (60, -95), (65, -80), (70, -65), (48, -92), (53, -78), (58, -64),
        (50, -40),
        (45, 5), (45 + step, 40), (45 + step * 1.5, 75),
        (57, 5), (57 - step, 40), (57 - step * 1.5, 75),
        (-55, 5), (-55 - step, 40), (-55 - step * 1.5, 75),
        (-43, 5), (-43 + step, 40), (-43 + step * 1.5, 75),
        (-80, -30), (-115, -45 + wag), (-145, -40 + wag * 2),
    ]
    values = [0.88]
    for o in offsets:
        values += [0.0, float(h), MISSING_CONF] if o is None else [cx + o[0], cy + o[1], 0.85]
    return values


def human(t, w, h):
    values = pose(t, w, h)[1:]
    xs, ys = values[0::3], values[1::3]
    m = 40
    return [0.97, min(xs) - m, min(ys) - m, max(xs) - min(xs) + 2 * m, max(ys) - min(ys) + 2 * m]


SCENE = {
    "/poses/arr": pose, "/hands/arr": hand, "/faces/arr": face, "/faces/box": face_box,
    "/faces/contour": face_contour, "/texts/arr": text, "/animals/arr": animal,
    "/poses3d/arr": pose3d, "/barcodes/arr": barcode, "/animalposes/arr": animal_pose,
    "/humans/arr": human,
}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("host", nargs="?", default="127.0.0.1")
    ap.add_argument("port", nargs="?", type=int, default=9527)
    ap.add_argument("--landscape", action="store_true")
    ap.add_argument("--rate", type=float, default=30.0, help="frames per second")
    ap.add_argument("--only", help="comma-separated kinds, e.g. poses,hands,poses3d")
    args = ap.parse_args()

    w, h = (1280, 720) if args.landscape else (720, 1280)
    kinds = SCENE
    if args.only:
        wanted = {k.strip() for k in args.only.split(",")}
        kinds = {a: f for a, f in SCENE.items() if a.split("/")[1] in wanted}

    client = SimpleUDPClient(args.host, args.port)
    print(f"trackosc_testsend → {args.host}:{args.port} at {args.rate:g} fps, {w}x{h}, {len(kinds)} kinds (Ctrl-C to stop)")
    start = time.monotonic()
    try:
        while True:
            t = time.monotonic() - start
            client.send_message("/camerainfo", [w, h, 0 if args.landscape else 90, 1])
            for address, make in kinds.items():
                client.send_message(address, [w, h, 1] + make(t, w, h))
            time.sleep(1 / args.rate)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
