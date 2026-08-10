/**
 * TrackOSCReceiver — a Processing reference receiver for TrackOSC.
 *
 * Draws everything the TrackOSC senders emit: body-pose skeletons, hand
 * skeletons, face landmark dots, face bounding boxes + jawline contours,
 * text and animal boxes — plus the same coordinate guides the native macOS
 * receiver shows (origin, axes, frame dimensions, camera orientation).
 *
 * Requires the oscP5 library: Sketch → Import Library… → Manage Libraries →
 * search "oscP5" (by Andreas Schlegel) → Install.
 *
 * Quick start:
 *   1. Run this sketch (it listens on UDP port 9527, the VisionOSC default).
 *   2. Point a TrackOSC sender (iPhone or Mac) at this machine's IP, port 9527.
 *      Or, with no camera at all, from the TrackOSC repo run:
 *        swift run poseiosc-testsend 127.0.0.1 9527
 *
 * Coordinate system (see the README's "Coordinate system" section):
 *   - Coordinates are PIXELS in the sent frame, NOT normalized.
 *   - Origin is top-left, y grows downward (same as Processing!).
 *   - Data is never mirrored, even when the sender previews in selfie-mirror.
 *   - Frame dimensions follow orientation: portrait 720×1280, landscape 1280×720.
 *   - Map into your sketch: sx = x / frameW * width; sy = y / frameH * height
 *     (this sketch aspect-fits instead, so proportions are preserved).
 *
 * Wire format (all VisionOSC-compatible; see README "OSC wire format"):
 *   Detection messages start with: int32 frameWidth, int32 frameHeight, int32 n.
 *   /poses/arr    per pose:  float conf, then 17 × (float x, float y, float conf)
 *   /hands/arr    per hand:  float conf, then 21 × (x, y, conf)
 *   /faces/arr    per face:  float conf, then 76 × (x, y, precision)
 *   /texts/arr    per text:  float conf, float left, top, width, height, string text
 *   /animals/arr  per animal: same as texts, label "Cat"/"Dog"
 *   /camerainfo   int32 width, height, orientationDegrees, facing (no n header)
 *   /faces/box    per face:  float conf, left, top, width, height, roll°, yaw°, pitch°
 *   /faces/contour per face: float conf, int32 m, then m × (float x, float y)
 *                  — an OPEN polyline (jawline, ear → chin → ear); m varies by
 *                  OS version (typically 17) and is 0 when unavailable.
 *   A keypoint with conf == 0 is "missing" — skip it.
 *   /faces/box and /faces/contour list the same faces in the same order;
 *   /faces/arr may (rarely) contain fewer.
 *
 * Body joint order (17): nose, leftEye, rightEye, leftEar, rightEar,
 *   leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist,
 *   leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle.
 * Hand joint order (21): wrist, then 4 joints per finger (thumb, index,
 *   middle, ring, pinky), knuckle → tip.
 */

import oscP5.*;

final int PORT = 9527;

// A message kind is drawn only if received in the last 0.5 s; camera info
// stays valid for 2 s (matches the native receiver).
final int STALE_MS = 500;
final int CAMERA_INFO_STALE_MS = 2000;

// Edge lists — keep in sync with PoseioscShared/Sources/PoseioscShared/Skeleton.swift.
final int[][] BODY_EDGES = {
  {0, 1}, {0, 2}, {1, 3}, {2, 4},            // head
  {5, 6}, {5, 11}, {6, 12}, {11, 12},        // torso
  {5, 7}, {7, 9},                            // left arm
  {6, 8}, {8, 10},                           // right arm
  {11, 13}, {13, 15},                        // left leg
  {12, 14}, {14, 16}                         // right leg
};
final int[][] HAND_EDGES = {
  {0, 1}, {1, 2}, {2, 3}, {3, 4},            // thumb
  {0, 5}, {5, 6}, {6, 7}, {7, 8},            // index
  {0, 9}, {9, 10}, {10, 11}, {11, 12},       // middle
  {0, 13}, {13, 14}, {14, 15}, {15, 16},     // ring
  {0, 17}, {17, 18}, {18, 19}, {19, 20}      // pinky
};

// Colors approximating the native receiver's system colors.
color POSE_COLOR, HAND_COLOR, FACE_COLOR, TEXT_COLOR, ANIMAL_COLOR, GUIDE_COLOR;

// ---- Latest data per message kind ----
// oscEvent runs on oscP5's network thread; each kind is parsed into a fresh
// object and published by a single reference assignment, so draw() always
// sees a complete frame (the standard oscP5 pattern).
KeypointFrame poses, hands, faces;
BoxFrame texts, animals;
FaceBoxFrame faceBoxes;
ContourFrame faceContours;
CameraInfo camInfo;

