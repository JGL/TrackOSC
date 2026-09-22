//
//  OverlayView.swift
//  TrackOSC Sender (shared)
//
//  Draws the latest detections over the camera preview. Wire coordinates are
//  pixels in the oriented frame; the preview uses aspect-fill, so the same
//  scale/offset math is applied here to keep the overlay registered.
//

import SwiftUI
import PoseioscShared

struct OverlayView: View {
    let snapshot: OverlaySnapshot
    var mirrored = false

    var body: some View {
        Canvas { context, size in
            guard snapshot.width > 0, snapshot.height > 0 else { return }
            let frameW = CGFloat(snapshot.width)
            let frameH = CGFloat(snapshot.height)

            // Aspect-fill: scale up so the frame covers the view, centered.
            let scale = max(size.width / frameW, size.height / frameH)
            let offsetX = (size.width - frameW * scale) / 2
            let offsetY = (size.height - frameH * scale) / 2

            // In selfie-mirror mode, flip x here (rather than transforming the
            // canvas) so drawn label text stays readable.
            func map(_ p: WirePoint) -> CGPoint {
                let x = offsetX + CGFloat(p.x) * scale
                return CGPoint(x: mirrored ? size.width - x : x, y: offsetY + CGFloat(p.y) * scale)
            }
            func map(_ p: WireXY) -> CGPoint {
                let x = offsetX + CGFloat(p.x) * scale
                return CGPoint(x: mirrored ? size.width - x : x, y: offsetY + CGFloat(p.y) * scale)
            }
            func map(_ r: WireRect) -> CGRect {
                var x = offsetX + CGFloat(r.left) * scale
                let width = CGFloat(r.width) * scale
                if mirrored { x = size.width - x - width }
                return CGRect(
                    x: x,
                    y: offsetY + CGFloat(r.top) * scale,
                    width: width,
                    height: CGFloat(r.height) * scale
                )
            }

            for human in snapshot.humans {
                drawBox(context: context, rect: map(human.box), label: nil, color: Detector.humans.color)
            }
            for pose in snapshot.poses {
                drawSkeleton(context: context, points: pose.joints, edges: Skeleton.body17Edges, color: Detector.poses.color, map: map)
            }
            for pose in snapshot.poses3D {
                // Drawn from the 2D projections; the label shows the root's
                // depth and the body height (also the on-device axis check).
                let projected = pose.joints.map { WirePoint(x: $0.px, y: $0.py, confidence: 1) }
                drawSkeleton(context: context, points: projected, edges: Skeleton.body3D17Edges, color: Detector.poses3D.color, map: map)
                let head = map(projected[4])
                drawLabel(
                    context: context,
                    String(format: "%.2f m · z %.2f", pose.bodyHeight, pose.joints[0].z),
                    at: CGPoint(x: head.x, y: head.y - 12),
                    anchor: .bottom,
                    color: Detector.poses3D.color
                )
            }
            for hand in snapshot.hands {
                drawSkeleton(context: context, points: hand.joints, edges: Skeleton.hand21Edges, color: Detector.hands.color, map: map)
            }
            for animal in snapshot.animalPoses {
                drawSkeleton(context: context, points: animal.joints, edges: Skeleton.animal25Edges, color: Detector.animalPoses.color, map: map)
            }
            for face in snapshot.faces {
                for point in face.points where point.confidence > 0 {
                    let p = map(point)
                    context.fill(
                        Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)),
                        with: .color(Detector.faces.color)
                    )
                }
            }
            for faceBox in snapshot.faceBoxes {
                context.stroke(Path(map(faceBox.box)), with: .color(Detector.faces.color), lineWidth: 2)
            }
            for contour in snapshot.faceContours where !contour.points.isEmpty {
                // The jawline is an open polyline – mapped per-vertex so
                // selfie mirroring lands correctly, and never closed.
                var path = Path()
                path.move(to: map(contour.points[0]))
                for point in contour.points.dropFirst() {
                    path.addLine(to: map(point))
                }
                context.stroke(path, with: .color(Detector.faces.color), lineWidth: 2)
            }
            for box in snapshot.texts {
                drawBox(context: context, rect: map(box.box), label: box.label, color: Detector.texts.color)
            }
            for box in snapshot.animals {
                drawBox(context: context, rect: map(box.box), label: box.label, color: Detector.animals.color)
            }
            for barcode in snapshot.barcodes {
                // The quadrilateral in the code's own orientation, closed; a
                // dot marks its top-left corner (the wire's corner order).
                let corners = barcode.corners.map(map)
                guard corners.count == 4 else { continue }
                var path = Path()
                path.move(to: corners[0])
                for corner in corners.dropFirst() {
                    path.addLine(to: corner)
                }
                path.closeSubpath()
                let color = Detector.barcodes.color
                context.stroke(path, with: .color(color), lineWidth: 2)
                context.fill(
                    Path(ellipseIn: CGRect(x: corners[0].x - 4, y: corners[0].y - 4, width: 8, height: 8)),
                    with: .color(color)
                )
                let top = corners.min { $0.y < $1.y } ?? corners[0]
                drawLabel(
                    context: context,
                    "\(barcode.symbology) \(barcode.payload.prefix(24))",
                    at: CGPoint(x: top.x, y: max(top.y - 10, 8)),
                    anchor: .bottom,
                    color: color
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func drawSkeleton(
        context: GraphicsContext,
        points: [WirePoint],
        edges: [(Int, Int)],
        color: Color,
        map: (WirePoint) -> CGPoint
    ) {
        var path = Path()
        for (a, b) in edges {
            guard a < points.count, b < points.count else { continue }
            let pa = points[a], pb = points[b]
            guard pa.confidence > 0, pb.confidence > 0 else { continue }
            path.move(to: map(pa))
            path.addLine(to: map(pb))
        }
        context.stroke(path, with: .color(color), lineWidth: 2)
        for point in points where point.confidence > 0 {
            let p = map(point)
            context.fill(
                Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                with: .color(color.opacity(0.9))
            )
        }
    }

    private func drawBox(context: GraphicsContext, rect: CGRect, label: String?, color: Color) {
        context.stroke(Path(rect), with: .color(color), lineWidth: 2)
        if let label {
            drawLabel(
                context: context,
                label,
                at: CGPoint(x: rect.minX + 4, y: max(rect.minY - 10, 8)),
                anchor: .leading,
                color: color
            )
        }
    }

    private func drawLabel(context: GraphicsContext, _ text: String, at point: CGPoint, anchor: UnitPoint, color: Color) {
        let label = Text(text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
        context.draw(label, at: point, anchor: anchor)
    }
}
