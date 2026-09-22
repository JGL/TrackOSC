# TrackOSC receiver example for Max/MSP

| File | What it does |
|---|---|
| [`TrackOSCReceiver.maxpat`](TrackOSCReceiver.maxpat) | Receives on UDP 9527, parses with the `[js]` below, draws every message into a `[jit.lcd]` → `[jit.pwindow]`, and sonifies the first body: nose x → pitch, nose y → loudness, left-wrist height → the cutoff of a filtered noise voice. |
| [`trackosc.parse.js`](trackosc.parse.js) | A `[js]` object (ES5, Max 8; `[v8]` in Max 9 runs it unchanged) that parses all twelve TrackOSC messages and emits three easy-to-`[route]` streams plus `[jit.lcd]` drawing commands. |

## Run

1. Keep both files in the same folder and open `TrackOSCReceiver.maxpat`
   (Max 8.6 or newer).
2. Turn on audio (`ezdac~`) and raise the `gain~` slider.
3. Point a TrackOSC sender at this machine's IP, port 9527 – or send the
   synthetic scene from a terminal:

```bash
cd PoseioscShared && swift run poseiosc-testsend 127.0.0.1 9527
```

(or `python3 Examples/Python/trackosc_testsend.py` without Xcode.) Only one
program can listen on a port, so quit the native TrackOSC Receiver first.

## Why `[js]` rather than `[route]`/`[zl]`

`/faces/arr` alone is 232 atoms per face and `/faces/contour` carries a
per-face point count; unpicking that with `[zl slice]`/`[zl nth]` works but
becomes a wall of objects. The `[js]` keeps the parsing in forty readable
lines and hands you tidy lists instead:

| Outlet | Stream | Example |
|---|---|---|
| 0 | camera info | `camerainfo 720 1280 90 1` (width, height, orientation, facing) |
| 1 | keypoints | `pose 0 nose 0.52 0.31 0.94` – kind, detection index, joint name, x and y **normalised 0…1** (origin top-left), confidence. Kinds: `pose`, `hand`, `face` (joints numbered 0–75), `animalpose`, and `pose3d 0 root xN yN x y z` with x/y/z in **metres**. Missing keypoints (confidence 0) are not sent. |
| 2 | boxes | `text 0 0.1 0.65 0.35 0.05 HELLO` – kind, index, left/top/width/height normalised, then the label (`animal`, `human`, `facebox` with roll/yaw/pitch degrees, `barcode` with symbology and payload) |
| 3 | drawing | `[jit.lcd]` commands on each `bang` |

So `[route pose] → [route 0] → [route nose] → [unpack f f f]` gives you the
first body's nose as three floats, which is exactly what the patch does.
Send `size 1280 720` to the `[js]` if you change the `[jit.lcd]` size.

Joint names: [`Examples/SKELETONS.md`](../SKELETONS.md); wire format: the
[root README](../../README.md#osc-wire-format).

## Verification

The `.maxpat` is generated JSON, checked automatically for valid syntax and
for every patch cord pointing at an existing outlet/inlet. Max isn't
installed on the development machine, so neither file has been run in Max
by the author – if you try it, please open an issue or pull request with
your Max version and anything that needed changing.
