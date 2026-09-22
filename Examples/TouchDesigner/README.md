# TrackOSC receiver example for TouchDesigner

TouchDesigner's `.toe` files are binary, so this example ships the parts that
can live in a text repository – a Python callbacks script and a recipe for the
network – rather than a project file. Building it takes about five minutes.

| File | Paste into |
|---|---|
| [`trackosc_callbacks.py`](trackosc_callbacks.py) | The **Callbacks DAT** of an OSC In DAT. Parses every TrackOSC message into Table DATs. |
| [`trackosc_skeletons.py`](trackosc_skeletons.py) | A **Text DAT named `trackosc_skeletons`** (joint names and edge lists, imported by the callbacks). |
| [`trackosc_script_sop.py`](trackosc_script_sop.py) | Optional: the callbacks DAT of a **Script SOP**, to draw skeletons as geometry. |

## Why an OSC In DAT rather than an OSC In CHOP

TrackOSC messages have a variable number of arguments (n detections, and
`/faces/contour` has a per-face point count) and carry strings (text,
animal labels, barcode payloads). An OSC In **CHOP** flattens each message
into fixed channels and drops strings, which works only for `/camerainfo`.
The OSC In **DAT** hands the raw argument list to Python, where the same
running-cursor parser as every other example turns it into tables – and
tables convert to CHOPs, SOPs or anything else.

## Recipe

1. **OSC In DAT** (`oscin1`): Network Port `9527`, Address Scope `*`,
   Bundle Timestamp off. Only one program can listen on a port – quit the
   native TrackOSC Receiver first.
2. **Text DAT** named exactly `trackosc_skeletons`: paste
   `trackosc_skeletons.py` into it.
3. Open `oscin1`'s Callbacks DAT (the `oscin1_callbacks` Text DAT it creates)
   and replace its contents with `trackosc_callbacks.py`.
4. **Table DATs**, one per message you want, named exactly:
   `camerainfo`, `poses`, `hands`, `faces`, `faces_box`, `faces_contour`,
   `texts`, `animals`, `poses3d`, `barcodes`, `animalposes`, `humans`, and
   `frames`. Tables that don't exist are skipped, so start with `poses` and
   `frames`. Each fills with a header row and one row per joint / point /
   detection; `frames` holds the latest width, height and n per address.
5. Point a TrackOSC sender at this machine's IP, port 9527 (or run
   `swift run poseiosc-testsend 127.0.0.1 9527` from the repository, or
   `python3 Examples/Python/trackosc_testsend.py` without Xcode). The tables
   update live.
6. To get channels: **DAT to CHOP** on `poses` with the `x`, `y`, `c` columns
   selected, one sample per row (row = joint, see the `name` column).
7. To draw: a **Script SOP** with `trackosc_script_sop.py` as its callbacks,
   inside a Geometry COMP with a **Line MAT**, gives the body skeleton as
   line geometry in normalised coordinates; a Camera COMP + Render TOP shows
   it. Change `TABLE`/`COUNT` in the script for hands or animals.

## Table layouts

| Table | Columns |
|---|---|
| `poses`, `hands`, `faces`, `animalposes` | `det joint name x y c conf` – pixels in the sent frame, origin top-left; `c == 0` means missing |
| `texts`, `animals` | `det conf left top width height label` |
| `humans` | `det conf left top width height` |
| `faces_box` | `det conf left top width height roll yaw pitch` (degrees) |
| `faces_contour` | `det point x y conf` – an open jawline polyline; a face with no contour has no rows |
| `poses3d` | `det joint name x y z px py conf bodyHeight` – x/y/z metres (Vision camera space), px/py pixels |
| `barcodes` | `det conf left top width height tl_x tl_y tr_x tr_y br_x br_y bl_x bl_y symbology payload` |
| `camerainfo` | `key value` rows: width, height, orientation (0/90/180/270), facing (0 back, 1 front), time |
| `frames` | `address width height n time` |

Joint orders and edge lists: [`Examples/SKELETONS.md`](../SKELETONS.md).
Wire format: the [root README](../../README.md#osc-wire-format).

## Verification

The parser is exercised outside TouchDesigner by
`python3 -m unittest discover tests` (stubbing `op()` and `mod`). The network
recipe was written from TouchDesigner's documentation, not run in
TouchDesigner by the author – if you build it, please open an issue or pull
request with the TouchDesigner version you used (and a `.toe` would be very
welcome).
