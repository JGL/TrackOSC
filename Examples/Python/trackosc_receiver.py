#!/usr/bin/env python3
"""TrackOSC receiver in Python + pygame: draws all twelve messages, like the
Processing reference sketch, plus a top-down minimap of the 3D poses.

    python3 trackosc_receiver.py [--port 9527]

Keys: G toggles the coordinate guides, Q / Esc quits.
"""

import argparse
import threading
import time

import pygame
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import ThreadingOSCUDPServer

from trackosc import (ANIMAL_EDGES, BODY_EDGES, COLOURS, HAND_EDGES, POSE3D_EDGES,
                      Barcode, Box, CameraInfo, Contour, FaceBox, Horizon, Keypoints, Pose3D, Rectangle,
                      parse_message, visible)

STALE_S = 0.5
CAMERA_INFO_STALE_S = 2.0
WINDOW = (720, 960)


class Latest:
    """Most recent frame per address, written by the OSC thread, read by draw()."""

    def __init__(self):
        self.frames = {}
        self.camera = None
        self.unknown = 0
        self.lock = threading.Lock()

    def on_message(self, address, *args):
        try:
            frame = parse_message(address, args)
        except Exception:
            frame = None
        with self.lock:
            if frame is None:
                self.unknown += 1
            elif isinstance(frame, CameraInfo):
                self.camera = frame
            else:
                self.frames[address] = frame

    def snapshot(self):
        now = time.monotonic()
        with self.lock:
            fresh = {a: f for a, f in self.frames.items() if now - f.at < STALE_S}
            camera = self.camera if self.camera and now - self.camera.at < CAMERA_INFO_STALE_S else None
            return fresh, camera, self.unknown


def fit(frame_w, frame_h, width, height):
    sc = min(width / frame_w, height / frame_h)
    return sc, (width - frame_w * sc) / 2, (height - frame_h * sc) / 2


def draw_skeleton(surface, points, edges, colour, sc, ox, oy):
    for a, b in edges:
        pa, pb = points[a], points[b]
        if not (visible(pa) and visible(pb)):
            continue
        pygame.draw.line(surface, colour, (ox + pa.x * sc, oy + pa.y * sc), (ox + pb.x * sc, oy + pb.y * sc), 2)
    for p in points:
        if visible(p):
            pygame.draw.circle(surface, colour, (ox + p.x * sc, oy + p.y * sc), 3)


def draw_box(surface, font, rect, label, colour, sc, ox, oy):
    x, y = ox + rect.left * sc, oy + rect.top * sc
    pygame.draw.rect(surface, colour, pygame.Rect(x, y, rect.width * sc, rect.height * sc), 2)
    if label:
        surface.blit(font.render(label, True, colour), (x + 4, max(y - 16, 2)))


def draw_guides(surface, font, frame_w, frame_h, sc, ox, oy, camera):
    grey = COLOURS["guides"]
    fw, fh = frame_w * sc, frame_h * sc
    pygame.draw.rect(surface, (64, 64, 64), pygame.Rect(ox, oy, fw, fh), 1)
    pygame.draw.circle(surface, grey, (ox, oy), 4)
    pygame.draw.line(surface, grey, (ox, oy), (ox + 48, oy), 1)
    pygame.draw.line(surface, grey, (ox, oy), (ox, oy + 48), 1)
    surface.blit(font.render("x", True, grey), (ox + 58, oy - 7))
    surface.blit(font.render("y", True, grey), (ox - 4, oy + 56))
    surface.blit(font.render("(0,0)", True, grey), (ox + 8, oy - 20))
    caption = f"{frame_w}×{frame_h} px"
    if camera:
        caption += f" · {camera.orientation_name} · {'front' if camera.facing == 1 else 'back'} camera"
    text = font.render(caption, True, grey)
    surface.blit(text, (ox + fw / 2 - text.get_width() / 2, oy + fh - 20))


