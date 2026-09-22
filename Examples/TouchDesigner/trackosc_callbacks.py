"""OSC In DAT callbacks for TrackOSC – paste into the Callbacks DAT of an
OSC In DAT (see README.md for the network recipe).

Every TrackOSC message is parsed here and written into a Table DAT named
after its address (``poses``, ``hands``, ``faces``, ``faces_box``,
``faces_contour``, ``texts``, ``animals``, ``poses3d``, ``barcodes``,
``animalposes``, ``humans``, ``camerainfo``), one row per joint / point /
detection, plus a ``frames`` table with the latest header per address.
Tables that don't exist are skipped, so create only the ones you need.

Written for TouchDesigner's Python 3.11 (no 3.12+ syntax).

Wire format: every detection message starts with int32 width, int32 height,
int32 n (pixels of the sent frame, origin top-left, never mirrored), then n
detections – see the root README "OSC wire format". A keypoint with c == 0
is missing (VisionOSC's sentinel) – skip it.

TRACKOSC SKELETON REFERENCE v1.4 – joint orders live in trackosc_skeletons.py.
"""

import time

KEYPOINT_COUNTS = {"/poses/arr": 17, "/hands/arr": 21, "/faces/arr": 76, "/animalposes/arr": 25}
TABLES = {
    "/poses/arr": "poses", "/hands/arr": "hands", "/faces/arr": "faces",
    "/faces/box": "faces_box", "/faces/contour": "faces_contour",
    "/texts/arr": "texts", "/animals/arr": "animals", "/poses3d/arr": "poses3d",
    "/barcodes/arr": "barcodes", "/animalposes/arr": "animalposes", "/humans/arr": "humans",
    "/camerainfo": "camerainfo",
}


def _joint_names(address):
    try:
        sk = mod.trackosc_skeletons  # noqa: F821 – TouchDesigner's module accessor
    except Exception:
        return None
    return {"/poses/arr": sk.BODY_JOINTS, "/hands/arr": sk.HAND_JOINTS,
            "/animalposes/arr": sk.ANIMAL_JOINTS}.get(address)


def _table(name):
    """The Table DAT with this name, or None (so missing tables are simply skipped)."""
    try:
        return op(name)  # noqa: F821 – TouchDesigner builtin
    except NameError:
        return None


class _Cursor:
    def __init__(self, address, args):
        self.address = address
        self.args = args
        self.i = 0

    def _next(self):
        if self.i >= len(self.args):
            raise ValueError("%s: truncated (expected >= %d arguments, got %d)" % (self.address, self.i + 1, len(self.args)))
        value = self.args[self.i]
        self.i += 1
        return value

    def i32(self):
        return int(self._next())

    def count(self):
        value = self.i32()
        if value < 0:
            raise ValueError("%s: negative count %d" % (self.address, value))
        return value

    def f(self):
        return float(self._next())

    def s(self):
        return str(self._next())


def _fill(table, header, rows):
    if table is None:
        return
    table.clear()
    table.appendRow(header)
    for row in rows:
        table.appendRow(row)


def onReceiveOSC(dat, rowIndex, message, bytes, timeStamp, address, args, peer):
    """TouchDesigner calls this for every OSC message the OSC In DAT receives."""
    try:
        parse(address, args)
    except Exception as error:
        print("TrackOSC: failed to parse %s: %s" % (address, error))


def parse(address, args):
    cur = _Cursor(address, args)

    if address == "/camerainfo":
        width, height, orientation, facing = cur.i32(), cur.i32(), cur.i32(), cur.i32()
        _fill(_table("camerainfo"), ["key", "value"], [
            ["width", width], ["height", height], ["orientation", orientation],
            ["facing", facing], ["time", time.time()],
        ])
        return

    table_name = TABLES.get(address)
    if table_name is None:
        return  # not a TrackOSC address

    width, height, n = cur.i32(), cur.i32(), cur.count()
    _note_frame(address, width, height, n)
    rows = []

    if address in KEYPOINT_COUNTS:
        names = _joint_names(address)
        for det in range(n):
            conf = cur.f()
            for joint in range(KEYPOINT_COUNTS[address]):
                x, y, c = cur.f(), cur.f(), cur.f()
                name = names[joint] if names else str(joint)
                rows.append([det, joint, name, x, y, c, conf])
        _fill(_table(table_name), ["det", "joint", "name", "x", "y", "c", "conf"], rows)

    elif address in ("/texts/arr", "/animals/arr"):
        for det in range(n):
            rows.append([det, cur.f(), cur.f(), cur.f(), cur.f(), cur.f(), cur.s()])
        _fill(_table(table_name), ["det", "conf", "left", "top", "width", "height", "label"], rows)

    elif address == "/humans/arr":
        for det in range(n):
            rows.append([det, cur.f(), cur.f(), cur.f(), cur.f(), cur.f()])
        _fill(_table(table_name), ["det", "conf", "left", "top", "width", "height"], rows)

    elif address == "/faces/box":
        for det in range(n):
            rows.append([det] + [cur.f() for _ in range(8)])
        _fill(_table(table_name), ["det", "conf", "left", "top", "width", "height", "roll", "yaw", "pitch"], rows)

    elif address == "/faces/contour":
        for det in range(n):
            conf = cur.f()
            m = cur.count()  # varies per face – always loop on m
            for point in range(m):
                rows.append([det, point, cur.f(), cur.f(), conf])
        _fill(_table(table_name), ["det", "point", "x", "y", "conf"], rows)

    elif address == "/poses3d/arr":
        names = _joint_names_3d()
        for det in range(n):
            conf, body_height = cur.f(), cur.f()
            for joint in range(17):
                x, y, z, px, py = cur.f(), cur.f(), cur.f(), cur.f(), cur.f()
                rows.append([det, joint, names[joint], x, y, z, px, py, conf, body_height])
        _fill(_table(table_name), ["det", "joint", "name", "x", "y", "z", "px", "py", "conf", "bodyHeight"], rows)

    elif address == "/barcodes/arr":
        for det in range(n):
            conf = cur.f()
            box = [cur.f() for _ in range(4)]
            corners = [cur.f() for _ in range(8)]
            rows.append([det, conf] + box + corners + [cur.s(), cur.s()])
        _fill(_table(table_name), ["det", "conf", "left", "top", "width", "height",
                                   "tl_x", "tl_y", "tr_x", "tr_y", "br_x", "br_y", "bl_x", "bl_y",
                                   "symbology", "payload"], rows)


def _joint_names_3d():
    try:
        return mod.trackosc_skeletons.POSE3D_JOINTS  # noqa: F821
    except Exception:
        return [str(i) for i in range(17)]


_frames = {}


def _note_frame(address, width, height, n):
    """Keep the latest header per address in the 'frames' table (if it exists)."""
    _frames[address] = [address, width, height, n, time.time()]
    table = _table("frames")
    if table is None:
        return
    table.clear()
    table.appendRow(["address", "width", "height", "n", "time"])
    for row in sorted(_frames.values()):
        table.appendRow(row)
