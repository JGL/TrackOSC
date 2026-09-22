// node --test – raw OSC bytes → osc.js → the JSON shape the browser receives.
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const osc = require("osc");
const { flatten, parseArgs } = require("../bridge.js");

function encode(address, args) {
  // osc.js needs explicit types to produce int32 vs float32 like TrackOSC does.
  return osc.writePacket({ address, args });
}

test("a /poses/arr datagram becomes {address, args} with plain numbers", () => {
  const args = [{ type: "i", value: 720 }, { type: "i", value: 1280 }, { type: "i", value: 1 }, { type: "f", value: 0.95 }];
  for (let j = 0; j < 17; j++) args.push({ type: "f", value: j }, { type: "f", value: j * 2 }, { type: "f", value: 0.9 });
  const packet = osc.readPacket(encode("/poses/arr", args), { metadata: false });
  const [flat] = flatten(packet);
  assert.equal(flat.address, "/poses/arr");
  assert.equal(flat.args.length, 3 + 1 + 17 * 3);
  assert.deepEqual(flat.args.slice(0, 3), [720, 1280, 1]);
  assert.ok(Math.abs(flat.args[3] - 0.95) < 1e-6);
});

test("strings survive (barcode symbology and payload)", () => {
  const args = [{ type: "i", value: 720 }, { type: "i", value: 1280 }, { type: "i", value: 1 }];
  for (let i = 0; i < 13; i++) args.push({ type: "f", value: i });
  args.push({ type: "s", value: "QR" }, { type: "s", value: "https://github.com/JGL/TrackOSC" });
  const [flat] = flatten(osc.readPacket(encode("/barcodes/arr", args), { metadata: false }));
  assert.deepEqual(flat.args.slice(-2), ["QR", "https://github.com/JGL/TrackOSC"]);
});

test("bundles are flattened into their messages", () => {
  const bundle = osc.writePacket({
    timeTag: osc.timeTag(0),
    packets: [
      { address: "/camerainfo", args: [{ type: "i", value: 720 }, { type: "i", value: 1280 }, { type: "i", value: 90 }, { type: "i", value: 1 }] },
      { address: "/humans/arr", args: [{ type: "i", value: 720 }, { type: "i", value: 1280 }, { type: "i", value: 0 }] },
    ],
  });
  const flat = flatten(osc.readPacket(bundle, { metadata: false }));
  assert.deepEqual(flat.map((m) => m.address), ["/camerainfo", "/humans/arr"]);
  assert.deepEqual(flat[1].args, [720, 1280, 0]);
});

test("command-line options override the defaults", () => {
  const options = parseArgs(["--osc-port", "9600", "--ws-port", "9601", "--http-port", "9602"]);
  assert.deepEqual([options.oscPort, options.wsPort, options.httpPort], [9600, 9601, 9602]);
  assert.equal(parseArgs([]).oscPort, 9527);
});
