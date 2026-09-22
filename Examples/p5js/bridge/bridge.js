#!/usr/bin/env node
/**
 * trackosc-bridge – browsers can't open UDP sockets, so this small Node
 * program listens for TrackOSC's OSC messages on UDP and relays every one to
 * connected browsers as JSON over a WebSocket:
 *
 *     {"address": "/poses/arr", "args": [720, 1280, 1, 0.95, ...]}
 *
 * It also serves the sketch folder over HTTP so one command gives you a
 * working page.
 *
 *     npm install
 *     npm start                # UDP 9527 → ws://localhost:8765, page on http://localhost:8080
 *     node bridge.js --osc-port 9527 --ws-port 8765 --http-port 8080 --sketch ../sketch
 */

"use strict";

const fs = require("fs");
const http = require("http");
const path = require("path");
const osc = require("osc");
const { WebSocketServer } = require("ws");

function parseArgs(argv) {
  const options = { oscPort: 9527, wsPort: 8765, httpPort: 8080, sketch: path.join(__dirname, "..", "sketch") };
  for (let i = 0; i < argv.length; i++) {
    const next = () => argv[++i];
    switch (argv[i]) {
      case "--osc-port": options.oscPort = Number(next()); break;
      case "--ws-port": options.wsPort = Number(next()); break;
      case "--http-port": options.httpPort = Number(next()); break;
      case "--sketch": options.sketch = path.resolve(next()); break;
      case "--help": case "-h":
        console.log("usage: trackosc-bridge [--osc-port 9527] [--ws-port 8765] [--http-port 8080] [--sketch ../sketch]");
        process.exit(0);
    }
  }
  return options;
}

/** Flattens an osc.js packet (message or bundle) into {address, args} objects. */
function flatten(packet, out = []) {
  if (packet.address !== undefined) {
    out.push({ address: packet.address, args: packet.args === undefined ? [] : [].concat(packet.args) });
  } else if (Array.isArray(packet.packets)) {
    for (const inner of packet.packets) flatten(inner, out);
  }
  return out;
}

const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css", ".json": "application/json", ".png": "image/png", ".md": "text/plain; charset=utf-8" };

function serveStatic(root) {
  return (request, response) => {
    let urlPath = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
    if (urlPath.endsWith("/")) urlPath += "index.html";
    const file = path.normalize(path.join(root, urlPath));
    if (!file.startsWith(root)) { response.writeHead(403); response.end(); return; }
    fs.readFile(file, (error, data) => {
      if (error) { response.writeHead(404); response.end("not found"); return; }
      response.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream" });
      response.end(data);
    });
  };
}

function main() {
  const options = parseArgs(process.argv.slice(2));

  const wss = new WebSocketServer({ port: options.wsPort });
  wss.on("error", (error) => { console.error(`WebSocket server error: ${error.message}`); process.exit(1); });
  const broadcast = (json) => { for (const client of wss.clients) if (client.readyState === 1) client.send(json); };

  const counts = new Map();
  const udp = new osc.UDPPort({ localAddress: "0.0.0.0", localPort: options.oscPort, metadata: false });
  udp.on("message", (message) => {
    for (const flat of flatten(message)) {
      counts.set(flat.address, (counts.get(flat.address) || 0) + 1);
      broadcast(JSON.stringify(flat));
    }
  });
  udp.on("bundle", (bundle) => {
    for (const flat of flatten(bundle)) {
      counts.set(flat.address, (counts.get(flat.address) || 0) + 1);
      broadcast(JSON.stringify(flat));
    }
  });
  udp.on("error", (error) => { console.error(`OSC error: ${error.message}`); if (error.code === "EADDRINUSE") process.exit(1); });
  udp.open();

  const server = http.createServer(serveStatic(options.sketch));
  server.on("error", (error) => { console.error(`HTTP server error: ${error.message}`); process.exit(1); });
  server.listen(options.httpPort, () => {
    console.log(`trackosc-bridge: OSC in on UDP ${options.oscPort} → ws://localhost:${options.wsPort}`);
    console.log(`open http://localhost:${options.httpPort}/ for the sketch (${options.sketch})`);
  });

  // Once a second: per-address rates, like the native receiver's sidebar.
  setInterval(() => {
    if (counts.size === 0) return;
    const parts = [...counts.entries()].sort().map(([address, n]) => `${address} ${n} Hz`);
    console.log(`${wss.clients.size} browser(s) · ${parts.join(" · ")}`);
    counts.clear();
  }, 1000);
}

module.exports = { flatten, parseArgs };

if (require.main === module) main();