def draw_minimap(surface, font, poses):
    """Top-down view (x across, z away) of the 3D poses, bottom-right corner."""
    size, margin, metres = 160, 12, 5.0
    left, top = surface.get_width() - size - margin, surface.get_height() - size - margin
    colour = COLOURS["/poses3d/arr"]
    pygame.draw.rect(surface, (40, 40, 40), pygame.Rect(left, top, size, size))
    pygame.draw.rect(surface, (90, 90, 90), pygame.Rect(left, top, size, size), 1)
    # Camera at the bottom centre, looking up the map.
    cam = (left + size / 2, top + size - 8)
    pygame.draw.polygon(surface, (180, 180, 180), [cam, (cam[0] - 5, cam[1] + 6), (cam[0] + 5, cam[1] + 6)])
    scale = size / metres
    for pose in poses:
        pts = [(cam[0] + j.x * scale, cam[1] - abs(j.z) * scale) for j in pose.joints]
        for a, b in POSE3D_EDGES:
            pygame.draw.line(surface, colour, pts[a], pts[b], 1)
    surface.blit(font.render("top-down · x / z (m)", True, (150, 150, 150)), (left + 4, top + 4))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=9527)
    args = ap.parse_args()

    latest = Latest()
    dispatcher = Dispatcher()
    dispatcher.set_default_handler(latest.on_message)
    server = ThreadingOSCUDPServer(("0.0.0.0", args.port), dispatcher)
    server.max_packet_size = 65536
    threading.Thread(target=server.serve_forever, daemon=True).start()

    pygame.init()
    screen = pygame.display.set_mode(WINDOW)
    pygame.display.set_caption(f"TrackOSC Receiver (Python) – listening on {args.port}")
    font = pygame.font.SysFont("menlo,monospace", 13)
    clock = pygame.time.Clock()
    show_guides = True

    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN:
                if event.key in (pygame.K_q, pygame.K_ESCAPE):
                    running = False
                elif event.key == pygame.K_g:
                    show_guides = not show_guides

        screen.fill((0, 0, 0))
        fresh, camera, unknown = latest.snapshot()
        if not fresh:
            text = font.render(f"Waiting for OSC messages on port {args.port}…", True, (128, 128, 128))
            screen.blit(text, text.get_rect(center=screen.get_rect().center))
        else:
            ref = next(iter(fresh.values()))
            sc, ox, oy = fit(ref.frame_w, ref.frame_h, *WINDOW)
            if show_guides:
                draw_guides(screen, font, ref.frame_w, ref.frame_h, sc, ox, oy, camera)
            for address, frame in fresh.items():
                colour = COLOURS.get(address, (200, 200, 200))
                for d in frame.detections:
                    if isinstance(d, Keypoints):
                        edges = {"/poses/arr": BODY_EDGES, "/hands/arr": HAND_EDGES,
                                 "/animalposes/arr": ANIMAL_EDGES}.get(address)
                        if edges:
                            draw_skeleton(screen, d.points, edges, colour, sc, ox, oy)
                        else:  # faces: dots only
                            for p in d.points:
                                if visible(p):
                                    pygame.draw.circle(screen, colour, (ox + p.x * sc, oy + p.y * sc), 1)
                    elif isinstance(d, Pose3D):
                        pts = [(ox + j.px * sc, oy + j.py * sc) for j in d.joints]
                        for a, b in POSE3D_EDGES:
                            pygame.draw.line(screen, colour, pts[a], pts[b], 2)
                        for p in pts:
                            pygame.draw.circle(screen, colour, p, 3)
                        screen.blit(font.render(f"z {d.joints[0].z:.2f} m · h {d.body_height:.2f} m", True, colour),
                                    (pts[0][0] + 8, pts[0][1] - 18))
                    elif isinstance(d, FaceBox):
                        draw_box(screen, font, d.box, None, colour, sc, ox, oy)
                    elif isinstance(d, Contour) and len(d.points) >= 2:
                        # /faces/contour is an OPEN jawline; /contours/arr outlines are CLOSED.
                        closed = address == "/contours/arr"
                        pygame.draw.lines(screen, colour, closed, [(ox + x * sc, oy + y * sc) for x, y in d.points], 2 if not closed else 1)
                    elif isinstance(d, Horizon):
                        a = (ox + d.start[0] * sc, oy + d.start[1] * sc)
                        b = (ox + d.end[0] * sc, oy + d.end[1] * sc)
                        pygame.draw.line(screen, colour, a, b, 2)
                        screen.blit(font.render(f"horizon {d.angle:.1f}°", True, colour), ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 - 18))
                    elif isinstance(d, Rectangle):
                        pts = [(ox + x * sc, oy + y * sc) for x, y in d.corners]
                        pygame.draw.lines(screen, colour, True, pts, 2)
                        pygame.draw.circle(screen, colour, pts[0], 4)
                    elif isinstance(d, Barcode):
                        pts = [(ox + x * sc, oy + y * sc) for x, y in d.corners]
                        pygame.draw.lines(screen, colour, True, pts, 2)
                        pygame.draw.circle(screen, colour, pts[0], 4)
                        screen.blit(font.render(f"{d.symbology} {d.payload}", True, colour),
                                    (min(p[0] for p in pts), max(min(p[1] for p in pts) - 16, 2)))
                    elif isinstance(d, Box):
                        draw_box(screen, font, d.box, f"{d.label} {d.confidence:.2f}", colour, sc, ox, oy)
            if "/poses3d/arr" in fresh:
                draw_minimap(screen, font, fresh["/poses3d/arr"].detections)
        if unknown:
            screen.blit(font.render(f"unknown messages: {unknown}", True, (255, 160, 0)), (8, 8))

        pygame.display.flip()
        clock.tick(60)

    pygame.quit()


if __name__ == "__main__":
    main()
