# TrackOSC receiver example for Python

Three small scripts and a parser package:

| File | What it does |
|---|---|
| [`trackosc_receiver.py`](trackosc_receiver.py) | A pygame window drawing all twelve TrackOSC messages – skeletons, landmarks, boxes, barcode quads, the 3D skeleton (via its pixel projections) – with the same coordinate guides as the native receiver, plus a top-down minimap of the 3D poses. |
| [`trackosc_print.py`](trackosc_print.py) | Headless: one line per message. The smallest possible starting point for your own receiver. |
| [`trackosc_testsend.py`](trackosc_testsend.py) | Sends a synthetic scene of all twelve messages at 30 fps – test any receiver in this repository without a camera or Xcode. |
| [`trackosc/`](trackosc/) | `parse_message(address, args)` → dataclasses (`Keypoints`, `Box`, `FaceBox`, `Contour`, `Pose3D`, `Barcode`, `CameraInfo`), and the joint orders / edge lists / colours. |

## Setup

```bash
cd Examples/Python
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## Run

```bash
python3 trackosc_receiver.py          # window, port 9527
```

```bash
python3 trackosc_print.py             # headless
```

Point a TrackOSC sender at this machine's IP, port 9527 – or, in another
terminal, send the synthetic scene:

```bash
python3 trackosc_testsend.py 127.0.0.1 9527
```

`--landscape` sends 1280×720 frames, `--only poses,hands,poses3d` limits the
kinds, `--rate 10` slows it down. Only one program can listen on a port, so
quit the native TrackOSC Receiver first.

## Use the parser in your own code

```python
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
from trackosc import parse_message, Keypoints, visible

def on_message(address, *args):
    frame = parse_message(address, args)      # None for addresses TrackOSC doesn't define
    if frame and address == "/poses/arr":
        for pose in frame.detections:         # Keypoints(confidence, points)
            nose = pose.points[0]             # Point(x, y, c) in pixels, origin top-left
            if visible(nose):                 # c == 0 means missing
                print(nose.x / frame.frame_w, nose.y / frame.frame_h)   # normalised

dispatcher = Dispatcher()
dispatcher.set_default_handler(on_message)
server = BlockingOSCUDPServer(("0.0.0.0", 9527), dispatcher)
server.max_packet_size = 65536   # /faces/arr with several faces exceeds python-osc's 8 KB default
server.serve_forever()
```

Joint orders and edge lists are in `trackosc/skeletons.py` (a copy of
[`Examples/SKELETONS.md`](../SKELETONS.md)); the wire format is documented in
the [root README](../../README.md#osc-wire-format).

## Tests

```bash
python3 -m unittest discover tests
```

Verified: parser tests, `trackosc_testsend.py` → `trackosc_print.py` on
loopback, the pygame receiver against both this sender and the Swift
`poseiosc-testsend`, on Python 3.14 with python-osc 1.9 and pygame-ce 2.5.
