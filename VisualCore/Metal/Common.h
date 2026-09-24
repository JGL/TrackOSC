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

// ---- Body edges (JointOrder.body17), for drawing skeletons in shaders.
constant int2 vc_bodyEdges[16] = {
    int2(0, 1), int2(0, 2), int2(1, 3), int2(2, 4),
    int2(5, 6), int2(5, 7), int2(7, 9), int2(6, 8), int2(8, 10),
    int2(5, 11), int2(6, 12), int2(11, 12),
    int2(11, 13), int2(13, 15), int2(12, 14), int2(14, 16)
};
constant int vc_bodyEdgeCount = 16;

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
