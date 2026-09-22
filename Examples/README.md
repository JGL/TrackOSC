# TrackOSC receiver examples

Every folder here is a complete receiver for TrackOSC's OSC stream in a
different environment: it parses **all twelve messages** (the five
VisionOSC-compatible ones plus TrackOSC's additive `/camerainfo`,
`/faces/box`, `/faces/contour`, `/poses3d/arr`, `/barcodes/arr`,
`/animalposes/arr` and `/humans/arr`), draws or sonifies them, and is meant
to be copied and hacked. Pick the tool you already use.

| Platform | Folder | Demonstrates | Needs | Verified by the author |
|---|---|---|---|---|
| Processing | [`Processing/`](Processing/) | 2D drawing of everything with coordinate guides; a second sketch draws `/poses3d/arr` in real 3D (P3D) | Processing 4, oscP5 | **Yes** – both sketches run against the synthetic senders |
| Python | [`Python/`](Python/) | A parser package, a pygame window (2D + top-down 3D minimap), a headless printer, and `trackosc_testsend.py` – a synthetic sender of all twelve messages | Python 3, python-osc, pygame-ce | **Yes** – unit tests, loopback, window |
| p5.js | [`p5js/`](p5js/) | A Node **bridge** (UDP → WebSocket, browsers can't do UDP) and a p5.js sketch; `trackosc-client.js` works in any web page | Node 20+ | **Yes** – tests and browser |
| TouchDesigner | [`TouchDesigner/`](TouchDesigner/) | OSC In DAT callbacks that fill Table DATs per message; optional Script SOP drawing skeletons; step-by-step network recipe (`.toe` is binary, so text only) | TouchDesigner 2023+ | Parser only (mock tests) – recipe not run in TD |
| Max/MSP | [`Max/`](Max/) | A `[js]` parser emitting `[route]`-friendly streams and `[jit.lcd]` drawing; a patch that draws and sonifies | Max 8.6+ | Generated patch validated; not run in Max |
| Pure Data | [`PureData/`](PureData/) | Vanilla abstractions `[trackosc-parse]` and `[trackosc-joint]`, plus a sonification demo | Pd 0.51+ (no externals) | Generated patches linted; not run in Pd |
| openFrameworks | [`openFrameworks/`](openFrameworks/) | A reusable C++ parser, 2D drawing, and a 3D `ofEasyCam` view of `/poses3d/arr` | openFrameworks 0.11+ (ofxOsc) | Read carefully; not compiled |
| SuperCollider | [`SuperCollider/`](SuperCollider/) | `OSCdef` per address, sonification of bodies and hands, `UserView` drawing | SuperCollider 3.12+ | Read carefully; not run |

The "not run" examples were written from each environment's documentation
because those tools aren't installed on the development machine. If you run
one, please open an issue or pull request saying which version you used and
what (if anything) needed changing – that is the most useful contribution
this folder can get.

## Testing without a camera

Two synthetic senders emit the full scene (a walking figure, a waving hand,
a face with box and jawline, a HELLO text box, a Cat box, a 3D figure 2 m
from the camera, a QR code, a quadruped skeleton and a human box) at
30 fps to any receiver:

```bash
cd PoseioscShared && swift run poseiosc-testsend 127.0.0.1 9527     # needs Xcode
```

```bash
python3 Examples/Python/trackosc_testsend.py 127.0.0.1 9527          # needs python-osc only
```

Add `--landscape` for 1280×720 frames. Only one program can listen on a
port, so quit the native TrackOSC Receiver first.

## Conventions every example follows

- **Header:** each detection message starts with `int32 width, int32 height,
  int32 n`; `/camerainfo` has no `n`. Coordinates are **pixels** in that
  frame, origin top-left, never mirrored; frame size follows orientation
  (portrait 720×1280, landscape 1280×720).
- **Missing keypoints** arrive as `x=0, y=frameHeight, confidence=0` – skip
  edges that touch one.
- **Freshness:** a message kind is drawn only if received in the last 0.5 s
  (2 s for `/camerainfo`), so a switched-off detector disappears rather than
  freezing.
- **Aspect-fit:** `sc = min(W/frameW, H/frameH)` with the frame centred, so
  proportions are preserved whatever the window shape.
- **Joint orders, edge lists and colours** are in [`SKELETONS.md`](SKELETONS.md);
  every example carries a copy marked `TRACKOSC SKELETON REFERENCE v1.4`.
- The full wire format is in the [root README](../README.md#osc-wire-format).

## UDP packet sizes

`/faces/arr` is ~1.2 KB per face and `/poses3d/arr` ~350 bytes per pose; a
frame with several faces exceeds the receive buffer some OSC libraries
default to. Where it matters the examples raise it:

| Library | Default | Setting |
|---|---|---|
| python-osc | 8 KB | `server.max_packet_size = 65536` |
| Max `[udpreceive]` | 4 KB | `@maxpacketsize 65536` |
| ofxOsc (oscpack) | 4 KB in some releases | see the openFrameworks README |
| oscP5, osc.js, sclang, Pd `[netreceive]`, TouchDesigner | large enough / configurable | – |
