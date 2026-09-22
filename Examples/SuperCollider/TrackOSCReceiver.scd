/*
TrackOSCReceiver.scd – a SuperCollider receiver for TrackOSC.

Parses all twelve TrackOSC messages, sonifies the body and hand poses, and
draws every kind in a window. Evaluate the whole file (select all, then
Cmd/Ctrl-Enter). Needs the server for sound; the parsing and drawing work
without it.

  - Nose x → pitch and nose y → loudness of one sine voice per detected body
  - Wrist height of each hand → filter cutoff of a noise voice
  - Everything drawn in a UserView with the same colours as the native apps

sclang listens on port 57120 by default; TrackOSC senders use 9527, so this
file opens that port too (thisProcess.openUDPPort). Only one program can
listen on a port at a time – quit the native TrackOSC Receiver first.

Wire format: every detection message starts with int32 width, int32 height,
int32 n (pixels of the sent frame, origin top-left, never mirrored), then n
detections. In an OSCdef handler msg[0] is the address, so the header is
msg[1..3] and the first detection starts at msg[4]. A keypoint with
confidence 0 is missing (VisionOSC's sentinel) – skip it.

TRACKOSC SKELETON REFERENCE v1.4 – source: PoseioscShared/Sources/PoseioscShared/Skeleton.swift
(full table in Examples/SKELETONS.md)
*/

