# TrackOSC receiver example for SuperCollider

[`TrackOSCReceiver.scd`](TrackOSCReceiver.scd) parses all twelve TrackOSC
messages with one `OSCdef` per address, **sonifies** the tracking (one saw
voice per detected body — nose x → pitch, nose y → loudness — and a
band-passed noise voice per hand whose cutoff follows the wrist height), and
**draws** everything in a `UserView` with the same colours and coordinate
guides as the native receiver.

## Run

1. Open the file in the SuperCollider IDE (3.12 or newer).
2. Boot the server (`Cmd/Ctrl-B`) for sound — parsing and drawing work
   without it.
3. Select all and evaluate (`Cmd/Ctrl-Enter`). A window opens and sclang
   starts listening on UDP **9527** in addition to its usual 57120.
4. Point a TrackOSC sender at this machine's IP, port 9527 — or send the
   synthetic scene from a terminal:

```bash
cd PoseioscShared && swift run poseiosc-testsend 127.0.0.1 9527
```

(or `python3 Examples/Python/trackosc_testsend.py` without Xcode.) Only one
program can listen on a port, so quit the native TrackOSC Receiver first.
Closing the window frees the synths.

## Use the data in your own patch

Latest frames sit in `~trackosc`, keyed by address, each an Event
`(frameW:, frameH:, detections:, at:)`; `~trackoscFresh.('/poses/arr')`
returns the frame only if it arrived in the last 0.5 s. Keypoint detections
are `(conf:, points: [[x, y, c] × n])` in pixels of the sent frame (origin
top-left; `c == 0` means missing); `/poses3d/arr` joints are
`[x, y, z, px, py]` (metres, then pixels); barcodes carry `corners`
(TL, TR, BR, BL), `symbology` and `payload`.

```supercollider
// Map the first body's nose to a control value, 0…1 across the frame:
~trackoscFresh.('/poses/arr') !? { |f|
    var nose = f.detections[0].points[0];
    if(nose[2] > 0) { (nose[0] / f.frameW).postln };
};
```

Joint orders and edge lists: [`Examples/SKELETONS.md`](../SKELETONS.md);
wire format: the [root README](../../README.md#osc-wire-format).

## Verification

Written against the SuperCollider 3.13 class library documentation and
checked by reading, not run by the author (SuperCollider isn't installed on
the development machine). If you run it, please open an issue or pull
request with the SuperCollider version you used and anything that needed
changing.