OscP5 osc;

void setup() {
  size(720, 960);
  surface.setTitle("TrackOSC Receiver (Processing) — listening on " + PORT);
  POSE_COLOR = color(48, 209, 88);
  HAND_COLOR = color(255, 159, 10);
  FACE_COLOR = color(100, 210, 255);
  TEXT_COLOR = color(255, 214, 10);
  ANIMAL_COLOR = color(255, 55, 95);
  GUIDE_COLOR = color(128);
  textFont(createFont("Monospaced", 12));
  osc = new OscP5(this, PORT);
}

// ---- Parsed-frame holders ----

class KeypointFrame {
  int frameW, frameH;
  float[] conf;      // [n]
  float[][] x, y, c; // [n][pointCount]
  long at;
}

class BoxFrame {
  int frameW, frameH;
  float[] conf;                          // [n]
  float[][] box;                         // [n][4] left, top, width, height
  String[] label;                        // [n]
  long at;
}

class FaceBoxFrame {
  int frameW, frameH;
  float[] conf;                          // [n]
  float[][] box;                         // [n][4]
  float[] roll, yaw, pitch;              // [n], degrees
  long at;
}

class ContourFrame {
  int frameW, frameH;
  float[] conf;                          // [n]
  float[][] x, y;                        // [n][m_i] — m varies per face!
  long at;
}

class CameraInfo {
  int w, h, orientationDegrees, facing;  // facing: 0 = back, 1 = front
  long at;

  String orientationName() {
    switch (orientationDegrees) {
      case 0: return "landscape";
      case 90: return "portrait";
      case 180: return "landscape (flipped)";
      case 270: return "portrait (upside down)";
      default: return orientationDegrees + "°";
    }
  }
}

// ---- OSC parsing ----

void oscEvent(OscMessage msg) {
  try {
    if (msg.checkAddrPattern("/poses/arr")) {
      poses = parseKeypoints(msg, 17);
    } else if (msg.checkAddrPattern("/hands/arr")) {
      hands = parseKeypoints(msg, 21);
    } else if (msg.checkAddrPattern("/faces/arr")) {
      faces = parseKeypoints(msg, 76);
    } else if (msg.checkAddrPattern("/texts/arr")) {
      texts = parseBoxes(msg);
    } else if (msg.checkAddrPattern("/animals/arr")) {
      animals = parseBoxes(msg);
    } else if (msg.checkAddrPattern("/faces/box")) {
      faceBoxes = parseFaceBoxes(msg);
    } else if (msg.checkAddrPattern("/faces/contour")) {
      faceContours = parseFaceContours(msg);
    } else if (msg.checkAddrPattern("/camerainfo")) {
      CameraInfo info = new CameraInfo();
      info.w = msg.get(0).intValue();
      info.h = msg.get(1).intValue();
      info.orientationDegrees = msg.get(2).intValue();
      info.facing = msg.get(3).intValue();
      info.at = millis();
      camInfo = info;
    }
  } catch (Exception e) {
    println("Failed to parse " + msg.addrPattern() + ": " + e);
  }
}

KeypointFrame parseKeypoints(OscMessage msg, int pointCount) {
  KeypointFrame f = new KeypointFrame();
  f.frameW = msg.get(0).intValue();
  f.frameH = msg.get(1).intValue();
  int n = msg.get(2).intValue();
  f.conf = new float[n];
  f.x = new float[n][pointCount];
  f.y = new float[n][pointCount];
  f.c = new float[n][pointCount];
  int arg = 3;
  for (int i = 0; i < n; i++) {
    f.conf[i] = msg.get(arg++).floatValue();
    for (int j = 0; j < pointCount; j++) {
      f.x[i][j] = msg.get(arg++).floatValue();
      f.y[i][j] = msg.get(arg++).floatValue();
      f.c[i][j] = msg.get(arg++).floatValue();
    }
  }
  f.at = millis();
  return f;
}

BoxFrame parseBoxes(OscMessage msg) {
  BoxFrame f = new BoxFrame();
  f.frameW = msg.get(0).intValue();
  f.frameH = msg.get(1).intValue();
  int n = msg.get(2).intValue();
  f.conf = new float[n];
  f.box = new float[n][4];
  f.label = new String[n];
  int arg = 3;
  for (int i = 0; i < n; i++) {
    f.conf[i] = msg.get(arg++).floatValue();
    for (int j = 0; j < 4; j++) f.box[i][j] = msg.get(arg++).floatValue();
    f.label[i] = msg.get(arg++).stringValue();
  }
  f.at = millis();
  return f;
}

