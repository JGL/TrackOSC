# TrackOSC Privacy Policy

_Last updated: 24 August 2026_

This policy covers the TrackOSC apps: **TrackOSC** for iOS, **TrackOSC
Sender** for macOS, and **TrackOSC Receiver** for macOS.

## The short version

TrackOSC does not collect, store, or transmit any personal data. There are
no accounts, no analytics, no advertising, and no third-party services.

## Camera

The sender apps use the camera solely to run Apple's Vision framework
**on-device**, detecting body poses, hand poses, face landmarks, text, and
animals. Camera video is never recorded, never stored, and never leaves the
device. The only thing derived from the camera that is transmitted is
numerical tracking data (coordinates and confidence values), described
below.

## Face data

The sender apps use Apple's Vision framework to detect faces in the camera
feed, entirely on-device. The face data produced is numerical geometry
only: facial landmark coordinates (eyes, brows, nose, lips, jawline), a
face bounding box, and head rotation angles. The apps do not create
biometric templates or faceprints, do not perform face recognition or
identification, and cannot determine who a person is.

- **Collection and storage:** Face data is computed in memory for each
  camera frame and exists only for the duration of that frame — a fraction
  of a second. It is never written to disk, never saved, and never
  associated with any identity.
- **Use:** Face data is used for exactly two things: drawing the tracking
  overlay on the screen, and encoding numerical coordinates into OSC
  messages sent to the local-network destination the user has explicitly
  configured.
- **Sharing:** Face data is not shared with the developer or with any
  third party. It is transmitted only as numerical coordinates, only over
  the local network, and only to the receiving device the user chooses.
  There are no developer servers, and the data never touches the internet.
- **Retention and deletion:** Retention is zero. Each frame's face data is
  discarded as soon as the frame has been processed; closing the app, or
  simply the arrival of the next frame, removes it. There is nothing
  stored, and therefore nothing requiring later deletion.

## Network

The sender apps transmit tracking data as OSC (Open Sound Control) messages
over UDP **only to the destination you explicitly configure** — typically a
computer on your own local network. Nothing is sent anywhere by default,
and nothing is ever sent to the developer or to any third party.

The apps also use Bonjour to discover TrackOSC receivers on your local
network; this is standard Apple local-network service discovery and shares
no personal information.

The receiver app listens for OSC messages on a port you choose and displays
them. It stores nothing beyond the current session's on-screen log, which
is discarded when the app quits.

## Data collection

None. The apps collect no personal information, no usage analytics, and no
identifiers, and they include no third-party SDKs.

## Changes

If this policy ever changes, the updated version will be published at this
same address with a revised date.

## Contact

Questions or concerns: please open an issue at
<https://github.com/JGL/TrackOSC/issues>.
