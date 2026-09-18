// node --test — parseMessage on every message shape (the browser-only class is not exercised here).
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { parseMessage, fit, visible } = require("../trackosc-client.js");
const { BODY_EDGES, HAND_EDGES, POSE3D_EDGES, ANIMAL_EDGES } = require("../skeletons.js");

function keypoints(count, n = 1) {
  const args = [720, 1280, n];
  for (let i = 0; i < n; i++) {
    args.push(0.9);
    for (let j = 0; j < count; j++) args.push(...(j % 5 === 4 ? [0, 1280, 0] : [j * 10 + i, j * 20 + i, 0.5]));
  }
  return args;
}

test("camerainfo", () => {
  const info = parseMessage("/camerainfo", [720, 1280, 90, 1]);
  assert.equal(info.orientationName, "portrait");
  assert.equal(info.facing, 1);
});

test("keypoint kinds with the missing sentinel", () => {
  for (const [address, count] of [["/poses/arr", 17], ["/hands/arr", 21], ["/faces/arr", 76], ["/animalposes/arr", 25]]) {
    const frame = parseMessage(address, keypoints(count, 2));
    assert.equal(frame.detections.length, 2);
    assert.equal(frame.detections[1].points.length, count);
    assert.equal(frame.detections[1].points[1].x, 11);
    assert.equal(visible(frame.detections[1].points[4]), false);
  }
});

test("empty frame keeps its header", () => {
  const frame = parseMessage("/hands/arr", [1280, 720, 0]);
  assert.deepEqual([frame.frameW, frame.frameH, frame.detections.length], [1280, 720, 0]);
});

test("boxes, humans, face boxes, contours", () => {
  assert.deepEqual(parseMessage("/texts/arr", [720, 1280, 1, 0.8, 1, 2, 3, 4, "HELLO"]).detections[0].label, "HELLO");
  assert.equal(parseMessage("/humans/arr", [720, 1280, 1, 0.9, 1, 2, 3, 4]).detections[0].label, "human");
  const fb = parseMessage("/faces/box", [720, 1280, 1, 0.9, 1, 2, 3, 4, 5, 6, 7]).detections[0];
  assert.deepEqual([fb.roll, fb.yaw, fb.pitch], [5, 6, 7]);
  const [first, second] = parseMessage("/faces/contour", [720, 1280, 2, 0.9, 2, 1, 2, 3, 4, 0.5, 0]).detections;
  assert.deepEqual(first.points, [{ x: 1, y: 2 }, { x: 3, y: 4 }]);
  assert.deepEqual(second.points, []);
});

test("poses3d", () => {
  const args = [720, 1280, 1, 0.93, 1.75];
  for (let j = 0; j < 17; j++) args.push(j * 0.1, j * 0.2, -2, j * 10, j * 20);
  const pose = parseMessage("/poses3d/arr", args).detections[0];
  assert.equal(pose.bodyHeight, 1.75);
  assert.equal(pose.joints.length, 17);
  assert.equal(pose.joints[3].py, 60);
});

test("barcodes", () => {
  const args = [720, 1280, 1, 1, 10, 20, 30, 40, 10, 20, 40, 20, 40, 60, 10, 60, "QR", "https://github.com/JGL/TrackOSC"];
  const code = parseMessage("/barcodes/arr", args).detections[0];
  assert.deepEqual(code.corners[2], { x: 40, y: 60 });
  assert.equal(code.payload, "https://github.com/JGL/TrackOSC");
});

test("unknown address → null, truncated → throws", () => {
  assert.equal(parseMessage("/foo/bar", [1, 2, 0]), null);
  assert.throws(() => parseMessage("/poses/arr", [720, 1280, 1]));
  assert.throws(() => parseMessage("/humans/arr", [720, 1280, -1]));
});

test("fit aspect-fits and centres", () => {
  const { sc, ox, oy } = fit(720, 1280, 720, 960);
  assert.equal(sc, 0.75);
  assert.equal(ox, 90);
  assert.equal(oy, 0);
});

test("edge lists index their joint lists", () => {
  for (const [edges, count] of [[BODY_EDGES, 17], [HAND_EDGES, 21], [POSE3D_EDGES, 17], [ANIMAL_EDGES, 25]]) {
    for (const [a, b] of edges) assert.ok(a >= 0 && a < count && b >= 0 && b < count && a !== b);
  }
});
