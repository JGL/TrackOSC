"""Optional Script SOP callbacks: turns the ``poses`` table (filled by
trackosc_callbacks.py) into line geometry — one open polyline per skeleton
edge, in normalised coordinates (x across -0.5…0.5, y up), so a Geometry COMP
with a Line MAT draws the skeleton in 3D space.

Paste into the callbacks DAT of a Script SOP. Change TABLE / EDGES / COUNT
below to draw hands (``hands``, HAND_EDGES, 21) or animals
(``animalposes``, ANIMAL_EDGES, 25) instead.
"""

TABLE = "poses"
COUNT = 17


def _edges():
    try:
        return mod.trackosc_skeletons.BODY_EDGES  # noqa: F821
    except Exception:
        return []


def onSetupParameters(scriptOp):
    return


def onPulse(par):
    return


def onCook(scriptOp):
    scriptOp.clear()
    table = op(TABLE)  # noqa: F821
    frames = op("frames")  # noqa: F821
    if table is None or table.numRows < 2:
        return

    # Frame size from the 'frames' table (fallback: portrait 720×1280).
    width, height = 720.0, 1280.0
    if frames is not None:
        for r in range(1, frames.numRows):
            if str(frames[r, "address"]) == "/poses/arr":
                width, height = float(frames[r, "width"]), float(frames[r, "height"])

    # Rows are (det, joint, name, x, y, c, conf); group by detection.
    points = {}
    for r in range(1, table.numRows):
        det = int(table[r, "det"])
        joint = int(table[r, "joint"])
        points.setdefault(det, {})[joint] = (float(table[r, "x"]), float(table[r, "y"]), float(table[r, "c"]))

    for det in sorted(points):
        joints = points[det]
        for a, b in _edges():
            pa, pb = joints.get(a), joints.get(b)
            if pa is None or pb is None or pa[2] <= 0 or pb[2] <= 0:
                continue  # missing keypoint (VisionOSC's confidence-0 sentinel)
            poly = scriptOp.appendPoly(2, closed=False, addPoints=True)
            for vertex, (x, y, _) in zip(poly, (pa, pb)):
                vertex.point.x = x / width - 0.5
                vertex.point.y = 0.5 - y / height       # wire y grows downward; TD y grows upward
                vertex.point.z = 0.0
    return
