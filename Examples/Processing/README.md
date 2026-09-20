# TrackOSC receiver examples for Processing

Two sketches for [Processing 4](https://processing.org), both needing only the
free **oscP5** library.

| Sketch | What it does |
|---|---|
| [`TrackOSCReceiver`](TrackOSCReceiver/TrackOSCReceiver.pde) | Parses **all twelve** TrackOSC messages and draws them in 2D: body skeletons (2D, and the pixel projections of 3D), hand skeletons, face landmarks, boxes and jawline contours, text/animal boxes, animal skeletons, human boxes, barcode quads — with the same coordinate guides as the native macOS receiver. The reference for every other example in this folder. |
| [`TrackOSCReceiver3D`](TrackOSCReceiver3D/TrackOSCReceiver3D.pde) | Draws `/poses3d/arr` in real 3D (P3D): skeletons in metres over a floor grid, with the camera marked at the origin. Drag to orbit, scroll to zoom, `R` to reset. |

## Setup

1. Install oscP5: **Sketch → Import Library… → Manage Libraries…**, search
   "oscP5" (by Andreas Schlegel), Install.
2. Open either sketch and run it. Both listen on UDP port **9527** (the
   VisionOSC default). Only one program can listen on a port at a time, so
   quit the native TrackOSC Receiver first.
3. Point a TrackOSC sender at this machine's IP, port 9527 — or test without
   any camera from the repository root:

```bash
cd PoseioscShared && swift run poseiosc-testsend 127.0.0.1 9527
```

(No Xcode? `Examples/Python/trackosc_testsend.py` sends the same synthetic
scene from Python.)

## Adapting the sketches

- Wire coordinates are **pixels in the sent frame**, origin top-left, never
  mirrored; the frame size (`720×1280` portrait, `1280×720` landscape) is in
  every message header. Both sketches aspect-fit that frame into the window.
- Joint orders, edge lists and colours are in
  [`Examples/SKELETONS.md`](../SKELETONS.md); the sketches carry a copy.
- A keypoint with confidence `0` is missing — skip it (the sketches already do).
- The full wire format is documented in the
  [root README](../../README.md#osc-wire-format).
