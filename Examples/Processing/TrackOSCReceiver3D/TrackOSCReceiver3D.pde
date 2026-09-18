/**
 * TrackOSCReceiver3D — the /poses3d/arr message drawn in real 3D.
 *
 * Listens for TrackOSC's 3D body poses (metres, Vision camera space) and
 * draws them as skeletons over a floor grid, with the camera at the origin
 * and an orbit you drive with the mouse. Everything else TrackOSC sends is
 * ignored here — see TrackOSCReceiver (next to this sketch) for the 2D
 * picture of all twelve messages.
 *
 * Requires the oscP5 library: Sketch → Import Library… → Manage Libraries →
 * search "oscP5" (by Andreas Schlegel) → Install.
 *
 * Quick start:
 *   1. Run this sketch (it listens on UDP port 9527, the VisionOSC default).
 *   2. On the TrackOSC sender, switch on "3D Body" and point it at this
 *      machine's IP, port 9527. Or, with no camera at all, from the TrackOSC
 *      repo run:  swift run poseiosc-testsend 127.0.0.1 9527
 *   3. Drag to orbit, scroll to zoom, press R to reset the view.
 *
 * /poses3d/arr layout (TrackOSC v1.4 additive message):
 *   int32 frameWidth, int32 frameHeight, int32 n, then per pose:
 *   float conf, float bodyHeight (metres), then 17 × (float x, y, z, px, py)
 *   — x, y, z in METRES in Vision's camera-relative space (x right, y up),
 *     px, py the same joint projected into the frame in pixels.
 *   Pose i starts at argument 3 + i*87; joint j of pose i at 3 + i*87 + 2 + j*5.
 *   All 17 joints are always present (no missing-joint sentinel).
 *
 * TRACKOSC SKELETON REFERENCE v1.4 — source: PoseioscShared/Sources/PoseioscShared/Skeleton.swift
 * 3D body joint order (17): 0 root, 1 spine, 2 centerShoulder, 3 centerHead,
 *   4 topHead, 5 leftShoulder, 6 leftElbow, 7 leftWrist, 8 rightShoulder,
 *   9 rightElbow, 10 rightWrist, 11 leftHip, 12 leftKnee, 13 leftAnkle,
 *   14 rightHip, 15 rightKnee, 16 rightAnkle.
 *
 * Axes: Processing's P3D is y-DOWN with +z towards the viewer, so metres-y is
 * negated below. Z_SIGN flips Vision's z if a subject standing in front of the
 * camera appears behind the camera marker on your device.
 */

import oscP5.*;

final int PORT = 9527;
final int STALE_MS = 500;
final int CAMERA_INFO_STALE_MS = 2000;

final float SCALE = 200;    // Processing units per metre
final float Z_SIGN = 1;     // flip here if the on-device axis check says so

// Orbit centre: a couple of metres in front of the camera, hip height.
final float TARGET_X = 0, TARGET_Y = -0.2, TARGET_Z = 2.0;

final int[][] POSE3D_EDGES = {
  {0, 1}, {1, 2}, {2, 3}, {3, 4},            // root → spine → centerShoulder → centerHead → topHead
  {2, 5}, {5, 6}, {6, 7},                    // left arm
  {2, 8}, {8, 9}, {9, 10},                   // right arm
  {0, 11}, {11, 12}, {12, 13},               // left leg
  {0, 14}, {14, 15}, {15, 16}                // right leg
};

color POSE3D_COLOR, GUIDE_COLOR, HUD_COLOR;

// ---- Latest data ----
Pose3DFrame poses3D;
CameraInfo camInfo;

// ---- View state ----
float rotX, rotY, zoom;
float floorY = -1.2;        // metres; eased towards the lowest ankle

OscP5 osc;
PFont hudFont;

void setup() {
  size(960, 720, P3D);
  surface.setTitle("TrackOSC Receiver 3D (Processing) — listening on " + PORT);
  POSE3D_COLOR = color(99, 230, 226);
  GUIDE_COLOR = color(90);
  HUD_COLOR = color(160);
  hudFont = createFont("Monospaced", 12);
  textFont(hudFont);
  sphereDetail(8);
  resetView();
  osc = new OscP5(this, PORT);
}

void resetView() {
  rotX = -0.35;   // look slightly down onto the floor (P3D is y-down)
  rotY = -0.6;
  zoom = 1.3;
}

// ---- Parsed-frame holders ----

class Pose3DFrame {
  int frameW, frameH;
  float[] conf, bodyHeight;
  float[][] x, y, z, px, py;   // [n][17]
  long at;
}

class CameraInfo {
  int w, h, orientationDegrees, facing;
  long at;
}

// ---- OSC parsing ----

