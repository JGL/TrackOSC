//
//  Skeleton.swift
//  PoseioscShared
//
//  Edge lists for drawing skeletons, shared by the iOS overlay and the macOS
//  visualiser so both render identical geometry. Indices refer to
//  `JointOrder.body17` / `JointOrder.hand21` / `JointOrder.body3D17` /
//  `JointOrder.animal25`.
//
//  Examples/SKELETONS.md is a copy of these lists for non-Swift receivers –
//  keep it in sync.
//

public enum Skeleton {
    /// Limb pairs for the 17-joint PoseNet body skeleton.
    public static let body17Edges: [(Int, Int)] = [
        // head
        (0, 1), (0, 2), (1, 3), (2, 4),
        // torso
        (5, 6), (5, 11), (6, 12), (11, 12),
        // left arm (indices 5,7,9)
        (5, 7), (7, 9),
        // right arm (indices 6,8,10)
        (6, 8), (8, 10),
        // left leg (11,13,15)
        (11, 13), (13, 15),
        // right leg (12,14,16)
        (12, 14), (14, 16)
    ]

    /// Finger chains for the 21-joint hand skeleton: wrist → each finger base → tip.
    public static let hand21Edges: [(Int, Int)] = [
        // thumb: wrist → CMC → MP → IP → tip
        (0, 1), (1, 2), (2, 3), (3, 4),
        // index: wrist → MCP → PIP → DIP → tip
        (0, 5), (5, 6), (6, 7), (7, 8),
        // middle
        (0, 9), (9, 10), (10, 11), (11, 12),
        // ring
        (0, 13), (13, 14), (14, 15), (15, 16),
        // pinky
        (0, 17), (17, 18), (18, 19), (19, 20)
    ]

    /// Parent → child pairs for Vision's 17-joint 3D body skeleton
    /// (`JointOrder.body3D17`), matching Vision's own joint hierarchy.
    public static let body3D17Edges: [(Int, Int)] = [
        // spine: root → spine → centerShoulder → centerHead → topHead
        (0, 1), (1, 2), (2, 3), (3, 4),
        // left arm (5,6,7)
        (2, 5), (5, 6), (6, 7),
        // right arm (8,9,10)
        (2, 8), (8, 9), (9, 10),
        // left leg (11,12,13)
        (0, 11), (11, 12), (12, 13),
        // right leg (14,15,16)
        (0, 14), (14, 15), (15, 16)
    ]

    /// Limb pairs for Vision's 25-joint animal (cat/dog) skeleton (`JointOrder.animal25`).
    public static let animal25Edges: [(Int, Int)] = [
        // face: nose → eyes
        (0, 1), (0, 2),
        // ears: eye → ear bottom → middle → top
        (1, 5), (5, 4), (4, 3),
        (2, 8), (8, 7), (7, 6),
        // nose → neck
        (0, 9),
        // front legs: neck → elbow → knee → paw
        (9, 10), (10, 11), (11, 12),
        (9, 13), (13, 14), (14, 15),
        // spine: neck → tailTop
        (9, 22),
        // back legs: tailTop → elbow → knee → paw
        (22, 16), (16, 17), (17, 18),
        (22, 19), (19, 20), (20, 21),
        // tail
        (22, 23), (23, 24)
    ]
}
