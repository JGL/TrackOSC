//
//  SourceReader.swift
//  TrackOSC Router (macOS)
//
//  Reads a ValueSource from the latest frames. Counts are 0 when the kind
//  is stale; positions are nil when the person or joint is missing.
//

import Foundation
import PoseioscShared

enum SourceReader {
    static func read(_ source: ValueSource, latest: [FrameKind: TimestampedFrame], now: Date, staleInterval: TimeInterval) -> SourceValue {
        func fresh(_ kind: FrameKind) -> DecodedFrame? {
            guard let frame = latest[kind], now.timeIntervalSince(frame.receivedAt) < staleInterval else { return nil }
            return frame.decoded
        }
        func count(_ kind: FrameKind) -> SourceValue {
            .number(Double(fresh(kind)?.detectionCount ?? 0))
        }
        let person = source.person

        switch source.kind {
        case .peopleCount: return count(.poses)
        case .handCount: return count(.hands)
        case .faceCount: return count(.faces)
        case .animalCount: return count(.animals)
        case .textCount: return count(.texts)
        case .barcodeCount: return count(.barcodes)
        case .humanCount: return count(.humans)

        case .noseX, .noseY, .jointX, .jointY, .leftHandRaised, .rightHandRaised:
            guard case .poses(let f)? = fresh(.poses), f.detections.indices.contains(person) else { return .none }
            let pose = f.detections[person]
            switch source.kind {
            case .noseX: return FrameMetrics.nose(of: pose, in: (f.width, f.height)).map { .number($0.x) } ?? .none
            case .noseY: return FrameMetrics.nose(of: pose, in: (f.width, f.height)).map { .number($0.y) } ?? .none
            case .leftHandRaised: return .number(FrameMetrics.raisedHands(of: pose).left ? 1 : 0)
            case .rightHandRaised: return .number(FrameMetrics.raisedHands(of: pose).right ? 1 : 0)
            default:
                guard pose.joints.indices.contains(source.joint),
                      let n = FrameMetrics.normalised(pose.joints[source.joint], in: (f.width, f.height)) else { return .none }
                return .number(source.kind == .jointX ? n.x : n.y)
            }

        case .handJointX, .handJointY:
            guard case .hands(let f)? = fresh(.hands), f.detections.indices.contains(person) else { return .none }
            let hand = f.detections[person]
            guard hand.joints.indices.contains(source.joint),
                  let n = FrameMetrics.normalised(hand.joints[source.joint], in: (f.width, f.height)) else { return .none }
            return .number(source.kind == .handJointX ? n.x : n.y)

        case .faceCentreX, .faceCentreY, .faceWidth, .faceYaw, .facePitch, .faceRoll:
            guard case .faceBoxes(let f)? = fresh(.faceBoxes), f.detections.indices.contains(person) else { return .none }
            let face = f.detections[person]
            switch source.kind {
            case .faceCentreX: return FrameMetrics.normalisedCentre(of: face.box, in: (f.width, f.height)).map { .number($0.x) } ?? .none
            case .faceCentreY: return FrameMetrics.normalisedCentre(of: face.box, in: (f.width, f.height)).map { .number($0.y) } ?? .none
            case .faceWidth: return f.width > 0 ? .number(Double(face.box.width) / Double(f.width)) : .none
            case .faceYaw: return .number(Double(face.yawDegrees))
            case .facePitch: return .number(Double(face.pitchDegrees))
            default: return .number(Double(face.rollDegrees))
            }

        case .mouthOpenness:
            guard case .faces(let f)? = fresh(.faces), f.detections.indices.contains(person),
                  let openness = FaceLandmarks.mouthOpenness(f.detections[person].points) else { return .none }
            return .number(Double(min(openness, 1)))

        case .distance3D, .bodyHeight:
            guard case .poses3D(let f)? = fresh(.poses3D), f.detections.indices.contains(person) else { return .none }
            let pose = f.detections[person]
            if source.kind == .bodyHeight { return pose.bodyHeight > 0 ? .number(Double(pose.bodyHeight)) : .none }
            return FrameMetrics.distance(of: pose).map { .number($0) } ?? .none

        case .recognisedText:
            guard case .texts(let f)? = fresh(.texts), f.detections.indices.contains(person) else { return .none }
            return .text(f.detections[person].label)
        case .barcodePayload:
            guard case .barcodes(let f)? = fresh(.barcodes), f.detections.indices.contains(person) else { return .none }
            return .text(f.detections[person].payload)
        case .barcodeSymbology:
            guard case .barcodes(let f)? = fresh(.barcodes), f.detections.indices.contains(person) else { return .none }
            return .text(f.detections[person].symbology)
        case .animalLabel:
            guard case .animals(let f)? = fresh(.animals), f.detections.indices.contains(person) else { return .none }
            return .text(f.detections[person].label)
        }
    }
}
