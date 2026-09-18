# TrackOSC receiver example for Pure Data

Pd **vanilla** only — no externals. Three patches, kept in one folder:

| Patch | What it does |
|---|---|
| [`trackosc-receiver.pd`](trackosc-receiver.pd) | The demo: sonifies the first body (nose x → pitch, nose y → loudness, left-wrist height → the cutoff of a filtered noise voice), shows the nose on sliders and the camera info in number boxes, and can print raw lists so you can see what arrives. |
| [`trackosc-parse.pd`](trackosc-parse.pd) | Abstraction: `[netreceive -u -b 9527]` → `[oscparse]` → `[route …]`. Twelve outlets, one per address. |
| [`trackosc-joint.pd`](trackosc-joint.pd) | Abstraction `[trackosc-joint <joint> <detection> <pointCount>]`: picks one keypoint out of a keypoint list. Outlets: x y c (pixels) w h. |

## Run

1. Open `trackosc-receiver.pd` in Pd 0.51 or newer and turn DSP on.
2. Point a TrackOSC sender at this machine's IP, port 9527 — or send the
   synthetic scene from a terminal:

```bash
cd PoseioscShared && swift run poseiosc-testsend 127.0.0.1 9527
```

(or `python3 Examples/Python/trackosc_testsend.py` without Xcode.) Only one
program can listen on a port, so quit the native TrackOSC Receiver first.

## What comes out of `[trackosc-parse]`

`[oscparse]` turns the OSC address into symbols, so `/poses/arr 720 1280 1 …`
arrives as the list `poses arr 720 1280 1 …`; `[route poses]` then
`[route arr]` strip those, leaving the list exactly as documented in the wire
format: `w h n` then the detections. Outlets, left to right:

| Outlet | Address | Per detection (after `w h n`) |
|---|---|---|
| 0 | `/camerainfo` | `w h orientation facing` (no n) |
| 1 | `/poses/arr` | conf, 17 × (x y c) |
| 2 | `/hands/arr` | conf, 21 × (x y c) |
| 3 | `/faces/arr` | conf, 76 × (x y c) |
| 4 | `/faces/box` | conf l t w h roll yaw pitch |
| 5 | `/faces/contour` | conf m, m × (x y) — open jawline |
| 6 | `/texts/arr` | conf l t w h text |
| 7 | `/animals/arr` | conf l t w h label |
| 8 | `/poses3d/arr` | conf bodyHeight, 17 × (x y z px py) — metres then pixels |
| 9 | `/barcodes/arr` | conf l t w h, 4 × (x y), symbology payload |
| 10 | `/animalposes/arr` | conf, 25 × (x y c) |
| 11 | `/humans/arr` | conf l t w h |

Strings arrive as symbols inside the list. OSC int32s become Pd floats.

`[trackosc-joint j d count]` computes the list offset
`3 + d·(1 + 3·count) + 1 + 3·j` once from its creation arguments, splits the
list there and unpacks x, y and c; use `count` 17 for bodies, 21 for hands,
25 for animals, 76 for faces. Divide x by w and y by h (also on its outlets)
for 0…1 values, as the demo does. A keypoint with `c == 0` is missing.

Joint orders: [`Examples/SKELETONS.md`](../SKELETONS.md); wire format: the
[root README](../../README.md#osc-wire-format).

## Verification

The patches are generated text, checked automatically so every `connect`
refers to existing objects and no comment is wired. Pure Data isn't
installed on the development machine, so they have not been opened in Pd by
the author — if you run them, please open an issue or pull request with
your Pd version and anything that needed changing. One known caveat to
test: with several faces on screen `/faces/arr` exceeds 4 KB per datagram,
which some `[netreceive]` builds truncate.
