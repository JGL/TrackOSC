# TrackOSC

<p align="center">
  <img src="Images/icon-ios-sender.png" width="128" alt="TrackOSC iOS sender app icon">&nbsp;&nbsp;
  <img src="Images/icon-mac-sender.png" width="128" alt="TrackOSC Sender macOS app icon">&nbsp;&nbsp;
  <img src="Images/icon-mac-receiver.png" width="128" alt="TrackOSC Receiver macOS app icon">
</p>
<p align="center"><em>TrackOSC for iOS&ensp;·&ensp;TrackOSC Sender for macOS&ensp;·&ensp;TrackOSC Receiver for macOS</em></p>

Live camera → Apple Vision tracking → OSC. TrackOSC streams (almost) all of
[Apple's Vision framework](https://developer.apple.com/documentation/vision)
detection results — body poses in 2D and 3D, hand poses, face landmarks,
text, animals (boxes and skeletons), people, and barcodes — over the network
as [OSC (OpenSoundControl)](https://opensoundcontrol.stanford.edu) messages,
from an iPhone or a Mac, and visualises them in a companion receiver app.

TrackOSC (formerly Poseiosc) is a native-Swift successor to
[VisionOSC](https://github.com/LingDong-/VisionOSC) by LingDong-
(itself a successor to [PoseOSC](https://github.com/LingDong-/PoseOSC)) and
speaks **exactly the same OSC wire format**, so existing VisionOSC/PoseOSC
receivers (Processing, TouchDesigner, Max/MSP, openFrameworks…) work unchanged.

Three apps plus open receiver examples for eight creative-coding environments:

- **TrackOSC** for iOS (iOS 18+, SwiftUI): live camera → Vision → OSC over UDP,
  with on-screen tracking overlays, per-detector toggles, front/back camera
  switch, portrait/landscape support with an orientation lock for mounted
  rigs, and Bonjour discovery of receivers.
- **TrackOSC Sender** (macOS 15+, SwiftUI): the same tracking pipeline running
  on a Mac camera — built-in, external webcam, or an iPhone via Continuity
  Camera — with a camera picker and a rig-rotation setting for cameras
  mounted sideways.
- **TrackOSC Receiver** (macOS 15+, SwiftUI): listens on UDP (default port
  9527), draws skeletons/landmarks/boxes with coordinate guides, switches to
  an orbitable 3D view for the 3D body poses, shows per-address message
  rates and a log, and advertises itself on the local network so senders
  can find it.
- **[Receiver examples](Examples/README.md)** for Processing, Python, p5.js,
  TouchDesigner, Max/MSP, Pure Data, openFrameworks and SuperCollider: each
  is a complete, hackable receiver of every TrackOSC message — the same
  drawing (or a sonification) as the native receiver — so you can start
  making software on the platform you already use, without touching the
  Apple stack.

> **A note on the receiver examples.** Only the **Processing**, **Python**
> and **p5.js** examples have been run end-to-end by the maintainer; the
> TouchDesigner parser is unit-tested but its network recipe hasn't been
> built in TouchDesigner, and the **Max/MSP**, **Pure Data**,
> **openFrameworks** and **SuperCollider** examples were written from those
> platforms' documentation and checked mechanically (valid patch files,
> consistent wiring) but never opened in the tool itself, because none of
> them is installed on the development machine. Treat those as careful
> first drafts: they follow the same parsing pattern as the verified ones,
> but expect to fix small things. If you try one, please
> [open an issue or pull request](https://github.com/JGL/TrackOSC/issues)
> saying which version you used and what changed — that is the most useful
> contribution this repository can get right now. The per-platform status
> is tabulated in [`Examples/README.md`](Examples/README.md).

The Mac apps are downloadable, notarised builds; the iOS app is
[free on the App Store](https://apps.apple.com/app/trackosc/id6795593815)
(or built from source with your own developer account); the Processing
sketch just needs the free [Processing](https://processing.org) editor.

<p align="center">
  <img src="Images/screenshot-mac-sender.jpg" width="90%" alt="TrackOSC Sender on macOS tracking a person at 30 fps: body-pose skeleton in green, hand skeleton in orange, face bounding box, jawline contour, and landmark points in blue, with detector toggle chips and the destination address overlaid on the live camera view">
</p>
<p align="center"><em>The macOS sender tracking body, hand, and face at 30 fps, streaming OSC to <code>127.0.0.1:9527</code>.</em></p>

<p align="center">
  <img src="Images/screenshot-mac-receiver.png" width="90%" alt="TrackOSC Receiver on macOS drawing the received skeleton, hand, and face landmarks on a black canvas with coordinate guides, next to a panel of per-address message rates at 30 Hz, camera info, and a live message log">
</p>
<p align="center"><em>The macOS receiver drawing the same scene from the OSC stream alone — with per-address
message rates, camera info, and a live log.</em></p>

<p align="center">
  <img src="Images/screenshot-ios-sender.jpg" width="28%" alt="TrackOSC on iPhone tracking a person's face and a peace-sign hand gesture, with face box, jawline contour and landmarks in blue, hand skeleton in orange, body pose in green, and the detector chips along the bottom">
  &nbsp;&nbsp;
  <img src="Images/screenshot-processing-receiver.png" width="44%" alt="The TrackOSC Processing receiver sketch drawing the received face landmarks, jawline contour, hand skeleton, body pose, and a recognised-text box on a black canvas with coordinate guides">
</p>
<p align="center"><em>Left: the iOS sender. Right: the open Processing (oscP5) receiver sketch drawing the
same wire format — no Apple stack required.</em></p>

## Quick start without building anything

All downloads are signed and notarised — no Gatekeeper hoops.

- **Mac receiver**: download `TrackOSCReceiver-<version>-macOS.zip` from the
  [Releases page](https://github.com/JGL/TrackOSC/releases), unzip, and open.
  Allow the **Local Network** prompt on first launch.
- **Mac sender**: download `TrackOSCSender-<version>-macOS.zip` from the same
  Releases page — the full tracking pipeline running on a Mac camera
  (built-in, external webcam, or your iPhone via Continuity Camera). Allow
  the **Camera** and **Local Network** prompts. Pick the camera, a rig
  rotation (for cameras mounted sideways), and the destination in its
  settings — receivers on the network appear automatically. To try
  everything on one Mac, run sender and receiver together and send to
  `127.0.0.1`.
- **iPhone sender**: get [TrackOSC on the App Store](https://apps.apple.com/app/trackosc/id6795593815)
  (free, iOS 18+).
- **Receiver examples**: no Apple anything required — open the
  [Processing sketch](Examples/Processing/TrackOSCReceiver/TrackOSCReceiver.pde)
  in [Processing](https://processing.org) with the **oscP5** library, run
  the [Python](Examples/Python/) or [p5.js](Examples/p5js/) receiver, or
  pick TouchDesigner, Max/MSP, Pure Data, openFrameworks or SuperCollider
  from [`Examples/`](Examples/README.md). See
  [Receiver examples](#receiver-examples) for details.

Everything below is only needed if you want to build from source.

## Requirements (building from source)

- Xcode 16 or newer (with the iOS 18 and macOS 15 SDKs)
- A Mac running macOS 15 (Sequoia) or newer
- For the iOS sender: an iPhone running iOS 18 or newer
- An [Apple developer account](https://developer.apple.com) (the free tier works)
- Sender and receiver devices on the same Wi-Fi network (guest/hotel networks
  often block device-to-device traffic — see Troubleshooting)

All dependencies are Swift Packages resolved automatically by Xcode
([swift-osc](https://swiftpackageindex.com/orchetect/swift-osc) and the local
`PoseioscShared` package). Nothing else to install.

## Building the macOS receiver

1. Open `TrackOSC.xcodeproj` in Xcode.
2. Select the **TrackOSCReceiver** scheme, destination **My Mac**.
3. Signing: Xcode may ask you to pick a team — go to the target's
   **Signing & Capabilities** tab and select your team (personal is fine).
4. Run (⌘R).
5. First launch: macOS asks for **Local Network** permission — allow it, or
   the receiver can't be discovered (and on some setups can't receive at all).
   If the macOS firewall prompts about incoming connections, allow those too.

The toolbar shows the listening port (default **9527**) and the Bonjour name
it's advertising. You can change the port and press **Restart**.

## Building the macOS sender

Same as the receiver, with the **TrackOSCSenderMac** scheme. First launch
asks for **Camera** and **Local Network** permission — both are needed. In
its settings (gear icon): pick a camera (external webcams and iPhones via
Continuity Camera appear automatically), set **Rig rotation** if the camera
is mounted sideways, and choose a destination — discovered receivers are one
click. Send to `127.0.0.1` to feed a receiver on the same Mac.

## Building the iOS sender

1. In the same project, select the **TrackOSCSender** scheme and your iPhone
   as the destination (connect it by cable the first time).
2. In the **PoseioscSender** target's **Signing & Capabilities** tab, select
   your team. (Target and bundle-ID names keep the historical "Poseiosc" —
   bundle IDs are welded to App Store Connect and to users' granted
   permissions, so they deliberately never changed with the rename.) If
   you're building from source rather than installing from the App Store, also
   change the bundle identifier prefix `com.joelgethinlewis` to something of
   your own (e.g. `com.yourname.trackosc`) — either in Signing &
   Capabilities, or by editing `bundleIdPrefix` in `project.yml` and running
   `xcodegen generate`.
3. Run (⌘R). With a free developer account the app must be re-signed every
   7 days; paid accounts get a year.
4. On the iPhone, if the app won't launch: **Settings → General →
   VPN & Device Management** → trust your developer certificate.
5. First launch prompts: allow **Camera**, and allow **Local Network**
   (needed both for Bonjour discovery and for sending UDP to your Mac).
   If you decline Local Network by accident: Settings → Privacy & Security →
   Local Network → enable TrackOSC.

## Using it

1. Start the receiver on a Mac.
2. Start a sender (iPhone or Mac). In its settings (gear icon), the receiver
   should appear under **Discovered receivers** within a second or two — tap
   it. (Or type an IP and port manually — senders can also target
   TouchDesigner, Max/MSP, Processing, etc. on any port.)
3. Point the camera at a person: a skeleton appears on the sender's overlay
   and, live, on the receiver's canvas.
4. Toggle detectors with the chips along the bottom (2D Body / 3D Body /
   Hand / Face / Text / Animal / Animal Pose / Human / Barcode — the row
   scrolls sideways on the iPhone). More detectors = lower frame rate;
   2D Body + Hand + Face is the comfortable default. **3D Body** runs in its
   own lane at its own, lower rate so it never slows the other detectors;
   its rate is shown in Settings → Statistics. The status capsule shows
   destination, transmitted frame size, and processed fps.
5. Selfie-style previews are mirrored by default (like the Camera app) so
   they feel natural — but the OSC coordinates sent to receivers are
   **always unmirrored**, matching VisionOSC. Turn the mirror off in the
   sender's settings if you want the screen to match the receiver exactly.

### Camera orientation

Tracking quality is best when the declared orientation matches how the
camera is actually held, because Vision then analyses unrotated frames.

- **iPhone — Auto (default)**: follows the device as you rotate it between
  portrait and landscape; the transmitted frame dimensions swap accordingly
  (e.g. 720×1280 ↔ 1280×720).
- **iPhone — Portrait / Landscape Left / Landscape Right** (Settings →
  Camera): locks the assumed orientation. Use this when the phone is
  **mounted** — on a tripod, clamped sideways, or lying flat — because
  automatic detection fails when the phone is flat. If a locked landscape
  preview appears upside down, pick the other landscape option.
- **Mac — Rig rotation** (0°/90°/180°/270°): Mac cameras don't rotate on
  their own, so declare how the camera is physically mounted instead.

The current orientation and dimensions are always broadcast in the
`/camerainfo` OSC message and shown in the sender's status capsule and the
receiver's canvas.

### Testing without a camera

The shared package includes two CLI tools (run from `PoseioscShared/`):

```bash
swift run poseiosc-testsend 127.0.0.1 9527
```

sends synthetic animated frames of all twelve message types — point it at
the receiver and you should see a walking stick figure, a waving hand, a
face ring with box and jawline, a "HELLO" text box, a "Cat" box, a 3D
figure two metres from the camera (switch the receiver to **3D**), a QR
code, a quadruped skeleton, and a human box. Add `--landscape` to send
landscape-oriented frames instead of portrait. Without Xcode,
`python3 Examples/Python/trackosc_testsend.py` sends the same scene.

```bash
swift run poseiosc-testlisten 9527
```

is a headless decoder that prints one line per received message (quit the
receiver app first — only one process can bind the port).

### Receiver examples

[`Examples/`](Examples/README.md) holds a complete receiver for every
TrackOSC message in eight environments — FLOSS starting points for modding
and tinkering with no Apple toolchain required. Each parses all twelve
messages, draws (or sonifies) them, and shows the same coordinate guides as
the native receiver; joint orders and edge lists are shared via
[`Examples/SKELETONS.md`](Examples/SKELETONS.md).

- **[Processing](Examples/Processing/)** (oscP5): the 2D reference sketch,
  plus a P3D sketch drawing the 3D body poses in real 3D.
- **[Python](Examples/Python/)** (python-osc + pygame): a parser package, a
  window, a headless printer, and a synthetic sender.
- **[p5.js](Examples/p5js/)**: a Node bridge (browsers can't receive UDP)
  and a sketch; the client works in any web page.
- **[TouchDesigner](Examples/TouchDesigner/)**: OSC In DAT callbacks that
  fill Table DATs, a Script SOP, and a network recipe.
- **[Max/MSP](Examples/Max/)**: a `[js]` parser, a drawing patch, and a
  sonification.
- **[Pure Data](Examples/PureData/)** (vanilla): parse and joint-picking
  abstractions plus a sonification demo.
- **[openFrameworks](Examples/openFrameworks/)** (ofxOsc): a reusable C++
  parser with 2D and 3D views.
- **[SuperCollider](Examples/SuperCollider/)**: OSCdefs, sonification, and a
  drawing window.

The Processing, Python and p5.js examples were run by the maintainer; the
others were written from their platforms' documentation and are waiting for
someone with that tool installed to confirm them — pull requests welcome.

### Hiding the video

Both senders have a **Hide video preview** option (the eye button on the
main screen, or the toggle in Settings): the camera and OSC output keep
running, but the screen shows only the tracking overlay on black — useful
on stage or in installations where the raw camera feed shouldn't be visible.

## Distributing the iOS sender via TestFlight

If you have a **paid** Apple Developer Program membership, you can put the
sender on TestFlight so testers (e.g. students) install it from a link —
no Xcode needed on their side.

One-time setup:

1. Sign in at [App Store Connect](https://appstoreconnect.apple.com) →
   **Apps → ＋ → New App**: platform iOS, a name (e.g. "TrackOSC"), your
   bundle ID (register it under **Certificates, IDs & Profiles** or let
   Xcode's signing pane register it first), any SKU string.
2. In Xcode, select the **TrackOSCSender** scheme with your team set.

Per release:

1. Bump `CURRENT_PROJECT_VERSION` in `project.yml` (every upload needs a
   higher build number) and run `xcodegen generate` — or edit the build
   number in Xcode's target General tab.
2. Select destination **Any iOS Device (arm64)** → **Product → Archive**.
3. In the Organizer window: **Distribute App → TestFlight & App Store →
   Upload** (accept the defaults).
4. In App Store Connect → your app → **TestFlight** tab: wait a few minutes
   for processing, then either
   - add **Internal Testers** (up to 100 App Store Connect users — instant), or
   - create an **External** group and enable a **public link** (up to 10,000
     testers — ideal for a class; the first build needs a one-off Beta App
     Review, usually a day or two).
5. Testers install the **TestFlight** app from the App Store and open your
   public link on the iPhone. Builds expire after 90 days — upload a new one
   before term ends!

The project already sets `ITSAppUsesNonExemptEncryption` to false (the app
contains no custom cryptography), so uploads skip the export-compliance
question.

## Releasing the macOS apps (maintainers)

`Scripts/release.sh` archives **both** macOS apps (receiver and sender),
signs them with your Developer ID, notarises and staples them, and publishes
the zips as one GitHub Release — so end users can download and double-click
with no Gatekeeper friction.

One-time setup:

1. A **Developer ID Application** certificate: Xcode → Settings → Accounts →
   your team → Manage Certificates → ＋.
2. Notary credentials in your keychain (use an
   [app-specific password](https://appleid.apple.com)):

```bash
xcrun notarytool store-credentials poseiosc-notary --apple-id you@example.com --team-id YOURTEAMID --password your-app-specific-password
```

3. The [GitHub CLI](https://cli.github.com) authenticated (`gh auth login`).

Then, per release — bump `MARKETING_VERSION` in `project.yml`, run
`xcodegen generate`, commit, and:

```bash
POSEIOSC_TEAM_ID=YOURTEAMID Scripts/release.sh
```

Add `--dry-run` to build/notarise without publishing.

## Coordinate system

Everything on the wire uses one convention — the same one VisionOSC uses:

```
(0,0) ──────────► x                width
  │  ┌───────────────────────────────┐
  │  │                               │
  ▼  │        pixels, y down         │ height
  y  │                               │
     └───────────────────────────(w,h)
```

- **Pixels**, not normalised: divide by the frame width/height from the
  message header (or `/camerainfo`) to normalise.
- **Origin top-left, y grows downward** (screen convention, not math
  convention).
- **Never mirrored.** The selfie-mirror option only flips the phone's
  *display*; wire coordinates are always the unmirrored scene.
- **Dimensions follow orientation**: portrait sends 720×1280, landscape
  1280×720. Listen to `/camerainfo` and your mapping code needs no
  special-casing:

```java
// Processing: map a TrackOSC point into your sketch window
float sx = x / frameW * width;   // frameW/frameH from the message header
float sy = y / frameH * height;
```

(For a full working example — parsing, skeletons, coordinate guides — see
[`Examples/Processing/TrackOSCReceiver`](Examples/Processing/TrackOSCReceiver/TrackOSCReceiver.pde).)

- A keypoint that wasn't detected arrives as `x=0, y=frameHeight,
  confidence=0` — always filter on `confidence == 0`.

## OSC wire format

Byte-compatible with VisionOSC. All messages are sent unbundled over UDP, one
per enabled detector per processed frame, **including when nothing is
detected** (header-only). Coordinates are as described above.

**`/camerainfo`** (TrackOSC addition; VisionOSC receivers ignore it) —
sent with every processed frame:

| # | Type | Value |
|---|------|-------|
| 0 | int32 | frame width in pixels |
| 1 | int32 | frame height in pixels |
| 2 | int32 | orientation: 0 = landscape, 90 = portrait, 180 = landscape flipped, 270 = portrait upside-down |
| 3 | int32 | camera facing: 0 = back, 1 = front |

Every message begins with the same header:

| # | Type | Value |
|---|------|-------|
| 0 | int32 | frame width (oriented pixels, e.g. 720) |
| 1 | int32 | frame height (e.g. 1280) |
| 2 | int32 | number of detections `n` (capped at 32) |

Then, per detection:

**`/poses/arr`** — `float` confidence, then 17 joints × (`float` x, `float` y,
`float` confidence). Joint order (PoseNet order): nose, leftEye, rightEye,
leftEar, rightEar, leftShoulder, rightShoulder, leftElbow, rightElbow,
leftWrist, rightWrist, leftHip, rightHip, leftKnee, rightKnee, leftAnkle,
rightAnkle.

**`/hands/arr`** — `float` confidence, then 21 joints × (x, y, confidence).
Order: wrist; thumb CMC, MP, IP, tip; index MCP, PIP, DIP, tip; middle …;
ring …; pinky … .

**`/faces/arr`** — `float` confidence, then 76 landmark points ×
(x, y, precisionEstimate), in Vision's constellation order.

**`/texts/arr`** — `float` confidence, `float` left, `float` top,
`float` width, `float` height, `string` recognised text.

**`/animals/arr`** — `float` confidence, `float` left, `float` top,
`float` width, `float` height, `string` label (`"Cat"` or `"Dog"`).

A joint/point that wasn't detected is sent as `x=0, y=frameHeight,
confidence=0` (VisionOSC's convention) — filter on `confidence == 0`.

### Face boundary messages (TrackOSC addition, v1.3)

VisionOSC's `/faces/arr` carries only the 76 landmark points — no face
boundary. TrackOSC adds two messages (VisionOSC receivers ignore them; the
five messages above are untouched). Both start with the standard
width/height/n header, and both list the **same faces in the same order**,
so index i in one matches index i in the other. (`/faces/arr` applies a
stricter landmark check and can, in rare cases, contain fewer faces — don't
assume its indices line up with these.)

**`/faces/box`** — per face, 8 floats (fixed stride: face *i* starts at
argument `3 + i×8`):

| Type | Value |
|------|-------|
| float | confidence |
| float × 4 | bounding box: left, top, width, height (pixels, origin top-left) |
| float × 3 | head rotation: roll, yaw, pitch in **degrees** (0 when unavailable) |

**`/faces/contour`** — per face: `float` confidence, `int32 m` (contour
point count), then m × (`float` x, `float` y). The contour is the jawline —
an **open** polyline from ear to chin to ear; don't close it. `m` varies by
OS version (typically 17) and is 0 when Vision reports no contour for that
face — always loop on `m`, never hardcode it.

### 3D body, barcode, animal-pose and human messages (TrackOSC addition, v1.4)

Four more additive messages, each behind its own detector chip. VisionOSC
receivers ignore them; the messages above are untouched. All start with the
standard width/height/n header, and every coordinate that is a pixel uses
the same convention as everything else (oriented frame, origin top-left,
never mirrored).

**`/poses3d/arr`** — per pose (fixed stride: pose *i* starts at argument
`3 + i×87`; joint *j* of pose *i* at `3 + i×87 + 2 + j×5`):

| Type | Value |
|------|-------|
| float | confidence |
| float | estimated body height in **metres** |
| 17 × (float x, float y, float z, float px, float py) | per joint: position in **metres** in Vision's camera-relative space, then the same joint projected into the frame in **pixels** |

Joint order (Vision's 3D skeleton, root first — *not* the PoseNet order of
`/poses/arr`): root, spine, centerShoulder, centerHead, topHead,
leftShoulder, leftElbow, leftWrist, rightShoulder, rightElbow, rightWrist,
leftHip, leftKnee, leftAnkle, rightHip, rightKnee, rightAnkle. All 17 joints
are always present — there is no missing-joint sentinel. The metric space is
right-handed with the camera at the origin, x to the right and y up; z runs
along the camera's axis (the receiver's 3D view and the Processing 3D
sketch each have a single sign constant should your device report it the
other way). The pixel projections let 2D-only receivers draw the 3D
skeleton without any projection maths. On iPhone the heights are measured
using the camera's intrinsics; on a Mac they are estimated from a reference
height. `/poses3d/arr` is sent at the 3D detector's own rate, typically
lower than the other messages.

**`/barcodes/arr`** — per code: `float` confidence, `float` left, top,
width, height (axis-aligned box), then 4 × (`float` x, `float` y) — the
corners of the code in **its own orientation**, top-left, top-right,
bottom-right, bottom-left (draw them as a closed quadrilateral) — then
`string` symbology (`QR`, `EAN13`, `Code128`, `DataMatrix`, `Aztec`,
`PDF417`, `MicroQR`, …) and `string` payload (empty when none).

**`/animalposes/arr`** — per animal: `float` confidence, then 25 joints ×
(`float` x, `float` y, `float` confidence), same conventions as
`/poses/arr` including the missing-joint sentinel. Joint order: nose,
leftEye, rightEye, leftEarTop, leftEarMiddle, leftEarBottom, rightEarTop,
rightEarMiddle, rightEarBottom, neck, leftFrontElbow, leftFrontKnee,
leftFrontPaw, rightFrontElbow, rightFrontKnee, rightFrontPaw,
leftBackElbow, leftBackKnee, leftBackPaw, rightBackElbow, rightBackKnee,
rightBackPaw, tailTop, tailMiddle, tailBottom.

**`/humans/arr`** — per person: `float` confidence, `float` left, top,
width, height. A whole-body box with no skeleton — cheap, and it counts
people at distances where pose estimation gives up.

Edge lists for drawing all four skeletons, and the colours the apps use,
are in [`Examples/SKELETONS.md`](Examples/SKELETONS.md).

## Project layout

```
project.yml            XcodeGen spec (source of truth for the Xcode project)
TrackOSC.xcodeproj     Generated project (committed; users just open it)
PoseioscShared/        Swift package: wire format codec, models, skeleton
                       edge lists, coordinate mapping, CLI test tools, tests
SenderCore/            Platform-neutral sender pipeline shared by both
                       senders (Vision processing, OSC, Bonjour, overlay)
Sender/                iOS sender app shell (camera, rotation, UI)
SenderMac/             macOS sender app shell (camera picker, rig rotation)
Receiver/              macOS receiver (OSC server, 2D + 3D visualisers, log, Bonjour)
Examples/              Receiver examples: Processing, Python, p5.js, TouchDesigner,
                       Max/MSP, Pure Data, openFrameworks, SuperCollider — see
                       Examples/README.md; Examples/SKELETONS.md is the shared
                       joint-order/edge-list reference
Scripts/               Notarised-release tooling
PROMPTS_AND_DECISIONS.md   Running record of prompts and design decisions
```

Contributing: source files added/removed? Run `brew install xcodegen` once,
then `xcodegen generate` and commit both `project.yml` and the regenerated
project. Wire-format changes must keep the golden-bytes test in
`PoseioscShared/Tests` green — that test *is* the VisionOSC compatibility
contract. Run tests with `cd PoseioscShared && swift test`.

## Troubleshooting

- **Receiver never appears in a sender's list** — both devices on the same Wi-Fi?
  Many guest/campus/hotel networks enable *client isolation*, which blocks
  device-to-device traffic entirely; use a private network or a personal
  hotspot. Check Local Network permission on **both** devices, and that the
  Mac's firewall allowed TrackOSC Receiver. Verify the Mac is advertising:
  `dns-sd -B _osc._udp local.`
- **Discovered receiver won't resolve** — enter the Mac's IP manually
  (System Settings → Wi-Fi → Details → IP address).
- **Data sends but nothing draws** — confirm the port matches the receiver
  toolbar; check the receiver's total-message counter is climbing.
- **Overlay/receiver skeleton is rotated or flipped** — the sender assumes a
  portrait phone; keep the phone upright. (If it's still wrong on your device,
  please open an issue naming the iPhone model.)
- **Low frame rate** — disable Text/Animal (they're the slow ones), good
  lighting helps every detector.
- **Port 9527 already in use** — Protokol, OSC DataMonitor, or another
  receiver may be bound to it; only one process can listen per port.

## Related projects

Two other free tools turn cameras into OSC-speaking people sensors for
creative coding; each covers ground TrackOSC doesn't, and vice versa.

- **[openTSPS](https://github.com/labatrockwell/openTSPS)** — the "Toolkit
  for Sensing People in Spaces" from the LAB at Rockwell Group. A desktop
  openFrameworks/OpenCV app that runs blob and person tracking on webcams,
  **Kinect and other depth sensors**, or video files, and broadcasts the
  results as OSC, TUIO, TCP, or JSON over WebSockets. The classic choice
  for overhead or depth-camera installations that need presence, position
  and size of people rather than skeletons; it is in maintenance mode
  (built on openFrameworks 0.8), but still works and is well documented.
- **[tramontanaCV](https://tramontana.xyz)** — by Pierluigi Dalla Rosa,
  part of the Tramontana platform for prototyping interactive spaces with
  phones. An iOS app that uses the phone as a sensor, running **blob
  detection or face tracking** on its camera and sending the results over
  Wi-Fi to Processing (and, through Tramontana's libraries, to p5.js,
  JavaScript and openFrameworks). The closest precedent for TrackOSC's
  phone-as-tracker idea, with a lighter, blob-oriented output.

TrackOSC's niche next to them: Apple Vision's richer detectors — full body
skeletons in 2D and 3D, hand and face landmarks, animal skeletons, text
and barcodes — from any iPhone or Mac camera, speaking the VisionOSC wire
format so existing receivers keep working. If you need depth-camera
tracking of a whole room, reach for openTSPS; if you need the simplest
possible blob-from-a-phone, tramontanaCV; if you need skeletons and
landmarks, TrackOSC.

## Lineage & licence

Inspired by [VisionOSC](https://github.com/LingDong-/VisionOSC) and
[PoseOSC](https://github.com/LingDong-/PoseOSC) by LingDong-, which grew out
of [ofxFaceTracker](https://github.com/kylemcdonald/ofxFaceTracker) by Kyle
McDonald. OSC via [swift-osc](https://github.com/orchetect/swift-osc) by
Steffan Andrews.

MIT — see [LICENSE](LICENSE).

## Thanks

TrackOSC exists because [Golan Levin](https://flong.com) suggested building
it in the first place — a native, freely available successor to VisionOSC
that students could point at any receiver — and then test-drove every
release, sending the feedback that shaped the face boundary messages, the
Processing example, the screenshots, and the receiver examples for other
platforms. Thank you, Golan.
