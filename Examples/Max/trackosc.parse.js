/*
trackosc.parse.js – a [js] parser for TrackOSC messages in Max.

Connect [udpreceive 9527 @maxpacketsize 65536] to the inlet. Each OSC message
arrives with its address as the selector ("/poses/arr 720 1280 1 0.95 …"), so
"anything" below receives every one. Written in ES5 for Max 8's [js]; [v8]
in Max 9 runs it unchanged.

Outlets:
  0  camerainfo:  "camerainfo <w> <h> <orientation> <facing>"
  1  keypoints:   "<kind> <det> <jointName> <xNorm> <yNorm> <c>"  (kind = pose | hand |
                  face | animalpose; face joints are numbered 0–75), and for the 3D body
                  "pose3d <det> <jointName> <xNorm> <yNorm> <x> <y> <z>" with x/y/z in
                  metres. xNorm/yNorm are the frame position 0…1 (origin top-left).
                  A keypoint with c == 0 is missing and is NOT sent.
  2  boxes:       "<kind> <det> <lNorm> <tNorm> <wNorm> <hNorm> <label…>" (kind = text |
                  animal | human | facebox | barcode; barcode labels are "<symbology>
                  <payload>", facebox labels are "<roll> <yaw> <pitch>" in degrees)
  3  drawing:     on "bang", a burst of [jit.lcd] commands (clear, frgb, pensize,
                  linesegment, paintoval, framerect, framepoly, moveto, write) that draws
                  every fresh frame aspect-fitted into an LCD of "size <w> <h>"
                  (default 720 960), followed by "bang" so the lcd outputs its matrix.

Wire format: every detection message starts with int32 width, int32 height,
int32 n (pixels of the sent frame, origin top-left, never mirrored), then n
detections – see the root README "OSC wire format".

TRACKOSC SKELETON REFERENCE v1.4 – source: PoseioscShared/Sources/PoseioscShared/Skeleton.swift
(full table in Examples/SKELETONS.md)
*/

inlets = 1;
outlets = 4;
autowatch = 1;

var STALE_MS = 500;
var lcdWidth = 720, lcdHeight = 960;

var BODY_JOINTS = ["nose", "leftEye", "rightEye", "leftEar", "rightEar", "leftShoulder", "rightShoulder",
	"leftElbow", "rightElbow", "leftWrist", "rightWrist", "leftHip", "rightHip", "leftKnee", "rightKnee",
	"leftAnkle", "rightAnkle"];
var BODY_EDGES = [[0, 1], [0, 2], [1, 3], [2, 4], [5, 6], [5, 11], [6, 12], [11, 12], [5, 7], [7, 9], [6, 8], [8, 10],
	[11, 13], [13, 15], [12, 14], [14, 16]];
var HAND_JOINTS = ["wrist", "thumbCMC", "thumbMP", "thumbIP", "thumbTip", "indexMCP", "indexPIP", "indexDIP",
	"indexTip", "middleMCP", "middlePIP", "middleDIP", "middleTip", "ringMCP", "ringPIP", "ringDIP", "ringTip",
	"pinkyMCP", "pinkyPIP", "pinkyDIP", "pinkyTip"];
var HAND_EDGES = [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [0, 9], [9, 10], [10, 11], [11, 12],
	[0, 13], [13, 14], [14, 15], [15, 16], [0, 17], [17, 18], [18, 19], [19, 20]];
var POSE3D_JOINTS = ["root", "spine", "centerShoulder", "centerHead", "topHead", "leftShoulder", "leftElbow",
	"leftWrist", "rightShoulder", "rightElbow", "rightWrist", "leftHip", "leftKnee", "leftAnkle", "rightHip",
	"rightKnee", "rightAnkle"];
var POSE3D_EDGES = [[0, 1], [1, 2], [2, 3], [3, 4], [2, 5], [5, 6], [6, 7], [2, 8], [8, 9], [9, 10], [0, 11], [11, 12],
	[12, 13], [0, 14], [14, 15], [15, 16]];
