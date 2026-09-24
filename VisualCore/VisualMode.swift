//
//  VisualMode.swift
//  TrackOSC (VisualCore)
//
//  One entry in an app's mode catalogue: a Metal fragment function plus
//  the parameters it reads from the uniform block.
//

import Foundation

struct VisualMode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let blurb: String
    /// Name of the fragment function in the app's default Metal library.
    let fragment: String
    /// Reads the previous frame (trails, accumulation).
    var usesFeedback = false
    let parameters: [ParameterSpec]

    static func == (lhs: VisualMode, rhs: VisualMode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
