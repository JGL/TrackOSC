# TrackOSC receiver example for p5.js

Browsers can't open UDP sockets, so this example has two halves:

| Part | What it does |
|---|---|
| [`bridge/`](bridge/) | **trackosc-bridge**, a ~100-line Node program: listens for OSC on UDP 9527 and relays every message to browsers as JSON over WebSocket (`ws://localhost:8765`). It also serves the sketch on `http://localhost:8080`. |
| [`sketch/`](sketch/) | A p5.js sketch drawing all fifteen TrackOSC messages – mirroring the Processing reference sketch – plus [`trackosc-client.js`](sketch/trackosc-client.js), a dependency-free parser/client you can drop into any web page (p5 or not). |

## Run

Needs [Node.js](https://nodejs.org) 20 or newer.

```bash
cd Examples/p5js/bridge
npm install
npm start
```

Then open <http://localhost:8080> in a browser and point a TrackOSC sender at
this machine's IP, port 9527 – or send the synthetic scene from another
terminal:

```bash
cd PoseioscShared && swift run poseiosc-testsend 127.0.0.1 9527
```

(or `python3 Examples/Python/trackosc_testsend.py` without Xcode.)

Options: `node bridge.js --osc-port 9527 --ws-port 8765 --http-port 8080 --sketch ../sketch`.
The bridge prints per-address message rates once a second.

## Use the client in your own page

```html
<script src="trackosc-client.js"></script>
<script>
  const client = new TrackOSC.TrackOSCClient("ws://localhost:8765");
  function draw() {
    const poses = client.fresh("/poses/arr");        // null unless received in the last 500 ms
    if (poses) {
      const { sc, ox, oy } = TrackOSC.fit(poses.frameW, poses.frameH, width, height);
      for (const pose of poses.detections) {          // { confidence, points: [{x, y, c} × 17] }
        const nose = pose.points[0];                  // pixels in the sent frame, origin top-left
        if (TrackOSC.visible(nose)) circle(ox + nose.x * sc, oy + nose.y * sc, 10);
      }
    }
  }
</script>
```

Every message becomes `{address, frameW, frameH, detections, at}`;
`/camerainfo` becomes `{width, height, orientation, facing}`. Joint orders,
edge lists and colours are in [`sketch/skeletons.js`](sketch/skeletons.js)
(a copy of [`Examples/SKELETONS.md`](../SKELETONS.md)); the wire format is in
the [root README](../../README.md#osc-wire-format).

The p5.js web editor works too: paste the three sketch files into a project
and keep the bridge running locally (browsers treat `ws://localhost` as a
secure context).

## Tests

```bash
cd Examples/p5js/bridge && npm test
```

Verified: `npm test` (bridge decoding + client parsing), and the sketch in a
browser against both `trackosc_testsend.py` and the Swift `poseiosc-testsend`,
with Node 26, osc 2.4 and ws 8.