var ANIMAL_JOINTS = ["nose", "leftEye", "rightEye", "leftEarTop", "leftEarMiddle", "leftEarBottom", "rightEarTop",
	"rightEarMiddle", "rightEarBottom", "neck", "leftFrontElbow", "leftFrontKnee", "leftFrontPaw", "rightFrontElbow",
	"rightFrontKnee", "rightFrontPaw", "leftBackElbow", "leftBackKnee", "leftBackPaw", "rightBackElbow",
	"rightBackKnee", "rightBackPaw", "tailTop", "tailMiddle", "tailBottom"];
var ANIMAL_EDGES = [[0, 1], [0, 2], [1, 5], [5, 4], [4, 3], [2, 8], [8, 7], [7, 6], [0, 9], [9, 10], [10, 11], [11, 12],
	[9, 13], [13, 14], [14, 15], [9, 22], [22, 16], [16, 17], [17, 18], [22, 19], [19, 20], [20, 21], [22, 23], [23, 24]];

var KEYPOINT_KINDS = {
	"/poses/arr": { kind: "pose", count: 17, names: BODY_JOINTS, edges: BODY_EDGES, colour: [48, 209, 88] },
	"/hands/arr": { kind: "hand", count: 21, names: HAND_JOINTS, edges: HAND_EDGES, colour: [255, 159, 10] },
	"/faces/arr": { kind: "face", count: 76, names: null, edges: [], colour: [100, 210, 255] },
	"/animalposes/arr": { kind: "animalpose", count: 25, names: ANIMAL_JOINTS, edges: ANIMAL_EDGES, colour: [172, 142, 104] }
};
var BOX_KINDS = { "/texts/arr": "text", "/animals/arr": "animal", "/humans/arr": "human" };
var COLOURS = {
	"/poses3d/arr": [99, 230, 226], "/faces/box": [100, 210, 255], "/faces/contour": [100, 210, 255],
	"/texts/arr": [255, 214, 10], "/animals/arr": [255, 55, 95], "/humans/arr": [94, 92, 230],
	"/barcodes/arr": [191, 90, 242], guides: [128, 128, 128]
};

var latest = {};   // address → { frameW, frameH, detections, at }
var camera = null;

function size(w, h) { lcdWidth = w; lcdHeight = h; }

function now() { return new Date().getTime(); }

// ---- Parsing (running-argument cursor) ----

function Cursor(args) { this.args = args; this.i = 0; }
Cursor.prototype.next = function () {
	if (this.i >= this.args.length) throw new Error("truncated message");
	return this.args[this.i++];
};
Cursor.prototype.count = function () { var n = Math.round(this.next()); if (n < 0) throw new Error("negative count"); return n; };

function anything() {
	var address = messagename;
	var args = arrayfromargs(arguments);
	try {
		parse(address, args);
	} catch (e) {
		post("trackosc.parse.js: " + address + ": " + e.message + "\n");
	}
}

