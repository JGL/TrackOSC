//
//  USDAWriter.swift
//  Costume3DCore
//
//  Writes a rigged USD (text) file in Apple's motion-capture convention:
//  the 91-joint skeleton in its T-pose plus a mesh of blocks, one per
//  bone, each skinned rigidly to its joint. Used for the bundled Blocky
//  model and as a reference for anyone checking their own export.
//

import Foundation
import simd

public enum USDAWriter {
    public struct Block: Sendable {
        public var joint: String
        public var toJoint: String
        public var thickness: Float
        public var colour: SIMD3<Float>
        public init(joint: String, toJoint: String, thickness: Float, colour: SIMD3<Float>) {
            self.joint = joint; self.toJoint = toJoint; self.thickness = thickness; self.colour = colour
        }
    }

    /// The blocks that make Blocky: torso, head, limbs, hands, feet.
    public static let blockyBlocks: [Block] = {
        let skin = SIMD3<Float>(0.93, 0.78, 0.62), shirt = SIMD3<Float>(0.25, 0.55, 0.95), trousers = SIMD3<Float>(0.25, 0.28, 0.45), shoe = SIMD3<Float>(0.15, 0.15, 0.17)
        var b: [Block] = [
            Block(joint: "hips_joint", toJoint: "spine_7_joint", thickness: 0.30, colour: shirt),
            Block(joint: "neck_1_joint", toJoint: "head_joint", thickness: 0.10, colour: skin),
            Block(joint: "head_joint", toJoint: "head_top", thickness: 0.22, colour: skin),
        ]
        for side in ["left", "right"] {
            b += [
                Block(joint: "\(side)_arm_joint", toJoint: "\(side)_forearm_joint", thickness: 0.10, colour: shirt),
                Block(joint: "\(side)_forearm_joint", toJoint: "\(side)_hand_joint", thickness: 0.085, colour: skin),
                Block(joint: "\(side)_hand_joint", toJoint: "\(side)_handMidEnd_joint", thickness: 0.07, colour: skin),
                Block(joint: "\(side)_upLeg_joint", toJoint: "\(side)_leg_joint", thickness: 0.14, colour: trousers),
                Block(joint: "\(side)_leg_joint", toJoint: "\(side)_foot_joint", thickness: 0.11, colour: trousers),
                Block(joint: "\(side)_foot_joint", toJoint: "\(side)_toesEnd_joint", thickness: 0.09, colour: shoe),
            ]
        }
        return b
    }()

    public static func blocky(name: String = "Blocky") -> String {
        write(name: name, rest: RestPose.tPose(), positions: RestPose.tPosePositions, blocks: blockyBlocks)
    }