void oscEvent(OscMessage msg) {
  try {
    if (msg.checkAddrPattern("/poses3d/arr")) {
      poses3D = parsePoses3D(msg);
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

Pose3DFrame parsePoses3D(OscMessage msg) {
  Pose3DFrame f = new Pose3DFrame();
  f.frameW = msg.get(0).intValue();
  f.frameH = msg.get(1).intValue();
  int n = msg.get(2).intValue();
  f.conf = new float[n];
  f.bodyHeight = new float[n];
  f.x = new float[n][17];
  f.y = new float[n][17];
  f.z = new float[n][17];
  f.px = new float[n][17];
  f.py = new float[n][17];
  int arg = 3;
  for (int i = 0; i < n; i++) {
    f.conf[i] = msg.get(arg++).floatValue();
    f.bodyHeight[i] = msg.get(arg++).floatValue();
    for (int j = 0; j < 17; j++) {
      f.x[i][j] = msg.get(arg++).floatValue();
      f.y[i][j] = msg.get(arg++).floatValue();
      f.z[i][j] = msg.get(arg++).floatValue();
      f.px[i][j] = msg.get(arg++).floatValue();
      f.py[i][j] = msg.get(arg++).floatValue();
    }
  }
  f.at = millis();
  return f;
}

// ---- Drawing ----

boolean fresh(long at) {
  return at > 0 && millis() - at < STALE_MS;
}

// Metres (Vision camera space) → Processing units.
float sx(float x) { return x * SCALE; }
float sy(float y) { return -y * SCALE; }
float sz(float z) { return z * Z_SIGN * SCALE; }

void draw() {
  background(0);
  Pose3DFrame f = poses3D;
  boolean live = f != null && fresh(f.at);

  // Ease the floor towards the lowest ankle (joints 13 and 16).
  if (live && f.conf.length > 0) {
    float lowest = Float.MAX_VALUE;
    for (int i = 0; i < f.conf.length; i++) {
      lowest = min(lowest, min(f.y[i][13], f.y[i][16]));
    }
    floorY += (lowest - 0.02 - floorY) * 0.1;
  }

  pushMatrix();
  translate(width / 2, height / 2 + 40, 0);
  scale(zoom);
  rotateX(rotX);
  rotateY(rotY);
  translate(-sx(TARGET_X), -sy(TARGET_Y), -sz(TARGET_Z));  // orbit around the target

  drawFloor();
  drawGnomonAndCameraMarker();
  if (live) drawPoses(f);
  popMatrix();

  drawHUD(live ? f : null);
}

void drawFloor() {
  // 4 m grid, 0.5 m pitch, centred under the target at the eased floor height.
  stroke(GUIDE_COLOR);
  strokeWeight(1);
  float y = sy(floorY);
  for (float d = -2; d <= 2.001; d += 0.5) {
    line(sx(TARGET_X - 2), y, sz(TARGET_Z + d), sx(TARGET_X + 2), y, sz(TARGET_Z + d));
    line(sx(TARGET_X + d), y, sz(TARGET_Z - 2), sx(TARGET_X + d), y, sz(TARGET_Z + 2));
  }
}

void drawGnomonAndCameraMarker() {
  // 0.25 m axes at the origin: x red, y green, z blue.
  strokeWeight(3);
  stroke(255, 80, 80);  line(0, 0, 0, sx(0.25), 0, 0);
  stroke(80, 255, 80);  line(0, 0, 0, 0, sy(0.25), 0);
  stroke(80, 140, 255); line(0, 0, 0, 0, 0, sz(0.25));
  // The camera itself: a small grey box at the origin.
  noStroke();
  fill(190);
  pushMatrix();
  box(sx(0.08), 0.05 * SCALE, 0.03 * SCALE);
  popMatrix();
}

void drawPoses(Pose3DFrame f) {
  for (int i = 0; i < f.conf.length; i++) {
    stroke(POSE3D_COLOR);
    strokeWeight(3);
    for (int[] edge : POSE3D_EDGES) {
      int a = edge[0], b = edge[1];
      line(sx(f.x[i][a]), sy(f.y[i][a]), sz(f.z[i][a]),
           sx(f.x[i][b]), sy(f.y[i][b]), sz(f.z[i][b]));
    }
    noStroke();
    fill(POSE3D_COLOR);
    for (int j = 0; j < 17; j++) {
      pushMatrix();
      translate(sx(f.x[i][j]), sy(f.y[i][j]), sz(f.z[i][j]));
      sphere(5);
      popMatrix();
    }
  }
}

/// 2D overlay: drawn with the depth test off and the default camera so it
/// sits flat on top of the 3D scene.
void drawHUD(Pose3DFrame f) {
  hint(DISABLE_DEPTH_TEST);
  camera();
  noLights();
  noStroke();
  fill(HUD_COLOR);
  textFont(hudFont);
  textAlign(LEFT, TOP);

  String line1;
  if (f == null) {
    line1 = "Waiting for /poses3d/arr on port " + PORT + "… (turn on 3D Body on the sender)";
  } else {
    StringBuilder heights = new StringBuilder();
    for (int i = 0; i < f.conf.length; i++) {
      if (i > 0) heights.append(", ");
      heights.append(nf(f.bodyHeight[i], 0, 2)).append(" m");
    }
    line1 = "/poses3d/arr  n=" + f.conf.length + (f.conf.length > 0 ? "  height " + heights : "");
  }
  text(line1, 10, 10);

  String line2 = "metres · x right · y up · z: Vision camera space";
  CameraInfo ci = camInfo;
  if (ci != null && millis() - ci.at < CAMERA_INFO_STALE_MS) {
    line2 += " · frame " + ci.w + "×" + ci.h + " · " + (ci.facing == 1 ? "front" : "back") + " camera";
  }
  text(line2, 10, 28);
  text("drag: orbit   wheel: zoom   R: reset view", 10, 46);
  hint(ENABLE_DEPTH_TEST);
}

// ---- Interaction ----

void mouseDragged() {
  rotY += (mouseX - pmouseX) * 0.01;
  rotX = constrain(rotX + (mouseY - pmouseY) * 0.01, -HALF_PI, HALF_PI);
}

void mouseWheel(MouseEvent e) {
  zoom = constrain(zoom * pow(1.1, -e.getCount()), 0.2, 5);
}

void keyPressed() {
  if (key == 'r' || key == 'R') resetView();
}
