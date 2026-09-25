//
//  Filters.swift
//  SynthCore
//
//  A zero-delay-feedback four-pole ladder (the 303/Moog character) after
//  Zavalishin, with a soft-clipped feedback path so it stays stable at
//  full resonance, and a Simper state-variable filter for the drums.
//

import Foundation

@inline(__always)
func softClip(_ x: Float) -> Float {
    // tanh-like, cheap and monotonic.
    let x2 = x * x
    return x * (27 + x2) / (27 + 9 * x2)
}

public struct LadderFilter {
    private var s = SIMD4<Float>(repeating: 0)   // integrator states
    public init() {}

    public mutating func reset() { s = .zero }

    /// One sample. `cutoff` in Hz, `resonance` 0…1 (self-oscillation near 1).
    @inline(__always)
    public mutating func process(_ input: Float, cutoff: Float, resonance: Float, sampleRate: Float) -> Float {
        let fc = min(max(cutoff, 20), sampleRate * 0.45)
        let g = tanf(Float.pi * fc / sampleRate)          // TPT one-pole coefficient
        let G = g / (1 + g)
        let k = min(max(resonance, 0), 1) * 4.2            // feedback gain, > 4 self-oscillates
        // Solve the zero-delay feedback loop: y = G^4 * (x - k*y_fb) + states
        let G2 = G * G, G3 = G2 * G, G4 = G3 * G
        let S = (G3 * s[0] + G2 * s[1] + G * s[2] + s[3]) / (1 + g)
        let u = (input - k * softClip(S)) / (1 + k * G4)
        // Four cascaded one-poles.
        var v = G * (u - s[0]); var y0 = v + s[0]; s[0] = y0 + v
        v = G * (y0 - s[1]); var y1 = v + s[1]; s[1] = y1 + v
        v = G * (y1 - s[2]); var y2 = v + s[2]; s[2] = y2 + v
        v = G * (y2 - s[3]); let y3 = v + s[3]; s[3] = y3 + v
        // Keep the states finite whatever the input does.
        if !y3.isFinite { reset(); return 0 }
        y0 = 0; y1 = 0; y2 = 0
        return y3
    }
}

/// Simper's linear trapezoidal SVF: low, band and high outputs at once.
public struct StateVariableFilter {
    public enum Mode: Sendable { case low, band, high }
    private var ic1eq: Float = 0
    private var ic2eq: Float = 0
    public init() {}

    public mutating func reset() { ic1eq = 0; ic2eq = 0 }

    @inline(__always)
    public mutating func process(_ input: Float, cutoff: Float, q: Float, mode: Mode, sampleRate: Float) -> Float {
        let g = tanf(Float.pi * min(max(cutoff, 10), sampleRate * 0.45) / sampleRate)
        let k = 1 / max(q, 0.1)
        let a1 = 1 / (1 + g * (g + k))
        let a2 = g * a1
        let a3 = g * a2
        let v3 = input - ic2eq
        let v1 = a1 * ic1eq + a2 * v3
        let v2 = ic2eq + a2 * ic1eq + a3 * v3
        ic1eq = 2 * v1 - ic1eq
        ic2eq = 2 * v2 - ic2eq
        switch mode {
        case .low: return v2
        case .band: return v1
        case .high: return input - k * v1 - v2
        }
    }
}

/// Exponential decay envelope with an instant or short attack.
public struct DecayEnvelope {
    private var level: Float = 0
    private var attackRemaining = 0
    public init() {}

    public var value: Float { level }
    public var isActive: Bool { level > 1e-4 }

    public mutating func trigger(level: Float = 1, attackSamples: Int = 0) {
        self.level = attackSamples > 0 ? 0 : level
        attackRemaining = attackSamples
        peak = level
    }
    private var peak: Float = 1

    /// `decaySeconds` is the time to fall to about 1 % (−40 dB).
    @inline(__always)
    public mutating func next(decaySeconds: Float, sampleRate: Float) -> Float {
        if attackRemaining > 0 {
            attackRemaining -= 1
            level += (peak - level) * 0.3
            return level
        }
        let coefficient = expf(-4.6 / max(decaySeconds * sampleRate, 1))
        level *= coefficient
        return level
    }
}

/// One-pole smoother for parameters that must not step.
public struct Smoother {
    private var value: Float
    public init(_ initial: Float = 0) { value = initial }

    @inline(__always)
    public mutating func next(target: Float, coefficient: Float) -> Float {
        value += (target - value) * coefficient
        return value
    }

    public mutating func set(_ v: Float) { value = v }
}