(
var port = 9527;
var staleSeconds = 0.5;

// ---- Skeletons and colours ----
~trackoscEdges = (
	body: [[0,1],[0,2],[1,3],[2,4],[5,6],[5,11],[6,12],[11,12],[5,7],[7,9],[6,8],[8,10],[11,13],[13,15],[12,14],[14,16]],
	hand: [[0,1],[1,2],[2,3],[3,4],[0,5],[5,6],[6,7],[7,8],[0,9],[9,10],[10,11],[11,12],[0,13],[13,14],[14,15],[15,16],[0,17],[17,18],[18,19],[19,20]],
	pose3d: [[0,1],[1,2],[2,3],[3,4],[2,5],[5,6],[6,7],[2,8],[8,9],[9,10],[0,11],[11,12],[12,13],[0,14],[14,15],[15,16]],
	animal: [[0,1],[0,2],[1,5],[5,4],[4,3],[2,8],[8,7],[7,6],[0,9],[9,10],[10,11],[11,12],[9,13],[13,14],[14,15],[9,22],[22,16],[16,17],[17,18],[22,19],[19,20],[20,21],[22,23],[23,24]]
);
~trackoscColours = (
	'/poses/arr': Color.new255(48, 209, 88),
	'/poses3d/arr': Color.new255(99, 230, 226),
	'/hands/arr': Color.new255(255, 159, 10),
	'/faces/arr': Color.new255(100, 210, 255),
	'/faces/box': Color.new255(100, 210, 255),
	'/faces/contour': Color.new255(100, 210, 255),
	'/texts/arr': Color.new255(255, 214, 10),
	'/animals/arr': Color.new255(255, 55, 95),
	'/animalposes/arr': Color.new255(172, 142, 104),
	'/humans/arr': Color.new255(94, 92, 230),
	'/barcodes/arr': Color.new255(191, 90, 242),
	guides: Color.gray(0.5)
);

// ---- Latest frame per address ----
// Each entry: (frameW:, frameH:, detections: [...], at: seconds)
~trackosc = ();
~trackoscCamera = nil;

~trackoscFresh = { |address|
	var frame = ~trackosc[address];
	if(frame.notNil and: { (Main.elapsedTime - frame.at) < staleSeconds }) { frame } { nil };
};

// ---- Parsing: the running-cursor idiom over msg (msg[0] is the address) ----
~trackoscKeypointCounts = ('/poses/arr': 17, '/hands/arr': 21, '/faces/arr': 76, '/animalposes/arr': 25);

~trackoscParse = { |msg|
	var address = msg[0];
	var i = 4;
	var next = { var v = msg[i]; i = i + 1; v };
	var frame = (frameW: msg[1], frameH: msg[2], detections: [], at: Main.elapsedTime);
	var n = msg[3];
	var count = ~trackoscKeypointCounts[address];

	if(count.notNil) {
		n.do {
			var conf = next.value;
			var points = Array.fill(count, { [next.value, next.value, next.value] });   // [x, y, c]
			frame.detections = frame.detections.add((conf: conf, points: points));
		};
	} {
		switch(address,
			'/texts/arr', { n.do { frame.detections = frame.detections.add((conf: next.value, box: Array.fill(4, { next.value }), label: next.value.asString)) } },
			'/animals/arr', { n.do { frame.detections = frame.detections.add((conf: next.value, box: Array.fill(4, { next.value }), label: next.value.asString)) } },
			'/humans/arr', { n.do { frame.detections = frame.detections.add((conf: next.value, box: Array.fill(4, { next.value }), label: "human")) } },
			'/faces/box', { n.do { frame.detections = frame.detections.add((conf: next.value, box: Array.fill(4, { next.value }), roll: next.value, yaw: next.value, pitch: next.value)) } },
			'/faces/contour', { n.do {
				var conf = next.value;
				var m = next.value;   // varies per face – always loop on m
				frame.detections = frame.detections.add((conf: conf, points: Array.fill(m, { [next.value, next.value] })));
			} },
			'/poses3d/arr', { n.do {
				var conf = next.value;
				var height = next.value;
				// each joint: [x, y, z (metres, Vision camera space), px, py (pixels)]
				frame.detections = frame.detections.add((conf: conf, bodyHeight: height, joints: Array.fill(17, { [next.value, next.value, next.value, next.value, next.value] })));
			} },
			'/barcodes/arr', { n.do {
				var conf = next.value;
				var box = Array.fill(4, { next.value });
				var corners = Array.fill(4, { [next.value, next.value] });   // TL, TR, BR, BL
				frame.detections = frame.detections.add((conf: conf, box: box, corners: corners, symbology: next.value.asString, payload: next.value.asString));
			} }
		);
	};
	frame;
};

// ---- OSC ----
thisProcess.openUDPPort(port);
[
	'/poses/arr', '/hands/arr', '/faces/arr', '/faces/box', '/faces/contour', '/texts/arr',
	'/animals/arr', '/poses3d/arr', '/barcodes/arr', '/animalposes/arr', '/humans/arr'
].do { |address|
	OSCdef(("trackosc" ++ address).asSymbol, { |msg|
		~trackosc[address] = ~trackoscParse.value(msg);
	}, address, recvPort: port);
};
OSCdef(\trackoscCamera, { |msg|
	~trackoscCamera = (width: msg[1], height: msg[2], orientation: msg[3], facing: msg[4], at: Main.elapsedTime);
}, '/camerainfo', recvPort: port);
("TrackOSC: listening on UDP " ++ port).postln;

// ---- Sound: one voice per body, one per hand ----
~trackoscVoices = ();
s.waitForBoot {
	SynthDef(\trackoscBody, { |freq = 220, amp = 0, cutoff = 2000, gate = 1|
		var env = EnvGen.kr(Env.asr(0.05, 1, 0.3), gate, doneAction: 2);
		var sig = LPF.ar(Saw.ar(freq.lag(0.05)) * 0.3, cutoff.lag(0.05));
		Out.ar(0, Pan2.ar(sig * amp.lag(0.05) * env));
	}).add;
	SynthDef(\trackoscHand, { |cutoff = 800, amp = 0, gate = 1|
		var env = EnvGen.kr(Env.asr(0.05, 1, 0.3), gate, doneAction: 2);
		var sig = BPF.ar(WhiteNoise.ar(0.4), cutoff.lag(0.05), 0.2);
		Out.ar(0, Pan2.ar(sig * amp.lag(0.05) * env));
	}).add;

	// 20 Hz: create, update and free voices to match what is being tracked.
	~trackoscSoundRoutine = Routine {
		loop {
			var poses = ~trackoscFresh.value('/poses/arr');
			var hands = ~trackoscFresh.value('/hands/arr');
			var wanted = ();
			if(poses.notNil) {
				poses.detections.do { |pose, i|
					var nose = pose.points[0];
					var key = ("body" ++ i).asSymbol;
					if(nose[2] > 0) {
						var freq = nose[0].linexp(0, poses.frameW, 110, 880);
						var amp = nose[1].linlin(0, poses.frameH, 0.6, 0.05);
						if(~trackoscVoices[key].isNil) { ~trackoscVoices[key] = Synth(\trackoscBody) };
						~trackoscVoices[key].set(\freq, freq, \amp, amp);
						wanted[key] = true;
					};
				};
			};
			if(hands.notNil) {
				hands.detections.do { |hand, i|
					var wrist = hand.points[0];
					var key = ("hand" ++ i).asSymbol;
					if(wrist[2] > 0) {
						var cutoff = wrist[1].linexp(0, hands.frameH, 4000, 200);
						if(~trackoscVoices[key].isNil) { ~trackoscVoices[key] = Synth(\trackoscHand) };
						~trackoscVoices[key].set(\cutoff, cutoff, \amp, 0.3);
						wanted[key] = true;
					};
				};
			};
			~trackoscVoices.keys.copy.do { |key|
				if(wanted[key].isNil) { ~trackoscVoices[key].release; ~trackoscVoices.removeAt(key) };
			};
			0.05.wait;
		}
	}.play(AppClock);
};

// ---- Drawing ----
~trackoscWindow = Window("TrackOSC Receiver (SuperCollider) – listening on " ++ port, Rect(100, 100, 720, 960)).front;
~trackoscWindow.view.background = Color.black;
~trackoscWindow.onClose = {
	~trackoscSoundRoutine !? { ~trackoscSoundRoutine.stop };
	~trackoscVoices.do(_.release);
	~trackoscVoices = ();
};
~trackoscView = UserView(~trackoscWindow, ~trackoscWindow.view.bounds.moveTo(0, 0)).resize_(5);
~trackoscView.animate = true;
~trackoscView.frameRate = 30;
~trackoscView.drawFunc = { |view|
	var w = view.bounds.width, h = view.bounds.height;
	var fresh = ~trackosc.keys.select { |a| ~trackoscFresh.value(a).notNil };
	var ref, frameW, frameH, sc, ox, oy;
	var px = { |x| ox + (x * sc) };
	var py = { |y| oy + (y * sc) };
	var drawSkeleton = { |points, edges, colour|
		Pen.strokeColor = colour;
		Pen.width = 2;
		edges.do { |edge|
			var a = points[edge[0]], b = points[edge[1]];
			if((a[2] > 0) and: { b[2] > 0 }) { Pen.line(Point(px.(a[0]), py.(a[1])), Point(px.(b[0]), py.(b[1]))) };
		};
		Pen.stroke;
		Pen.fillColor = colour;
		points.do { |p| if(p[2] > 0) { Pen.fillOval(Rect(px.(p[0]) - 3, py.(p[1]) - 3, 6, 6)) } };
	};
	var drawBox = { |box, label, colour|
		Pen.strokeColor = colour;
		Pen.width = 2;
		Pen.strokeRect(Rect(px.(box[0]), py.(box[1]), box[2] * sc, box[3] * sc));
		if(label.notNil) { Pen.fillColor = colour; Pen.stringAtPoint(label, Point(px.(box[0]) + 4, max(py.(box[1]) - 16, 2))) };
	};

	Pen.font = Font.monospace(12);
	if(fresh.isEmpty) {
		Pen.fillColor = Color.gray;
		Pen.stringCenteredIn("Waiting for OSC messages on port " ++ port ++ "…", view.bounds);
	} {
		ref = ~trackoscFresh.value(fresh.asArray[0]);
		frameW = ref.frameW; frameH = ref.frameH;
		sc = min(w / frameW, h / frameH);
		ox = (w - (frameW * sc)) / 2;
		oy = (h - (frameH * sc)) / 2;

		// Coordinate guides: frame outline, origin, axes, caption.
		Pen.strokeColor = Color.gray(0.3); Pen.width = 1;
		Pen.strokeRect(Rect(ox, oy, frameW * sc, frameH * sc));
		Pen.fillColor = ~trackoscColours.guides;
		Pen.fillOval(Rect(ox - 4, oy - 4, 8, 8));
		Pen.strokeColor = ~trackoscColours.guides;
		Pen.line(Point(ox, oy), Point(ox + 48, oy)); Pen.line(Point(ox, oy), Point(ox, oy + 48)); Pen.stroke;
		Pen.stringAtPoint("x", Point(ox + 56, oy - 8));
		Pen.stringAtPoint("y", Point(ox - 4, oy + 54));
		Pen.stringAtPoint(frameW.asString ++ "×" ++ frameH ++ " px" ++ (~trackoscCamera !? { |c| " · " ++ if(c.orientation == 90) { "portrait" } { "landscape" } ++ " · " ++ if(c.facing == 1) { "front" } { "back" } ++ " camera" } ? ""),
			Point(ox + (frameW * sc / 2) - 120, oy + (frameH * sc) - 20));

		fresh.do { |address|
			var frame = ~trackoscFresh.value(address);
			var colour = ~trackoscColours[address];
			switch(address,
				'/poses/arr', { frame.detections.do { |d| drawSkeleton.(d.points, ~trackoscEdges.body, colour) } },
				'/hands/arr', { frame.detections.do { |d| drawSkeleton.(d.points, ~trackoscEdges.hand, colour) } },
				'/animalposes/arr', { frame.detections.do { |d| drawSkeleton.(d.points, ~trackoscEdges.animal, colour) } },
				'/faces/arr', { Pen.fillColor = colour; frame.detections.do { |d| d.points.do { |p| if(p[2] > 0) { Pen.fillOval(Rect(px.(p[0]) - 1.5, py.(p[1]) - 1.5, 3, 3)) } } } },
				'/faces/box', { frame.detections.do { |d| drawBox.(d.box, nil, colour) } },
				'/faces/contour', { frame.detections.do { |d|
					if(d.points.size > 0) {
						Pen.strokeColor = colour; Pen.width = 2;
						Pen.moveTo(Point(px.(d.points[0][0]), py.(d.points[0][1])));
						d.points.drop(1).do { |p| Pen.lineTo(Point(px.(p[0]), py.(p[1]))) };
						Pen.stroke;   // open jawline – never closed
					};
				} },
				'/texts/arr', { frame.detections.do { |d| drawBox.(d.box, d.label ++ " " ++ d.conf.round(0.01), colour) } },
				'/animals/arr', { frame.detections.do { |d| drawBox.(d.box, d.label ++ " " ++ d.conf.round(0.01), colour) } },
				'/humans/arr', { frame.detections.do { |d| drawBox.(d.box, "human " ++ d.conf.round(0.01), colour) } },
				'/poses3d/arr', { frame.detections.do { |d|
					var projected = d.joints.collect { |j| [j[3], j[4], 1] };
					drawSkeleton.(projected, ~trackoscEdges.pose3d, colour);
					Pen.fillColor = colour;
					Pen.stringAtPoint("z " ++ d.joints[0][2].round(0.01) ++ " m · h " ++ d.bodyHeight.round(0.01) ++ " m", Point(px.(d.joints[0][3]) + 8, py.(d.joints[0][4]) - 20));
				} },
				'/barcodes/arr', { frame.detections.do { |d|
					Pen.strokeColor = colour; Pen.width = 2;
					Pen.moveTo(Point(px.(d.corners[0][0]), py.(d.corners[0][1])));
					d.corners.drop(1).do { |c| Pen.lineTo(Point(px.(c[0]), py.(c[1]))) };
					Pen.lineTo(Point(px.(d.corners[0][0]), py.(d.corners[0][1])));
					Pen.stroke;
					Pen.fillColor = colour;
					Pen.fillOval(Rect(px.(d.corners[0][0]) - 4, py.(d.corners[0][1]) - 4, 8, 8));   // top-left corner
					Pen.stringAtPoint(d.symbology ++ " " ++ d.payload, Point(px.(d.box[0]), max(py.(d.box[1]) - 16, 2)));
				} }
			);
		};
	};
};
)
