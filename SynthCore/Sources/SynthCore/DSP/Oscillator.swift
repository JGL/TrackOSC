//
//  Oscillator.swift
//  SynthCore
//
//  PolyBLEP sawtooth and pulse: the discontinuities are corrected with a
//  two-sample polynomial band-limited step, which removes most of the
//  aliasing of a naive waveform at a fraction of the cost of oversampling.
//

import Foundation

public struct Oscillator {
    public enum Shape: Sendable { case saw, pulse }

    public var shape: Shape = .saw
    public var pulseWidth: Float = 0.5
    private var phase: Float = 0

    public init(shape: Shape = .saw) { self.shape = shape }

    public mutating func reset() { phase = 0 }

    /// PolyBLEP residual for a discontinuity at phase 0 with phase step `dt`.
    @inline(__always)
    static func blep(_ t: Float, _ dt: Float) -> Float {
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        } else if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }

    /// Next sample for a frequency (Hz) at a sample rate; output in −1…1.
    @inline(__always)
    public mutating func next(frequency: Float, sampleRate: Float) -> Float {
        let dt = max(frequency, 0) / sampleRate
        let t = phase
        var value: Float
        switch shape {
        case .saw:
            value = 2 * t - 1
            value -= Self.blep(t, dt)
        case .pulse:
            let width = min(max(pulseWidth, 0.05), 0.95)
            value = t < width ? 1 : -1
            value += Self.blep(t, dt)
            var t2 = t + 1 - width
            t2 -= floorf(t2)
            value -= Self.blep(t2, dt)
        }
        phase += dt
        if phase >= 1 { phase -= 1 }
        return value
    }

    /// The same waveform without correction, for tests that measure aliasing.
    public static func naive(shape: Shape, phase t: Float, pulseWidth: Float = 0.5) -> Float {
        switch shape {
        case .saw: return 2 * t - 1
        case .pulse: return t < pulseWidth ? 1 : -1
        }
    }
}

/// xorshift32 white noise, −1…1.
public struct Noise {
    private var state: UInt32
    public init(seed: UInt32 = 0x9E3779B9) { state = seed == 0 ? 1 : seed }

    @inline(__always)
    public mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(state) / Float(UInt32.max) * 2 - 1
    }
}
