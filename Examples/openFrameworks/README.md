# TrackOSC receiver example for openFrameworks

`TrackOSCReceiver/` is an openFrameworks app (0.11 or newer, C++17) using
**ofxOsc** (bundled with openFrameworks):

| File | What it does |
|---|---|
| `src/TrackOSCParser.h/.cpp` | `parseFrame(ofxOscMessage)` → a `Frame` of plain structs for all twelve messages; no drawing, reusable as-is. |
| `src/TrackOSCSkeletons.h` | Joint orders, edge lists, colours. |
| `src/ofApp.h/.cpp` | 2D view of everything (like the Processing reference sketch) and a 3D view of `/poses3d/arr` with an `ofEasyCam` over a floor grid. |

Keys: `2` / `3` switch views, `G` toggles the guides, `R` resets the 3D camera.

## Build

1. Copy `TrackOSCReceiver/` into `<openFrameworks>/apps/myApps/` (the
   `Makefile` and `config.make` expect `OF_ROOT` three levels up).
2. Either open it in the **projectGenerator** (Import, then Update) to get an
   Xcode / Visual Studio project, or on macOS/Linux:

```bash
cd <openFrameworks>/apps/myApps/TrackOSCReceiver && make -j && make RunRelease
```

3. Point a TrackOSC sender at this machine's IP, port 9527 – or send the
   synthetic scene from a terminal:

```bash
cd PoseioscShared && swift run poseiosc-testsend 127.0.0.1 9527
```

(or `python3 Examples/Python/trackosc_testsend.py` without Xcode.) Only one
program can listen on a port, so quit the native TrackOSC Receiver first.

## Use the parser in your own app

```cpp
#include "TrackOSCParser.h"
// in update():
while (receiver.hasWaitingMessages()) {
    ofxOscMessage m; receiver.getNextMessage(m);
    if (m.getAddress() == "/poses/arr") {
        auto frame = trackosc::parseFrame(m);            // throws on malformed input
        for (auto& pose : frame.keypoints) {             // Keypoints{confidence, points}
            auto& nose = pose.points[0];                 // pixels in the sent frame, origin top-left
            if (trackosc::visible(nose)) { /* nose.x / frame.frameW … */ }
        }
    }
}
```

Joint orders: [`Examples/SKELETONS.md`](../SKELETONS.md); wire format: the
[root README](../../README.md#osc-wire-format).

## Caveats

- ofxOsc's bundled oscpack has a fixed receive buffer (4096 bytes in some
  openFrameworks releases: `addons/ofxOsc/libs/oscpack/src/ip/posix/UdpSocket.cpp`).
  `/faces/arr` with four or more faces exceeds it and is dropped; raise
  `IP_MTU_SIZE`/the buffer there if you need many faces, or turn Face off
  on the sender.
- **Verification:** written against the openFrameworks 0.12 API and read
  carefully, but not compiled by the author (openFrameworks isn't installed
  on the development machine). If you build it, please open an issue or pull
  request with your openFrameworks version and any fixes.