function parse(address, args) {
	var cur = new Cursor(args);
	if (address === "/camerainfo") {
		camera = { w: cur.next(), h: cur.next(), orientation: cur.next(), facing: cur.next(), at: now() };
		outlet(0, ["camerainfo", camera.w, camera.h, camera.orientation, camera.facing]);
		return;
	}
	var frame = { frameW: cur.next(), frameH: cur.next(), detections: [], at: now() };
	var n = cur.count();
	var i, j, d;

	if (KEYPOINT_KINDS[address]) {
		var spec = KEYPOINT_KINDS[address];
		for (i = 0; i < n; i++) {
			d = { conf: cur.next(), points: [] };
			for (j = 0; j < spec.count; j++) {
				var p = { x: cur.next(), y: cur.next(), c: cur.next() };
				d.points.push(p);
				if (p.c > 0) outlet(1, [spec.kind, i, spec.names ? spec.names[j] : j, p.x / frame.frameW, p.y / frame.frameH, p.c]);
			}
			frame.detections.push(d);
		}
	} else if (BOX_KINDS[address]) {
		for (i = 0; i < n; i++) {
			d = { conf: cur.next(), box: [cur.next(), cur.next(), cur.next(), cur.next()] };
			d.label = address === "/humans/arr" ? "human" : String(cur.next());
			frame.detections.push(d);
			outlet(2, [BOX_KINDS[address], i].concat(normBox(d.box, frame), [d.label]));
		}
	} else if (address === "/faces/box") {
		for (i = 0; i < n; i++) {
			d = { conf: cur.next(), box: [cur.next(), cur.next(), cur.next(), cur.next()], roll: cur.next(), yaw: cur.next(), pitch: cur.next() };
			frame.detections.push(d);
			outlet(2, ["facebox", i].concat(normBox(d.box, frame), [d.roll, d.yaw, d.pitch]));
		}
	} else if (address === "/faces/contour") {
		for (i = 0; i < n; i++) {
			d = { conf: cur.next(), points: [] };
			var m = cur.count();   // varies per face – always loop on m
			for (j = 0; j < m; j++) d.points.push({ x: cur.next(), y: cur.next() });
			frame.detections.push(d);
		}
	} else if (address === "/poses3d/arr") {
		for (i = 0; i < n; i++) {
			d = { conf: cur.next(), bodyHeight: cur.next(), joints: [] };
			for (j = 0; j < 17; j++) {
				var joint = { x: cur.next(), y: cur.next(), z: cur.next(), px: cur.next(), py: cur.next() };
				d.joints.push(joint);
				outlet(1, ["pose3d", i, POSE3D_JOINTS[j], joint.px / frame.frameW, joint.py / frame.frameH, joint.x, joint.y, joint.z]);
			}
			frame.detections.push(d);
		}
	} else if (address === "/barcodes/arr") {
		for (i = 0; i < n; i++) {
			d = { conf: cur.next(), box: [cur.next(), cur.next(), cur.next(), cur.next()], corners: [] };
			for (j = 0; j < 4; j++) d.corners.push({ x: cur.next(), y: cur.next() });
			d.symbology = String(cur.next());
			d.payload = String(cur.next());
			frame.detections.push(d);
			outlet(2, ["barcode", i].concat(normBox(d.box, frame), [d.symbology, d.payload]));
		}
	} else {
		return;   // not a TrackOSC address
	}
	latest[address] = frame;
}

function normBox(box, frame) {
	return [box[0] / frame.frameW, box[1] / frame.frameH, box[2] / frame.frameW, box[3] / frame.frameH];
}

// ---- Drawing: [jit.lcd] commands on bang ----

