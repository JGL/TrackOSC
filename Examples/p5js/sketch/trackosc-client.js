/**
 * TrackOSC client for the browser: connects to trackosc-bridge over
 * WebSocket, parses every message into plain objects, and keeps the latest
 * frame per address for your draw loop.
 *
 *     const client = new TrackOSC.TrackOSCClient("ws://localhost:8765");
 *     // in draw():
 *     const poses = client.fresh("/poses/arr");   // null if nothing in the last 500 ms
 *     if (poses) for (const pose of poses.detections) { ... pose.points[0].x ... }
 *
 * Loads as a plain <script> (global `TrackOSC`) and as a CommonJS module
 * (Node tests exercise `parseMessage`).
 *
 * Wire format: every detection message starts with int32 width, int32
 * height, int32 n (pixels of the sent frame, origin top-left, never
 * mirrored), then n detections – see the root README "OSC wire format".
 * A keypoint with c === 0 is missing (VisionOSC's sentinel) – skip it.
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.TrackOSC = factory();
}(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const STALE_MS = 500;
  const CAMERA_INFO_STALE_MS = 2000;
  const KEYPOINT_COUNTS = { "/poses/arr": 17, "/hands/arr": 21, "/faces/arr": 76, "/animalposes/arr": 25 };
  const ALL_ADDRESSES = ["/camerainfo", "/poses/arr", "/hands/arr", "/faces/arr", "/faces/box", "/faces/contour",
    "/texts/arr", "/animals/arr", "/poses3d/arr", "/barcodes/arr", "/animalposes/arr", "/humans/arr",
    "/contours/arr", "/horizon", "/rectangles/arr"];

  /** The running-argument-cursor idiom: read values in wire order. */
  class Cursor {
    constructor(address, args) { this.address = address; this.args = args; this.i = 0; }
    next() {
      if (this.i >= this.args.length) throw new Error(`${this.address}: truncated (expected ≥ ${this.i + 1} arguments, got ${this.args.length})`);
      return this.args[this.i++];
    }
    int() { return Math.trunc(Number(this.next())); }
    count() { const n = this.int(); if (n < 0) throw new Error(`${this.address}: negative count ${n}`); return n; }
    float() { return Number(this.next()); }
    string() { return String(this.next()); }
    rect() { return { left: this.float(), top: this.float(), width: this.float(), height: this.float() }; }
  }

  const now = () => (typeof performance !== "undefined" ? performance.now() : Date.now());

  /**
   * Decode one message. Returns a frame {address, frameW, frameH, detections, at},
   * a camera info {address:"/camerainfo", width, height, orientation, facing, at},
   * or null for an address TrackOSC doesn't define. Throws on truncated input.
   */
  function parseMessage(address, args) {
    const cur = new Cursor(address, args);
    const at = now();

    if (address === "/camerainfo") {
      const info = { address, width: cur.int(), height: cur.int(), orientation: cur.int(), facing: cur.int(), at };
      info.orientationName = { 0: "landscape", 90: "portrait", 180: "landscape (flipped)", 270: "portrait (upside down)" }[info.orientation] || `${info.orientation}°`;
      return info;
    }

    const known = ALL_ADDRESSES.includes(address);
    if (!known) return null;

    const frame = { address, frameW: cur.int(), frameH: cur.int(), detections: [], at };
    const n = cur.count();

    for (let i = 0; i < n; i++) {
      if (address in KEYPOINT_COUNTS) {
        const confidence = cur.float();
        const points = [];
        for (let j = 0; j < KEYPOINT_COUNTS[address]; j++) points.push({ x: cur.float(), y: cur.float(), c: cur.float() });
        frame.detections.push({ confidence, points });
      } else if (address === "/texts/arr" || address === "/animals/arr") {
        frame.detections.push({ confidence: cur.float(), box: cur.rect(), label: cur.string() });
      } else if (address === "/humans/arr") {
        frame.detections.push({ confidence: cur.float(), box: cur.rect(), label: "human" });
      } else if (address === "/faces/box") {
        frame.detections.push({ confidence: cur.float(), box: cur.rect(), roll: cur.float(), yaw: cur.float(), pitch: cur.float() });
      } else if (address === "/faces/contour" || address === "/contours/arr") {
        const confidence = cur.float();
        const m = cur.count();  // varies per contour – always loop on m
        const points = [];
        for (let j = 0; j < m; j++) points.push({ x: cur.float(), y: cur.float() });
        frame.detections.push({ confidence, points });
      } else if (address === "/poses3d/arr") {
        const confidence = cur.float();
        const bodyHeight = cur.float();
        const joints = [];
        for (let j = 0; j < 17; j++) joints.push({ x: cur.float(), y: cur.float(), z: cur.float(), px: cur.float(), py: cur.float() });
        frame.detections.push({ confidence, bodyHeight, joints });
      } else if (address === "/barcodes/arr") {
        const confidence = cur.float();
        const box = cur.rect();
        const corners = [];
        for (let j = 0; j < 4; j++) corners.push({ x: cur.float(), y: cur.float() });
        frame.detections.push({ confidence, box, corners, symbology: cur.string(), payload: cur.string() });
      } else if (address === "/rectangles/arr") {
        const confidence = cur.float();
        const box = cur.rect();
        const corners = [];
        for (let j = 0; j < 4; j++) corners.push({ x: cur.float(), y: cur.float() });
        frame.detections.push({ confidence, box, corners });
      } else if (address === "/horizon") {
        frame.detections.push({ confidence: cur.float(), angle: cur.float(),
          start: { x: cur.float(), y: cur.float() }, end: { x: cur.float(), y: cur.float() } });
      }
    }
    return frame;
  }

  /** Aspect-fit a sent frame into a canvas: returns {sc, ox, oy}. */
  function fit(frameW, frameH, width, height) {
    const sc = Math.min(width / frameW, height / frameH);
    return { sc, ox: (width - frameW * sc) / 2, oy: (height - frameH * sc) / 2 };
  }

  const visible = (point) => point.c > 0;

  class TrackOSCClient {
    constructor(url = "ws://localhost:8765") {
      this.url = url;
      this.frames = {};      // address → latest frame
      this.camera = null;
      this.connected = false;
      this.unknown = 0;
      this.messageCount = 0;
      this._connect();
    }

    _connect() {
      const socket = new WebSocket(this.url);
      socket.onopen = () => { this.connected = true; };
      socket.onclose = () => { this.connected = false; setTimeout(() => this._connect(), 1000); };
      socket.onerror = () => socket.close();
      socket.onmessage = (event) => {
        let message;
        try { message = JSON.parse(event.data); } catch (_) { return; }
        this.messageCount++;
        let frame;
        try { frame = parseMessage(message.address, message.args || []); } catch (_) { frame = null; }
        if (frame === null) this.unknown++;
        else if (frame.address === "/camerainfo") this.camera = frame;
        else this.frames[frame.address] = frame;
      };
    }

    /** The latest frame for an address if it arrived in the last 500 ms, else null. */
    fresh(address) {
      const frame = this.frames[address];
      return frame && now() - frame.at < STALE_MS ? frame : null;
    }

    /** Every fresh frame, keyed by address. */
    freshFrames() {
      const result = {};
      for (const address of Object.keys(this.frames)) { const f = this.fresh(address); if (f) result[address] = f; }
      return result;
    }

    /** The latest /camerainfo if it arrived in the last 2 s, else null. */
    freshCamera() {
      return this.camera && now() - this.camera.at < CAMERA_INFO_STALE_MS ? this.camera : null;
    }
  }

  return { TrackOSCClient, parseMessage, fit, visible, KEYPOINT_COUNTS, ALL_ADDRESSES, STALE_MS };
}));