    public static func write(name: String, rest: RestPose, positions: [String: SIMD3<Float>], blocks: [Block]) -> String {
        let world = rest.worldTransforms()
        func f(_ v: Float) -> String { String(format: "%.5g", v) }
        func matrix(_ m: simd_float4x4) -> String {
            let c = m.columns
            // USD matrices are row-major with the translation in the last row (row vectors).
            return "( (\(f(c.0.x)), \(f(c.0.y)), \(f(c.0.z)), \(f(c.0.w))), (\(f(c.1.x)), \(f(c.1.y)), \(f(c.1.z)), \(f(c.1.w))), (\(f(c.2.x)), \(f(c.2.y)), \(f(c.2.z)), \(f(c.2.w))), (\(f(c.3.x)), \(f(c.3.y)), \(f(c.3.z)), \(f(c.3.w))) )"
        }
        func transform(rotation: simd_quatf, translation: SIMD3<Float>) -> simd_float4x4 {
            var m = simd_float4x4(rotation)
            m.columns.3 = SIMD4<Float>(translation, 1)
            return m
        }
        var s = "#usda 1.0\n(\n    defaultPrim = \"\(name)\"\n    metersPerUnit = 1\n    upAxis = \"Y\"\n)\n\n"
        s += "def SkelRoot \"\(name)\" (\n    prepend apiSchemas = [\"SkelBindingAPI\"]\n)\n{\n"
        s += "    rel skel:skeleton = </\(name)/Skeleton>\n\n"
        s += "    def Skeleton \"Skeleton\"\n    {\n"
        s += "        uniform token[] joints = [" + rest.paths.map { "\"\($0)\"" }.joined(separator: ", ") + "]\n"
        s += "        uniform matrix4d[] bindTransforms = [" + (0..<rest.count).map { matrix(transform(rotation: world.rotations[$0], translation: world.positions[$0])) }.joined(separator: ", ") + "]\n"
        s += "        uniform matrix4d[] restTransforms = [" + (0..<rest.count).map { matrix(transform(rotation: rest.localRotations[$0], translation: rest.localTranslations[$0])) }.joined(separator: ", ") + "]\n"
        s += "    }\n\n"

        // Blocks: a box along each bone in world (bind) space, every vertex weighted to the block's joint.
        var points: [SIMD3<Float>] = [], counts: [Int] = [], indices: [Int] = [], jointIndices: [Int] = [], colours: [SIMD3<Float>] = []
        let jointIndex = Dictionary(uniqueKeysWithValues: rest.names.enumerated().map { ($1, $0) })
        for block in blocks {
            guard let a = positions[block.joint], let ji = jointIndex[block.joint] else { continue }
            let b: SIMD3<Float>
            if block.toJoint == "head_top" { b = a + SIMD3<Float>(0, 0.24, 0) } else if let p = positions[block.toJoint] { b = p } else { continue }
            let axis = b - a
            let length = simd_length(axis)
            guard length > 1e-4 else { continue }
            let x = axis / length
            let frame = RestPose.frame(x: x, hint: SIMD3<Float>(0, 0, 1))
            let y = frame.act(SIMD3<Float>(0, 1, 0)), z = frame.act(SIMD3<Float>(0, 0, 1))
            let t = block.thickness / 2
            let base = points.count
            for i in 0..<8 {
                let sx: Float = (i & 1) == 0 ? 0 : length
                let sy: Float = (i & 2) == 0 ? -t : t
                let sz: Float = (i & 4) == 0 ? -t : t
                points.append(a + x * sx + y * sy + z * sz)
                jointIndices.append(ji)
                colours.append(block.colour)
            }
            // Six quads (outward winding).
            let faces = [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
            for face in faces { counts.append(4); indices += face.map { base + $0 } }
        }
        s += "    def Mesh \"Body\" (\n        prepend apiSchemas = [\"SkelBindingAPI\"]\n    )\n    {\n"
        s += "        int[] faceVertexCounts = [" + counts.map(String.init).joined(separator: ", ") + "]\n"
        s += "        int[] faceVertexIndices = [" + indices.map(String.init).joined(separator: ", ") + "]\n"
        s += "        point3f[] points = [" + points.map { "(\(f($0.x)), \(f($0.y)), \(f($0.z)))" }.joined(separator: ", ") + "]\n"
        s += "        color3f[] primvars:displayColor = [" + colours.map { "(\(f($0.x)), \(f($0.y)), \(f($0.z)))" }.joined(separator: ", ") + "] (\n            interpolation = \"vertex\"\n        )\n"
        s += "        int[] primvars:skel:jointIndices = [" + jointIndices.map(String.init).joined(separator: ", ") + "] (\n            elementSize = 1\n            interpolation = \"vertex\"\n        )\n"
        s += "        float[] primvars:skel:jointWeights = [" + jointIndices.map { _ in "1" }.joined(separator: ", ") + "] (\n            elementSize = 1\n            interpolation = \"vertex\"\n        )\n"
        s += "        matrix4d primvars:skel:geomBindTransform = ( (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1) )\n"
        s += "        rel skel:skeleton = </\(name)/Skeleton>\n"
        s += "        uniform token subdivisionScheme = \"none\"\n"
        s += "    }\n}\n"
        return s
    }
}