function bang() {
	var t = now();
	var fresh = [];
	for (var address in latest) if (t - latest[address].at < STALE_MS) fresh.push(address);
	outlet(3, "clear");
	if (fresh.length === 0) { outlet(3, "bang"); return; }

	var ref = latest[fresh[0]];
	var sc = Math.min(lcdWidth / ref.frameW, lcdHeight / ref.frameH);
	var ox = (lcdWidth - ref.frameW * sc) / 2, oy = (lcdHeight - ref.frameH * sc) / 2;
	var X = function (x) { return Math.round(ox + x * sc); };
	var Y = function (y) { return Math.round(oy + y * sc); };

	// Guides: frame outline, origin dot, caption.
	colour(COLOURS.guides);
	outlet(3, ["pensize", 1, 1]);
	outlet(3, ["framerect", X(0), Y(0), X(ref.frameW), Y(ref.frameH)]);
	outlet(3, ["paintoval", X(0) - 4, Y(0) - 4, X(0) + 4, Y(0) + 4]);
	outlet(3, ["linesegment", X(0), Y(0), X(0) + 48, Y(0)]);
	outlet(3, ["linesegment", X(0), Y(0), X(0), Y(0) + 48]);
	var caption = ref.frameW + "x" + ref.frameH + " px";
	if (camera && t - camera.at < 2000) caption += " " + (camera.orientation === 90 ? "portrait" : "landscape") + " " + (camera.facing === 1 ? "front" : "back");
	label(caption, X(ref.frameW / 2) - 60, Y(ref.frameH) - 8);

	outlet(3, ["pensize", 2, 2]);
	for (var k = 0; k < fresh.length; k++) {
		var address = fresh[k];
		var frame = latest[address];
		var i, j, d;
		if (KEYPOINT_KINDS[address]) {
			var spec = KEYPOINT_KINDS[address];
			colour(spec.colour);
			for (i = 0; i < frame.detections.length; i++) skeleton(frame.detections[i].points, spec.edges, X, Y, spec.names ? 3 : 1);
		} else if (address === "/poses3d/arr") {
			colour(COLOURS[address]);
			for (i = 0; i < frame.detections.length; i++) {
				d = frame.detections[i];
				var projected = [];
				for (j = 0; j < 17; j++) projected.push({ x: d.joints[j].px, y: d.joints[j].py, c: 1 });
				skeleton(projected, POSE3D_EDGES, X, Y, 3);
				label("z " + d.joints[0].z.toFixed(2) + "m h " + d.bodyHeight.toFixed(2) + "m", X(d.joints[0].px) + 8, Y(d.joints[0].py) - 8);
			}
		} else if (address === "/faces/box") {
			colour(COLOURS[address]);
			for (i = 0; i < frame.detections.length; i++) box(frame.detections[i].box, null, X, Y);
		} else if (address === "/faces/contour") {
			colour(COLOURS[address]);
			for (i = 0; i < frame.detections.length; i++) {
				var pts = frame.detections[i].points;
				for (j = 1; j < pts.length; j++) outlet(3, ["linesegment", X(pts[j - 1].x), Y(pts[j - 1].y), X(pts[j].x), Y(pts[j].y)]);
			}
		} else if (BOX_KINDS[address]) {
			colour(COLOURS[address]);
			for (i = 0; i < frame.detections.length; i++) box(frame.detections[i].box, frame.detections[i].label + " " + frame.detections[i].conf.toFixed(2), X, Y);
		} else if (address === "/barcodes/arr") {
			colour(COLOURS[address]);
			for (i = 0; i < frame.detections.length; i++) {
				d = frame.detections[i];
				var poly = ["framepoly"];
				for (j = 0; j < 4; j++) poly.push(X(d.corners[j].x), Y(d.corners[j].y));
				outlet(3, poly);
				outlet(3, ["paintoval", X(d.corners[0].x) - 4, Y(d.corners[0].y) - 4, X(d.corners[0].x) + 4, Y(d.corners[0].y) + 4]);
				label(d.symbology + " " + d.payload, X(d.box[0]), Math.max(Y(d.box[1]) - 6, 12));
			}
		}
	}
	outlet(3, "bang");
}

function colour(rgb) { outlet(3, ["frgb", rgb[0], rgb[1], rgb[2]]); }

function label(text, x, y) {
	outlet(3, ["moveto", x, y]);
	outlet(3, ["write"].concat(String(text).split(" ")));
}

function skeleton(points, edges, X, Y, dot) {
	var i;
	for (i = 0; i < edges.length; i++) {
		var a = points[edges[i][0]], b = points[edges[i][1]];
		if (a.c <= 0 || b.c <= 0) continue;   // missing keypoint
		outlet(3, ["linesegment", X(a.x), Y(a.y), X(b.x), Y(b.y)]);
	}
	for (i = 0; i < points.length; i++) {
		if (points[i].c <= 0) continue;
		outlet(3, ["paintoval", X(points[i].x) - dot, Y(points[i].y) - dot, X(points[i].x) + dot, Y(points[i].y) + dot]);
	}
}

function box(b, text, X, Y) {
	outlet(3, ["framerect", X(b[0]), Y(b[1]), X(b[0] + b[2]), Y(b[1] + b[3])]);
	if (text) label(text, X(b[0]) + 4, Math.max(Y(b[1]) - 4, 12));
}