FaceBoxFrame parseFaceBoxes(OscMessage msg) {
  FaceBoxFrame f = new FaceBoxFrame();
  f.frameW = msg.get(0).intValue();
  f.frameH = msg.get(1).intValue();
  int n = msg.get(2).intValue();
  f.conf = new float[n];
  f.box = new float[n][4];
  f.roll = new float[n];
  f.yaw = new float[n];
  f.pitch = new float[n];
  // Fixed stride: face i starts at argument 3 + i*8.
  int arg = 3;
  for (int i = 0; i < n; i++) {
    f.conf[i] = msg.get(arg++).floatValue();
    for (int j = 0; j < 4; j++) f.box[i][j] = msg.get(arg++).floatValue();
    f.roll[i] = msg.get(arg++).floatValue();
    f.yaw[i] = msg.get(arg++).floatValue();
    f.pitch[i] = msg.get(arg++).floatValue();
  }
  f.at = millis();
  return f;
}

ContourFrame parseFaceContours(OscMessage msg) {
  ContourFrame f = new ContourFrame();
  f.frameW = msg.get(0).intValue();
  f.frameH = msg.get(1).intValue();
  int n = msg.get(2).intValue();
  f.conf = new float[n];
  f.x = new float[n][];
  f.y = new float[n][];
  int arg = 3;
  for (int i = 0; i < n; i++) {
    f.conf[i] = msg.get(arg++).floatValue();
    int m = msg.get(arg++).intValue();  // varies per face — always loop on m
    f.x[i] = new float[m];
    f.y[i] = new float[m];
    for (int j = 0; j < m; j++) {
      f.x[i][j] = msg.get(arg++).floatValue();
      f.y[i][j] = msg.get(arg++).floatValue();
    }
  }
  f.at = millis();
  return f;
}

// ---- Drawing ----

boolean fresh(long at) {
  return at > 0 && millis() - at < STALE_MS;
}

void draw() {
  background(0);

  // Local copies: oscEvent may replace the references mid-draw.
  KeypointFrame po = poses, ha = hands, fa = faces;
  BoxFrame te = texts, an = animals;
  FaceBoxFrame fb = faceBoxes;
  ContourFrame fc = faceContours;
  CameraInfo ci = camInfo;

  // Any fresh frame supplies the sent-frame dimensions.
  int frameW = 0, frameH = 0;
  if (po != null && fresh(po.at)) { frameW = po.frameW; frameH = po.frameH; }
  else if (ha != null && fresh(ha.at)) { frameW = ha.frameW; frameH = ha.frameH; }
  else if (fa != null && fresh(fa.at)) { frameW = fa.frameW; frameH = fa.frameH; }
  else if (fb != null && fresh(fb.at)) { frameW = fb.frameW; frameH = fb.frameH; }
  else if (fc != null && fresh(fc.at)) { frameW = fc.frameW; frameH = fc.frameH; }
  else if (te != null && fresh(te.at)) { frameW = te.frameW; frameH = te.frameH; }
  else if (an != null && fresh(an.at)) { frameW = an.frameW; frameH = an.frameH; }

  if (frameW <= 0 || frameH <= 0) {
    fill(128);
    textAlign(CENTER, CENTER);
    text("Waiting for OSC messages on port " + PORT + "…", width / 2, height / 2);
    return;
  }

  // Aspect-fit the sent frame into the window.
  float sc = min(width / (float) frameW, height / (float) frameH);
  float ox = (width - frameW * sc) / 2;
  float oy = (height - frameH * sc) / 2;

  boolean cameraInfoFresh = ci != null && millis() - ci.at < CAMERA_INFO_STALE_MS;
  drawCoordinateGuides(frameW, frameH, sc, ox, oy, cameraInfoFresh ? ci : null);

  if (po != null && fresh(po.at)) drawSkeletons(po, BODY_EDGES, POSE_COLOR, sc, ox, oy);
  if (ha != null && fresh(ha.at)) drawSkeletons(ha, HAND_EDGES, HAND_COLOR, sc, ox, oy);

  if (fa != null && fresh(fa.at)) {
    noStroke();
    fill(FACE_COLOR);
    for (int i = 0; i < fa.conf.length; i++) {
      for (int j = 0; j < fa.x[i].length; j++) {
        if (fa.c[i][j] <= 0) continue;  // missing-point sentinel
        circle(ox + fa.x[i][j] * sc, oy + fa.y[i][j] * sc, 3);
      }
    }
  }

  if (fb != null && fresh(fb.at)) {
    noFill();
    stroke(FACE_COLOR);
    strokeWeight(2);
    for (int i = 0; i < fb.conf.length; i++) {
      rect(ox + fb.box[i][0] * sc, oy + fb.box[i][1] * sc, fb.box[i][2] * sc, fb.box[i][3] * sc);
    }
  }

  if (fc != null && fresh(fc.at)) {
    noFill();
    stroke(FACE_COLOR);
    strokeWeight(2);
    for (int i = 0; i < fc.conf.length; i++) {
      if (fc.x[i].length == 0) continue;
      beginShape();
      for (int j = 0; j < fc.x[i].length; j++) {
        vertex(ox + fc.x[i][j] * sc, oy + fc.y[i][j] * sc);
      }
      endShape();  // open polyline — deliberately no CLOSE
    }
  }

  if (te != null && fresh(te.at)) drawLabeledBoxes(te, TEXT_COLOR, sc, ox, oy);
  if (an != null && fresh(an.at)) drawLabeledBoxes(an, ANIMAL_COLOR, sc, ox, oy);
}

