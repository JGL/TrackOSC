//
//  Sprites.metal
//  TrackOSC (VisualCore)
//
//  The sprite and line layers drawn over a mode's background: instanced
//  quads (soft dots, rings or atlas glyphs) and line strips, both in the
//  scene's uv space, blended additively or normally by the pipeline.
//

#include "Common.h"

struct SpriteOut {
    float4 position [[position]];
    float2 local;        // -1 … 1 across the quad
    float2 uv;           // atlas coordinates
    float4 color;
    float kind;
    float softness;
};

vertex SpriteOut vc_sprite_vertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                  constant GPUSprite* sprites [[buffer(0)]],
                                  constant SceneUniforms& u [[buffer(1)]]) {
    constant GPUSprite& s = sprites[instanceID];
    float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, -1), float2(1, 1), float2(-1, 1) };
    float2 corner = corners[vertexID];
    float2 offset = vc_rotate(corner * s.size * 0.5, s.rotation);
    // Scene uv → screen uv → clip space (y up).
    float2 uv = vc_sceneToUV(s.position, u);
    float2 pixel = uv * u.resolution + offset;
    float2 ndc = pixel / u.resolution * 2.0 - 1.0;
    SpriteOut out;
    out.position = float4(ndc.x, -ndc.y, 0, 1);
    out.local = corner;
    float2 t = (corner + 1.0) * 0.5;
    out.uv = float2(mix(s.uv.x, s.uv.z, t.x), mix(s.uv.y, s.uv.w, t.y));
    out.color = s.color;
    out.kind = s.kind;
    out.softness = s.softness;
    return out;
}

fragment float4 vc_sprite_fragment(SpriteOut in [[stage_in]], texture2d<float> atlas [[texture(0)]]) {
    float alpha;
    if (in.kind > 1.5) {
        float r = length(in.local);
        alpha = smoothstep(0.55, 0.75, r) * smoothstep(1.0, 0.9, r);
    } else if (in.kind > 0.5) {
        alpha = atlas.sample(vc_sampler, in.uv).r;
    } else {
        float r = length(in.local);
        float edge = mix(0.85, 0.05, clamp(in.softness, 0.0, 1.0));
        alpha = 1.0 - smoothstep(edge, 1.0, r);
    }
    return float4(in.color.rgb * alpha * in.color.a, alpha * in.color.a);
}

struct LineOut {
    float4 position [[position]];
    float4 color;
};

vertex LineOut vc_line_vertex(uint vertexID [[vertex_id]], constant GPULineVertex* vertices [[buffer(0)]],
                              constant SceneUniforms& u [[buffer(1)]]) {
    float2 uv = vc_sceneToUV(vertices[vertexID].position, u);
    float2 ndc = uv * 2.0 - 1.0;
    LineOut out;
    out.position = float4(ndc.x, -ndc.y, 0, 1);
    out.color = vertices[vertexID].color;
    return out;
}

fragment float4 vc_line_fragment(LineOut in [[stage_in]]) {
    return float4(in.color.rgb * in.color.a, in.color.a);
}

// ---- A background for sprite modes: the previous frame faded (trails), or black.
fragment float4 vc_fade(MODE_ARGS) {
    float decay = u.params[15];   // the store puts the trail persistence here
    if (u.feedbackAvailable > 0.5 && decay > 0.0) {
        float3 c = previous.sample(vc_sampler, in.uv).rgb * decay;
        return float4(c, 1);
    }
    return float4(0, 0, 0, 1);
}
