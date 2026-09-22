/**
 * TrackOSC receiver in p5.js – draws all twelve messages, mirroring the
 * Processing reference sketch: skeletons (2D body, hand, animal, and the 3D
 * body via its pixel projections), face landmarks, boxes and contours,
 * text/animal/human boxes, barcode quads, and the coordinate guides.
 *
 * Needs trackosc-bridge running (see ../bridge): browsers can't receive UDP.
 */

const BRIDGE_URL = "ws://localhost:8765";
let client;
let showGuides = true;

const S = TrackOSCSkeletons;

function setup() {
  createCanvas(720, 960);
  textFont("monospace", 12);
  client = new TrackOSC.TrackOSCClient(BRIDGE_URL);
}

function keyPressed() {
  if (key === "g" || key === "G") showGuides = !showGuides;
}

function draw() {
  background(0);
  const frames = client.freshFrames();
  const addresses = Object.keys(frames);

  if (addresses.length === 0) {
    fill(128); noStroke(); textAlign(CENTER, CENTER);
    text(client.connected ? "Connected to the bridge – waiting for OSC messages…" : `Connecting to ${BRIDGE_URL}… (is trackosc-bridge running?)`, width / 2, height / 2);
    return;
  }

  const ref = frames[addresses[0]];
  const { sc, ox, oy } = TrackOSC.fit(ref.frameW, ref.frameH, width, height);
  const X = (x) => ox + x * sc;
  const Y = (y) => oy + y * sc;

  if (showGuides) drawGuides(ref.frameW, ref.frameH, sc, ox, oy, client.freshCamera());

  // Boxes first so skeletons draw on top.
  for (const address of ["/humans/arr", "/texts/arr", "/animals/arr"]) {
    const frame = frames[address];
    if (!frame) continue;
    for (const d of frame.detections) drawBox(d.box, `${d.label} ${d.confidence.toFixed(2)}`, S.COLOURS[address], X, Y, sc);
  }

  const skeletons = { "/poses/arr": S.BODY_EDGES, "/hands/arr": S.HAND_EDGES, "/animalposes/arr": S.ANIMAL_EDGES };
  for (const [address, edges] of Object.entries(skeletons)) {
    const frame = frames[address];
    if (!frame) continue;
    for (const d of frame.detections) drawSkeleton(d.points, edges, S.COLOURS[address], X, Y);
  }

  const faces = frames["/faces/arr"];
  if (faces) {
    noStroke(); fill(...S.COLOURS["/faces/arr"]);
    for (const face of faces.detections) for (const p of face.points) if (TrackOSC.visible(p)) circle(X(p.x), Y(p.y), 3);
  }
  const faceBoxes = frames["/faces/box"];
  if (faceBoxes) for (const d of faceBoxes.detections) drawBox(d.box, null, S.COLOURS["/faces/box"], X, Y, sc);
  const contours = frames["/faces/contour"];
  if (contours) {
    noFill(); stroke(...S.COLOURS["/faces/contour"]); strokeWeight(2);
    for (const d of contours.detections) {
      if (d.points.length === 0) continue;
      beginShape();
      for (const p of d.points) vertex(X(p.x), Y(p.y));
      endShape();  // open polyline – never CLOSE the jawline
    }
  }

  const poses3D = frames["/poses3d/arr"];
  if (poses3D) {
    const colour = S.COLOURS["/poses3d/arr"];
    for (const pose of poses3D.detections) {
      const projected = pose.joints.map((j) => ({ x: j.px, y: j.py, c: 1 }));
      drawSkeleton(projected, S.POSE3D_EDGES, colour, X, Y);
      noStroke(); fill(...colour); textAlign(LEFT, BOTTOM);
      text(`z ${pose.joints[0].z.toFixed(2)} m · h ${pose.bodyHeight.toFixed(2)} m`, X(pose.joints[0].px) + 8, Y(pose.joints[0].py) - 8);
    }
  }

  const barcodes = frames["/barcodes/arr"];
  if (barcodes) {
    const colour = S.COLOURS["/barcodes/arr"];
    for (const code of barcodes.detections) {
      noFill(); stroke(...colour); strokeWeight(2);
      beginShape();
      for (const c of code.corners) vertex(X(c.x), Y(c.y));
      endShape(CLOSE);
      noStroke(); fill(...colour);
      circle(X(code.corners[0].x), Y(code.corners[0].y), 8);  // top-left corner
      const top = Math.min(...code.corners.map((c) => c.y));
      textAlign(LEFT, BOTTOM);
      text(`${code.symbology} ${code.payload}`, X(code.box.left), Math.max(Y(top) - 6, 14));
    }
  }
}

function drawSkeleton(points, edges, colour, X, Y) {
  stroke(...colour); strokeWeight(2);
  for (const [a, b] of edges) {
    if (!TrackOSC.visible(points[a]) || !TrackOSC.visible(points[b])) continue;
    line(X(points[a].x), Y(points[a].y), X(points[b].x), Y(points[b].y));
  }
  noStroke(); fill(...colour, 230);
  for (const p of points) if (TrackOSC.visible(p)) circle(X(p.x), Y(p.y), 6);
}

function drawBox(box, label, colour, X, Y, sc) {
  noFill(); stroke(...colour); strokeWeight(2);
  rect(X(box.left), Y(box.top), box.width * sc, box.height * sc);
  if (label) {
    noStroke(); fill(...colour); textAlign(LEFT, BOTTOM);
    text(label, X(box.left) + 4, Math.max(Y(box.top) - 4, 14));
  }
}

function drawGuides(frameW, frameH, sc, ox, oy, camera) {
  const grey = S.COLOURS.guides;
  const fw = frameW * sc, fh = frameH * sc;
  noFill(); stroke(...grey, 128); strokeWeight(1); rect(ox, oy, fw, fh);
  noStroke(); fill(...grey); circle(ox, oy, 8);
  stroke(...grey); strokeWeight(1.5);
  drawArrow(ox, oy, ox + 48, oy); drawArrow(ox, oy, ox, oy + 48);
  noStroke(); fill(...grey);
  textAlign(LEFT, CENTER); text("x", ox + 58, oy);
  textAlign(CENTER, TOP); text("y", ox, oy + 58);
  textAlign(LEFT, BOTTOM); text("(0,0)", ox + 8, oy - 8);
  let caption = `${frameW}×${frameH} px`;
  if (camera) caption += ` · ${camera.orientationName} · ${camera.facing === 1 ? "front" : "back"} camera`;
  textAlign(CENTER, BOTTOM); text(caption, ox + fw / 2, oy + fh - 8);
}

function drawArrow(x1, y1, x2, y2) {
  line(x1, y1, x2, y2);
  const angle = Math.atan2(y2 - y1, x2 - x1);
  for (const side of [angle + Math.PI * 0.85, angle - Math.PI * 0.85]) line(x2, y2, x2 + Math.cos(side) * 8, y2 + Math.sin(side) * 8);
}
