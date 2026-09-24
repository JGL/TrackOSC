//
//  main.swift
//  poseiosc-testlisten
//
//  Headless OSC listener that decodes Poseiosc/VisionOSC messages and prints a
//  one-line summary per message. Useful for verifying a sender without the
//  receiver GUI. Note: only one process can bind the port at a time – quit the
//  Poseiosc Receiver app first.
//
//  Usage: swift run poseiosc-testlisten [port]
//  Default port: 9527
//

import Foundation
import PoseioscShared
import SwiftOSC

let arguments = CommandLine.arguments
let port = arguments.count > 1 ? UInt16(arguments[1]) ?? 9527 : 9527

func summarize(_ decoded: DecodedFrame) -> String {
    switch decoded {
    case .poses(let f):
        return "/poses/arr   \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in String(format: " conf=%.2f nose=(%.0f,%.0f)", d.confidence, d.joints[0].x, d.joints[0].y) } ?? "")
    case .hands(let f):
        return "/hands/arr   \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in String(format: " conf=%.2f wrist=(%.0f,%.0f)", d.confidence, d.joints[0].x, d.joints[0].y) } ?? "")
    case .faces(let f):
        return "/faces/arr   \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in String(format: " conf=%.2f p0=(%.0f,%.0f)", d.confidence, d.points[0].x, d.points[0].y) } ?? "")
    case .texts(let f):
        return "/texts/arr   \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in " \"\(d.label)\"" } ?? "")
    case .animals(let f):
        return "/animals/arr \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in " \"\(d.label)\"" } ?? "")
    case .cameraInfo(let info):
        return "/camerainfo  \(info.width)x\(info.height) \(info.orientationName) \(info.isFrontCamera ? "front" : "back")"
    case .faceBoxes(let f):
        return "/faces/box   \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in String(format: " conf=%.2f box=(%.0f,%.0f %.0fx%.0f) roll=%.0f°", d.confidence, d.box.left, d.box.top, d.box.width, d.box.height, d.rollDegrees) } ?? "")
    case .faceContours(let f):
        return "/faces/contour \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in String(format: " conf=%.2f m=%d", d.confidence, d.points.count) } ?? "")
    case .poses3D(let f):
        return "/poses3d/arr \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in
                String(format: " conf=%.2f height=%.2fm root=(%.2f,%.2f,%.2f)m px=(%.0f,%.0f)",
                       d.confidence, d.bodyHeight, d.joints[0].x, d.joints[0].y, d.joints[0].z, d.joints[0].px, d.joints[0].py)
            } ?? "")
    case .barcodes(let f):
        return "/barcodes/arr \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in " \(d.symbology) \"\(d.payload)\"" } ?? "")
    case .animalPoses(let f):
        return "/animalposes/arr \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in String(format: " conf=%.2f nose=(%.0f,%.0f)", d.confidence, d.joints[0].x, d.joints[0].y) } ?? "")
    case .humans(let f):
        return "/humans/arr  \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in String(format: " conf=%.2f box=(%.0f,%.0f %.0fx%.0f)", d.confidence, d.box.left, d.box.top, d.box.width, d.box.height) } ?? "")
    case .contours(let f):
        return "/contours/arr \(f.width)x\(f.height) n=\(f.detections.count)" +
            " points=\(f.detections.reduce(0) { $0 + $1.points.count })"
    case .horizon(let f):
        return "/horizon     \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in String(format: " angle=%.1f° (%.0f,%.0f)→(%.0f,%.0f)", d.angleDegrees, d.start.x, d.start.y, d.end.x, d.end.y) } ?? "")
    case .rectangles(let f):
        return "/rectangles/arr \(f.width)x\(f.height) n=\(f.detections.count)" +
            (f.detections.first.map { d in String(format: " conf=%.2f box=(%.0f,%.0f %.0fx%.0f)", d.confidence, d.box.left, d.box.top, d.box.width, d.box.height) } ?? "")
    }
}

let server = OSCUDPServer(port: port)
server.setReceiveHandler(.messages { message, _, host, senderPort in
    do {
        let decoded = try WireCodec.decode(message)
        print("[\(host):\(senderPort)] \(summarize(decoded))")
    } catch {
        print("[\(host):\(senderPort)] undecodable \(message.addressPattern.stringValue): \(error)")
    }
})

do {
    try server.start()
} catch {
    FileHandle.standardError.write("Failed to listen on UDP \(port): \(error)\n".data(using: .utf8)!)
    exit(1)
}

print("poseiosc-testlisten on UDP \(port) (Ctrl-C to stop)")
RunLoop.main.run()
