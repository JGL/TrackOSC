//
//  Present.metal
//  TrackOSC (VisualCore)
//
//  The full-screen triangle every mode draws with, and the post pass that
//  puts the offscreen frame on screen with vignette, grain and gamma.
//

#include "Common.h"

vertex VertexOut vc_fullscreen_vertex(uint id [[vertex_id]]) {
    // One triangle covering the clip space; uv has y down like the scene.
    float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VertexOut out;
    out.position = float4(positions[id], 0, 1);
    out.uv = float2((positions[id].x + 1) * 0.5, 1 - (positions[id].y + 1) * 0.5);
    return out;
}

fragment float4 vc_present(VertexOut in [[stage_in]],
                           constant SceneUniforms& u [[buffer(0)]],
                           texture2d<float> frame [[texture(0)]]) {
    float3 c = frame.sample(vc_sampler, in.uv).rgb;
    float2 q = in.uv - 0.5;
    float v = 1.0 - u.vignette * smoothstep(0.2, 0.9, dot(q, q) * 2.2);
    float g = (vc_hash(in.uv * u.resolution + u.seed * 1000.0) - 0.5) * u.grain;
    c = max(c * v + g, 0.0);
    c = pow(c, float3(1.0 / max(u.gamma, 0.1)));
    return float4(c, 1);
}