void drawSkeletons(KeypointFrame f, int[][] edges, color col, float sc, float ox, float oy) {
  stroke(col);
  strokeWeight(2);
  for (int i = 0; i < f.conf.length; i++) {
    for (int[] edge : edges) {
      int a = edge[0], b = edge[1];
      // Skip limbs with a missing endpoint (sentinel has conf 0).
      if (f.c[i][a] <= 0 || f.c[i][b] <= 0) continue;
      line(ox + f.x[i][a] * sc, oy + f.y[i][a] * sc,
           ox + f.x[i][b] * sc, oy + f.y[i][b] * sc);
    }
    noStroke();
    fill(col, 230);
    for (int j = 0; j < f.x[i].length; j++) {
      if (f.c[i][j] <= 0) continue;
      circle(ox + f.x[i][j] * sc, oy + f.y[i][j] * sc, 6);
    }
    stroke(col);
  }
}

void drawLabeledBoxes(BoxFrame f, color col, float sc, float ox, float oy) {
  for (int i = 0; i < f.conf.length; i++) {
    float bx = ox + f.box[i][0] * sc;
    float by = oy + f.box[i][1] * sc;
    noFill();
    stroke(col);
    strokeWeight(2);
    rect(bx, by, f.box[i][2] * sc, f.box[i][3] * sc);
    noStroke();
    fill(col);
    textAlign(LEFT, BOTTOM);
    text(f.label[i] + " " + nf(f.conf[i], 0, 2), bx + 4, max(by - 4, 14));
  }
}

/// Origin marker, axis arrows, and a dimensions/orientation caption —
/// mirrors the native receiver's drawCoordinateGuides.
void drawCoordinateGuides(int frameW, int frameH, float sc, float ox, float oy, CameraInfo info) {
  float fw = frameW * sc, fh = frameH * sc;

  // Frame outline
  noFill();
  stroke(GUIDE_COLOR, 128);
  strokeWeight(1);
  rect(ox, oy, fw, fh);

  // Origin dot
  noStroke();
  fill(GUIDE_COLOR);
  circle(ox, oy, 8);

  // Axis arrows (48 px) with arrowheads
  stroke(GUIDE_COLOR);
  strokeWeight(1.5);
  drawArrow(ox, oy, ox + 48, oy);
  drawArrow(ox, oy, ox, oy + 48);

  noStroke();
  fill(GUIDE_COLOR);
  textAlign(LEFT, CENTER);
  text("x", ox + 48 + 10, oy);
  textAlign(CENTER, TOP);
  text("y", ox, oy + 48 + 10);
  textAlign(LEFT, BOTTOM);
  text("(0,0)", ox + 8, oy - 8);

  // Dimensions + orientation caption, bottom center, inside the frame rect
  String caption = frameW + "×" + frameH + " px";
  if (info != null) {
    caption += " · " + info.orientationName() + " · " + (info.facing == 1 ? "front" : "back") + " camera";
  }
  textAlign(CENTER, BOTTOM);
  text(caption, ox + fw / 2, oy + fh - 8);
}

void drawArrow(float x1, float y1, float x2, float y2) {
  line(x1, y1, x2, y2);
  float angle = atan2(y2 - y1, x2 - x1);
  for (float side : new float[] { angle + PI * 0.85, angle - PI * 0.85 }) {
    line(x2, y2, x2 + cos(side) * 8, y2 + sin(side) * 8);
  }
}
