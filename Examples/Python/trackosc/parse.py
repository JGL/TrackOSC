"""Parse TrackOSC / VisionOSC messages into plain dataclasses.

Every detection message starts with ``int32 width, int32 height, int32 n``
(pixels of the sent frame; n detections, at most 32), followed by n
detections whose layout depends on the address — see the root README's
"OSC wire format". ``parse_message`` takes what python-osc hands a handler
(the address and the argument tuple) and returns a ``Frame`` (or a
``CameraInfo`` for ``/camerainfo``), or ``None`` for an unknown address.

A keypoint with ``c == 0`` is *missing* (VisionOSC's sentinel, sent as
``x=0, y=frameHeight``) — skip it when drawing.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Sequence


# ---- Values ----

@dataclass(frozen=True)
class Point:
    x: float
    y: float
    c: float = 1.0  # confidence (precision estimate for face landmarks)


@dataclass(frozen=True)
class Rect:
    left: float
    top: float
    width: float
    height: float


@dataclass(frozen=True)
class Joint3D:
    x: float   # metres, Vision camera space (x right, y up)
    y: float
    z: float
    px: float  # the same joint projected into the frame, pixels
    py: float


# ---- Detections ----

@dataclass
class Keypoints:
    """/poses/arr (17), /hands/arr (21), /faces/arr (76), /animalposes/arr (25)."""
    confidence: float
    points: list[Point]


@dataclass
class Box:
    """/texts/arr and /animals/arr (label), /humans/arr (label 'human')."""
    confidence: float
    box: Rect
    label: str


@dataclass
class FaceBox:
    """/faces/box: bounding box plus head rotation in degrees."""
    confidence: float
    box: Rect
    roll: float
    yaw: float
    pitch: float


@dataclass
class Contour:
    """/faces/contour: an OPEN jawline polyline (ear → chin → ear); may be empty."""
    confidence: float
    points: list[tuple[float, float]]


@dataclass
class Pose3D:
    """/poses3d/arr: 17 joints in metres + pixel projections; all present."""
    confidence: float
    body_height: float  # metres
    joints: list[Joint3D]


@dataclass
class Barcode:
    """/barcodes/arr: box, four corners (TL, TR, BR, BL), symbology, payload."""
    confidence: float
    box: Rect
    corners: list[tuple[float, float]]
    symbology: str
    payload: str


@dataclass
class Frame:
    """One decoded detection message."""
    address: str
    frame_w: int
    frame_h: int
    detections: list[Any] = field(default_factory=list)
    at: float = field(default_factory=time.monotonic)


@dataclass
class CameraInfo:
    """/camerainfo: sent with every processed frame; no n header."""
    width: int
    height: int
    orientation: int  # 0 landscape, 90 portrait, 180 landscape flipped, 270 portrait upside down
    facing: int       # 0 back, 1 front
    at: float = field(default_factory=time.monotonic)

    @property
    def orientation_name(self) -> str:
        return {0: "landscape", 90: "portrait", 180: "landscape (flipped)",
                270: "portrait (upside down)"}.get(self.orientation, f"{self.orientation}°")


KEYPOINT_COUNTS = {
    "/poses/arr": 17,
    "/hands/arr": 21,
    "/faces/arr": 76,
    "/animalposes/arr": 25,
}
ALL_ADDRESSES = [
    "/camerainfo", "/poses/arr", "/hands/arr", "/faces/arr", "/faces/box",
    "/faces/contour", "/texts/arr", "/animals/arr", "/poses3d/arr",
    "/barcodes/arr", "/animalposes/arr", "/humans/arr",
]


class TruncatedMessage(ValueError):
    """The message ended before its declared payload did."""


class _Cursor:
    """The running-argument-cursor idiom: read values in wire order."""

    def __init__(self, address: str, args: Sequence[Any]):
        self.address = address
        self.args = args
        self.i = 0

    def _next(self) -> Any:
        if self.i >= len(self.args):
            raise TruncatedMessage(f"{self.address}: expected ≥ {self.i + 1} arguments, got {len(self.args)}")
        value = self.args[self.i]
        self.i += 1
        return value

    def i32(self) -> int:
        return int(self._next())

    def count(self) -> int:
        value = self.i32()
        if value < 0:
            raise ValueError(f"{self.address}: negative count {value}")
        return value

    def f(self) -> float:
        return float(self._next())

    def s(self) -> str:
        return str(self._next())

    def rect(self) -> Rect:
        return Rect(self.f(), self.f(), self.f(), self.f())


def parse_message(address: str, args: Sequence[Any]) -> Frame | CameraInfo | None:
    """Decode one message; ``None`` for addresses TrackOSC doesn't define."""
    cur = _Cursor(address, args)

    if address == "/camerainfo":
        return CameraInfo(cur.i32(), cur.i32(), cur.i32(), cur.i32())

    if address in KEYPOINT_COUNTS:
        n_points = KEYPOINT_COUNTS[address]
        frame = _header(cur, address)
        for _ in range(frame_count(frame, cur)):
            conf = cur.f()
            points = [Point(cur.f(), cur.f(), cur.f()) for _ in range(n_points)]
            frame.detections.append(Keypoints(conf, points))
        return frame

    if address in ("/texts/arr", "/animals/arr"):
        frame = _header(cur, address)
        for _ in range(frame_count(frame, cur)):
            frame.detections.append(Box(cur.f(), cur.rect(), cur.s()))
        return frame

    if address == "/humans/arr":
        frame = _header(cur, address)
        for _ in range(frame_count(frame, cur)):
            frame.detections.append(Box(cur.f(), cur.rect(), "human"))
        return frame

    if address == "/faces/box":
        frame = _header(cur, address)
        for _ in range(frame_count(frame, cur)):
            frame.detections.append(FaceBox(cur.f(), cur.rect(), cur.f(), cur.f(), cur.f()))
        return frame

    if address == "/faces/contour":
        frame = _header(cur, address)
        for _ in range(frame_count(frame, cur)):
            conf = cur.f()
            m = cur.count()  # varies per face — always loop on m
            frame.detections.append(Contour(conf, [(cur.f(), cur.f()) for _ in range(m)]))
        return frame

    if address == "/poses3d/arr":
        frame = _header(cur, address)
        for _ in range(frame_count(frame, cur)):
            conf = cur.f()
            height = cur.f()
            joints = [Joint3D(cur.f(), cur.f(), cur.f(), cur.f(), cur.f()) for _ in range(17)]
            frame.detections.append(Pose3D(conf, height, joints))
        return frame

    if address == "/barcodes/arr":
        frame = _header(cur, address)
        for _ in range(frame_count(frame, cur)):
            conf = cur.f()
            box = cur.rect()
            corners = [(cur.f(), cur.f()) for _ in range(4)]
            frame.detections.append(Barcode(conf, box, corners, cur.s(), cur.s()))
        return frame

    return None


def _header(cur: _Cursor, address: str) -> Frame:
    return Frame(address, cur.i32(), cur.i32())


def frame_count(frame: Frame, cur: _Cursor) -> int:
    """Reads the detection count that follows the width/height pair."""
    return cur.count()


def visible(point: Point) -> bool:
    """False for VisionOSC's missing-keypoint sentinel."""
    return point.c > 0
