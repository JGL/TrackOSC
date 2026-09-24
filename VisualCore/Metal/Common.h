//
//  Common.h
//  TrackOSC (VisualCore)
//
//  Helpers every mode shader includes: the fragment signature, scene →
//  view mapping, palette lookup, signed distances, noise and folds.
//

#ifndef VisualCoreCommon_h
#define VisualCoreCommon_h

#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

#define MODE_ARGS VertexOut in [[stage_in]], \
    constant SceneUniforms& u [[buffer(0)]], \
    constant GPUPerson* persons [[buffer(1)]], \
    constant GPUHand* hands [[buffer(2)]], \
    constant GPUFace* faces [[buffer(3)]], \
    constant GPUAnimal* animals [[buffer(4)]], \
    texture2d<float> previous [[texture(0)]]

constexpr sampler vc_sampler(address::clamp_to_edge, filter::linear);

// ---- Scene mapping. "view space" is uv with x scaled by the aspect so
// distances are round.
inline float2 vc_sceneToUV(float2 p, constant SceneUniforms& u) { return u.sceneOrigin + p * u.sceneSize; }
inline float2 vc_view(float2 uv, constant SceneUniforms& u) { return float2(uv.x * u.aspect, uv.y); }
inline float2 vc_sceneToView(float2 p, constant SceneUniforms& u) { return vc_view(vc_sceneToUV(p, u), u); }

// ---- Palette: looping cosine-smoothed interpolation between stops.
inline float3 vc_palette(float t, constant SceneUniforms& u) {
    int n = max(u.paletteCount, 1);
    if (n == 1) return u.palette[0].rgb;
    float x = fract(t) * n;
    int i = int(floor(x)) % n;
    int j = (i + 1) % n;
    float f = smoothstep(0.0, 1.0, fract(x));
    return mix(u.palette[i].rgb, u.palette[j].rgb, f);
}

// ---- Distances.
inline float vc_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}
inline float vc_glow(float d, float radius) { return exp(-max(d, 0.0) / max(radius, 1e-4)); }

// ---- Hash and noise.
inline float vc_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
inline float vc_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = vc_hash(i), b = vc_hash(i + float2(1, 0)), c = vc_hash(i + float2(0, 1)), d = vc_hash(i + float2(1, 1));
    float2 s = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}
