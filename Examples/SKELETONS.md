# TrackOSC skeleton reference

Joint orders, edge lists, corner orders and colours for every receiver
example. The source of truth is
[`PoseioscShared/Sources/PoseioscShared/Skeleton.swift`](../PoseioscShared/Sources/PoseioscShared/Skeleton.swift)
and `WireFormat.swift` next to it; the block below is copied verbatim into each
example as a comment. If it changes, update every copy — the marker line makes
stale copies easy to find:

```bash
grep -rL "SKELETON REFERENCE v1.4" Examples --include='*.pde' --include='*.py' --include='*.js' --include='*.cpp' --include='*.h' --include='*.scd' --include='*.maxpat' --include='*.pd' --include='*.md'
```

```text
TRACKOSC SKELETON REFERENCE v1.4 — source: PoseioscShared/Sources/PoseioscShared/Skeleton.swift

Indices are positions in each message's joint list; a keypoint with
confidence 0 (sent as x=0, y=frameHeight) is missing — skip edges that touch it.

/poses/arr — 17 joints (PoseNet order):
   0 nose  1 leftEye  2 rightEye  3 leftEar  4 rightEar
   5 leftShoulder  6 rightShoulder  7 leftElbow  8 rightElbow
   9 leftWrist  10 rightWrist  11 leftHip  12 rightHip
  13 leftKnee  14 rightKnee  15 leftAnkle  16 rightAnkle
  edges: (0,1) (0,2) (1,3) (2,4)  (5,6) (5,11) (6,12) (11,12)
         (5,7) (7,9)  (6,8) (8,10)  (11,13) (13,15)  (12,14) (14,16)

/hands/arr — 21 joints: 0 wrist, then 4 per finger knuckle → tip:
   1-4 thumb (CMC, MP, IP, tip)  5-8 index  9-12 middle  13-16 ring  17-20 pinky
  edges: (0,1) (1,2) (2,3) (3,4)  (0,5) (5,6) (6,7) (7,8)  (0,9) (9,10) (10,11) (11,12)
         (0,13) (13,14) (14,15) (15,16)  (0,17) (17,18) (18,19) (19,20)

/poses3d/arr — 17 joints (Vision's 3D skeleton, root first; all always present):
   0 root  1 spine  2 centerShoulder  3 centerHead  4 topHead
   5 leftShoulder  6 leftElbow  7 leftWrist
   8 rightShoulder  9 rightElbow  10 rightWrist
  11 leftHip  12 leftKnee  13 leftAnkle
  14 rightHip  15 rightKnee  16 rightAnkle
  edges: (0,1) (1,2) (2,3) (3,4)  (2,5) (5,6) (6,7)  (2,8) (8,9) (9,10)
         (0,11) (11,12) (12,13)  (0,14) (14,15) (15,16)
  per joint: x y z in metres (Vision camera space: x right, y up), px py in pixels

/animalposes/arr — 25 joints (Vision's cat/dog skeleton):
   0 nose  1 leftEye  2 rightEye
   3 leftEarTop  4 leftEarMiddle  5 leftEarBottom
   6 rightEarTop  7 rightEarMiddle  8 rightEarBottom
   9 neck
  10 leftFrontElbow  11 leftFrontKnee  12 leftFrontPaw
  13 rightFrontElbow  14 rightFrontKnee  15 rightFrontPaw
  16 leftBackElbow  17 leftBackKnee  18 leftBackPaw
  19 rightBackElbow  20 rightBackKnee  21 rightBackPaw
  22 tailTop  23 tailMiddle  24 tailBottom
  edges: (0,1) (0,2)  (1,5) (5,4) (4,3)  (2,8) (8,7) (7,6)  (0,9)
         (9,10) (10,11) (11,12)  (9,13) (13,14) (14,15)  (9,22)
         (22,16) (16,17) (17,18)  (22,19) (19,20) (20,21)  (22,23) (23,24)

/barcodes/arr — 4 corners in the code's own orientation:
   0 topLeft  1 topRight  2 bottomRight  3 bottomLeft   (draw as a closed quad)

/faces/contour — an OPEN polyline, ear → chin → ear; never close it.

Colours (sRGB), matching the native apps:
  poses        green   ( 48, 209,  88)      poses3d      mint    ( 99, 230, 226)
  hands        orange  (255, 159,  10)      animalposes  brown   (172, 142, 104)
  faces        cyan    (100, 210, 255)      humans       indigo  ( 94,  92, 230)
  texts        yellow  (255, 214,  10)      barcodes     purple  (191,  90, 242)
  animals      pink    (255,  55,  95)      guides       grey    (128, 128, 128)
```
