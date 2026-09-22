//
//  CoordinateMapper.swift
//  PoseioscShared
//
//  Vision-space → wire-space conversion, matching VisionOSC exactly:
//  Vision uses normalized coordinates with origin bottom-left;
//  the wire format uses pixels with origin top-left.
//

import Foundation

public enum CoordinateMapper {
    /// Convert a Vision normalized point (origin bottom-left) to wire pixels (origin top-left).
    public static func point(
        normalizedX x: CGFloat,
        normalizedY y: CGFloat,
        confidence: Float,
        frameWidth: Float,
        frameHeight: Float
    ) -> WirePoint {
        WirePoint(
            x: Float(x) * frameWidth,
            y: (1 - Float(y)) * frameHeight,
            confidence: confidence
        )
    }

    /// Convert a Vision normalized bounding box (origin bottom-left) to a wire rect
    /// (pixels, origin top-left).
    public static func rect(
        normalized box: CGRect,
        frameWidth: Float,
        frameHeight: Float
    ) -> WireRect {
        WireRect(
            left: Float(box.origin.x) * frameWidth,
            top: (1 - Float(box.origin.y) - Float(box.size.height)) * frameHeight,
            width: Float(box.size.width) * frameWidth,
            height: Float(box.size.height) * frameHeight
        )
    }

    /// Convert a Vision normalized point (origin bottom-left) to a bare wire
    /// coordinate pair (pixels, origin top-left) – for points that carry no
    /// per-point confidence, such as barcode corners.
    public static func xy(
        normalizedX x: CGFloat,
        normalizedY y: CGFloat,
        frameWidth: Float,
        frameHeight: Float
    ) -> WireXY {
        WireXY(
            x: Float(x) * frameWidth,
            y: (1 - Float(y)) * frameHeight
        )
    }
}