inline float vc_fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * vc_noise(p); p = p * 2.03 + 17.1; a *= 0.5; }
    return v;
}
inline float2 vc_rotate(float2 p, float a) { float c = cos(a), s = sin(a); return float2(c * p.x - s * p.y, s * p.x + c * p.y); }
inline float3 vc_hsv(float h, float s, float v) {
    float3 k = float3(1.0, 2.0 / 3.0, 1.0 / 3.0);
    float3 p = abs(fract(float3(h) + k) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

// ---- Body edges (JointOrder.body17) without the nose–eye–ear bones: the
// head is drawn separately (landmarks or a circle) because those bones
// read as an "M" rather than a face.
constant int2 vc_bodyEdges[12] = {
    int2(5, 6), int2(5, 7), int2(7, 9), int2(6, 8), int2(8, 10),
    int2(5, 11), int2(6, 12), int2(11, 12),
    int2(11, 13), int2(13, 15), int2(12, 14), int2(14, 16)
};
constant int vc_bodyEdgeCount = 12;

// ---- Face landmark regions (FaceLandmarks.swift): start, end (exclusive), closed.
constant int3 vc_faceRegions[9] = {
    int3(0, 6, 1), int3(7, 13, 1),          // eyes
    int3(14, 20, 0), int3(20, 26, 0),       // brows
    int3(26, 40, 1), int3(40, 46, 1),       // lips
    int3(46, 54, 0), int3(54, 59, 0),       // nose, nose crest
    int3(59, 76, 0)                         // jaw
};

/// Distance to the nearest landmark feature line of a face with landmarks.
inline float vc_landmarkDistance(float2 p, constant GPUFace& face, constant SceneUniforms& u) {
    float d = 1e9;
    for (int r = 0; r < 9; r++) {
        int start = vc_faceRegions[r].x, end = vc_faceRegions[r].y;
        for (int i = start; i < end - 1; i++) {
            d = min(d, vc_sdSegment(p, vc_sceneToView(face.landmarks[i], u), vc_sceneToView(face.landmarks[i + 1], u)));
        }
        if (vc_faceRegions[r].z == 1) {
            d = min(d, vc_sdSegment(p, vc_sceneToView(face.landmarks[end - 1], u), vc_sceneToView(face.landmarks[start], u)));
        }
    }
    return d;
}

/// Where a person's head is and how big, from nose, eyes and ears.
inline float vc_headCircle(constant GPUPerson& person, constant SceneUniforms& u, thread float2& centre) {
    float2 sum = 0.0;
    float n = 0.0;
    for (int j = 0; j < 5; j++) {
        if (person.visible[j] < 0.5) continue;
        sum += vc_sceneToView(person.joints[j], u);
        n += 1.0;
    }
    if (n < 1.0) { centre = float2(-10.0); return 0.0; }
    centre = sum / n;
    float radius = 0.0;
    if (person.visible[3] > 0.5 && person.visible[4] > 0.5) {
        radius = distance(vc_sceneToView(person.joints[3], u), vc_sceneToView(person.joints[4], u)) * 0.6;
    } else if (person.visible[1] > 0.5 && person.visible[2] > 0.5) {
        radius = distance(vc_sceneToView(person.joints[1], u), vc_sceneToView(person.joints[2], u)) * 1.3;
    } else if (person.visible[5] > 0.5 && person.visible[6] > 0.5) {
        radius = distance(vc_sceneToView(person.joints[5], u), vc_sceneToView(person.joints[6], u)) * 0.28;
    }
    return max(radius, 0.015);
}

/// Distance to a person's head: their face's landmark features when Face
/// Landmarks is arriving for them, otherwise a circle.
inline float vc_headDistance(float2 p, constant GPUPerson& person, constant SceneUniforms& u, constant GPUFace* faces) {
    for (int i = 0; i < u.faceCount; i++) {
        if (faces[i].person == person.id && faces[i].hasLandmarks > 0.5) {
            return vc_landmarkDistance(p, faces[i], u);
        }
    }
    float2 centre;
    float radius = vc_headCircle(person, u, centre);
    if (radius <= 0.0) return 1e9;
    return abs(distance(p, centre) - radius);
}

/// A face on its own (no body): landmark features, or the box's ellipse.
inline float vc_faceOutlineDistance(float2 p, constant GPUFace& face, constant SceneUniforms& u);

/// Distance from view point `p` to the nearest visible bone of a person.
inline float vc_skeletonDistance(float2 p, constant GPUPerson& person, constant SceneUniforms& u) {
    float d = 1e9;
    for (int e = 0; e < vc_bodyEdgeCount; e++) {
        int a = vc_bodyEdges[e].x, b = vc_bodyEdges[e].y;
        if (person.visible[a] < 0.5 || person.visible[b] < 0.5) continue;
        d = min(d, vc_sdSegment(p, vc_sceneToView(person.joints[a], u), vc_sceneToView(person.joints[b], u)));
    }
    return d;
}

// ---- Hand edges (JointOrder.hand21): wrist to each finger base, then along each finger.
constant int2 vc_handEdges[20] = {
    int2(0, 1), int2(1, 2), int2(2, 3), int2(3, 4),
    int2(0, 5), int2(5, 6), int2(6, 7), int2(7, 8),
    int2(0, 9), int2(9, 10), int2(10, 11), int2(11, 12),
    int2(0, 13), int2(13, 14), int2(14, 15), int2(15, 16),
    int2(0, 17), int2(17, 18), int2(18, 19), int2(19, 20)
};
constant int vc_handEdgeCount = 20;

/// Distance from view point `p` to the nearest visible bone of a hand.
inline float vc_handSkeletonDistance(float2 p, constant GPUHand& hand, constant SceneUniforms& u) {
    float d = 1e9;
    for (int e = 0; e < vc_handEdgeCount; e++) {
        int a = vc_handEdges[e].x, b = vc_handEdges[e].y;
        if (hand.visible[a] < 0.5 || hand.visible[b] < 0.5) continue;
        d = min(d, vc_sdSegment(p, vc_sceneToView(hand.joints[a], u), vc_sceneToView(hand.joints[b], u)));
    }
    return d;
}

/// Signed-ish distance to a face's outline (an ellipse on its box).
inline float vc_faceRingDistance(float2 p, constant GPUFace& face, constant SceneUniforms& u) {
    float2 c = vc_sceneToView(face.centre, u);
    float2 halfSize = max(float2(face.size.x * u.sceneSize.x * u.aspect, face.size.y * u.sceneSize.y) * 0.5, 1e-3);
    float2 q = (p - c) / halfSize;
    return (length(q) - 1.0) * min(halfSize.x, halfSize.y);
}

inline float vc_faceOutlineDistance(float2 p, constant GPUFace& face, constant SceneUniforms& u) {
    return face.hasLandmarks > 0.5 ? vc_landmarkDistance(p, face, u) : abs(vc_faceRingDistance(p, face, u));
}

/// Distance to the nearest hand bone, or the outline of a face that is not
/// attached to a tracked body (attached faces are drawn as their person's
/// head) – the "extras" a body-only look can add for free.
inline float vc_extrasDistance(float2 p, constant SceneUniforms& u, constant GPUHand* hands, constant GPUFace* faces) {
    float d = 1e9;
    for (int i = 0; i < u.handCount; i++) d = min(d, vc_handSkeletonDistance(p, hands[i], u));
    for (int i = 0; i < u.faceCount; i++) {
        if (faces[i].person >= 0.0) continue;
        d = min(d, vc_faceOutlineDistance(p, faces[i], u));
    }
    return d;
}

// ---- Animal edges (JointOrder.animal25, Skeleton.animal25Edges).
constant int2 vc_animalEdges[24] = {
    int2(0, 1), int2(0, 2),
    int2(1, 5), int2(5, 4), int2(4, 3),
    int2(2, 8), int2(8, 7), int2(7, 6),
    int2(0, 9),
    int2(9, 10), int2(10, 11), int2(11, 12),
    int2(9, 13), int2(13, 14), int2(14, 15),
    int2(9, 22),
    int2(22, 16), int2(16, 17), int2(17, 18),
    int2(22, 19), int2(19, 20), int2(20, 21),
    int2(22, 23), int2(23, 24)
};
constant int vc_animalEdgeCount = 24;

/// Distance to the nearest visible bone of a cat or dog.
inline float vc_animalSkeletonDistance(float2 p, constant GPUAnimal& animal, constant SceneUniforms& u) {
    float d = 1e9;
    for (int e = 0; e < vc_animalEdgeCount; e++) {
        int a = vc_animalEdges[e].x, b = vc_animalEdges[e].y;
        if (animal.visible[a] < 0.5 || animal.visible[b] < 0.5) continue;
        d = min(d, vc_sdSegment(p, vc_sceneToView(animal.joints[a], u), vc_sceneToView(animal.joints[b], u)));
    }
    return d;
}

/// Distance to the nearest visible joint of a cat or dog.
inline float vc_animalJointDistance(float2 p, constant GPUAnimal& animal, constant SceneUniforms& u) {
    float d = 1e9;
    for (int j = 0; j < VC_ANIMAL_JOINTS; j++) {
        if (animal.visible[j] < 0.5) continue;
        d = min(d, distance(p, vc_sceneToView(animal.joints[j], u)));
    }
    return d;
}

/// A hue for an animal that never collides with a person's.
inline float vc_animalHue(constant GPUAnimal& animal) { return 0.5 + animal.id * 0.19; }

/// The whole figure: body bones plus the head.
inline float vc_figureDistance(float2 p, constant GPUPerson& person, constant SceneUniforms& u, constant GPUFace* faces) {
    return min(vc_skeletonDistance(p, person, u), vc_headDistance(p, person, u, faces));
}

/// Distance to the nearest visible joint of a person.
inline float vc_jointDistance(float2 p, constant GPUPerson& person, constant SceneUniforms& u) {
    float d = 1e9;
    for (int j = 0; j < VC_BODY_JOINTS; j++) {
        if (person.visible[j] < 0.5) continue;
        d = min(d, distance(p, vc_sceneToView(person.joints[j], u)));
    }
    return d;
}

#endif
