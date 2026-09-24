//
//  ColoursModes.metal
//  TrackOSC Colours
//
//  One fragment function per mode. Each reads the scene uniforms, the
//  people/hands/faces buffers and (for feedback modes) the previous frame,
//  and returns a colour for its pixel. Parameters arrive in u.params in
//  the order the mode's catalogue entry lists them.
//

#include "Common.h"

// ---- 1. Body Hue: glowing skeletons, one palette colour per person.
fragment float4 colours_body_hue(MODE_ARGS) {
    float thickness = u.params[0], glow = u.params[1], background = u.params[2];
    float2 p = vc_view(in.uv, u);
    float3 c = vc_palette(0.05 + u.time * 0.01, u) * background * 0.15;
    for (int i = 0; i < u.personCount; i++) {
        constant GPUPerson& person = persons[i];
        float d = vc_figureDistance(p, person, u, faces);
        float3 hue = vc_palette(person.id * 0.23 + u.time * 0.02, u);
        c += hue * (smoothstep(thickness, 0.0, d) + glow * vc_glow(d, 0.08 * glow)) * (0.4 + 0.6 * person.confidence);
    }
    // Hands and faces draw in their owner's colour, finer.
    for (int i = 0; i < u.handCount; i++) {
        float d = vc_handSkeletonDistance(p, hands[i], u);
        float3 hue = vc_palette(max(hands[i].person, 0.0) * 0.23 + u.time * 0.02, u);
        c += hue * (smoothstep(thickness * 0.6, 0.0, d) + glow * 0.6 * vc_glow(d, 0.04 * glow));
    }
    for (int i = 0; i < u.faceCount; i++) {
        if (faces[i].person >= 0.0) continue;   // drawn as that person's head
        float d = vc_faceOutlineDistance(p, faces[i], u);
        float3 hue = vc_palette(0.5 + u.time * 0.02, u);
        c += hue * (smoothstep(thickness * 0.6, 0.0, d) + glow * 0.6 * vc_glow(d, 0.04 * glow)) * (0.6 + faces[i].mouth);
    }
    return float4(c, 1);
}

// ---- 2. Hand Glow: light pours from every hand; open hands shine wider.
fragment float4 colours_hand_glow(MODE_ARGS) {
    float radius = u.params[0], intensity = u.params[1], fingers = u.params[2];
    float2 p = vc_view(in.uv, u);
    float3 c = float3(0.0);
    for (int i = 0; i < u.handCount; i++) {
        constant GPUHand& hand = hands[i];
        float r = radius * (0.5 + hand.openness);
        float d = distance(p, vc_sceneToView(hand.centre, u));
        float3 hue = vc_palette(hand.openness * 0.6 + hand.isLeft * 0.3, u);
        c += hue * intensity * vc_glow(d, r);
        for (int j = 0; j < VC_HAND_JOINTS; j++) {
            if (hand.visible[j] < 0.5) continue;
            c += hue * fingers * vc_glow(distance(p, vc_sceneToView(hand.joints[j], u)), 0.012);
        }
    }
    c += vc_palette(0.5, u) * 0.03 * u.presence;
    return float4(c, 1);
}

// ---- 3. Joint Stops: every joint is a colour stop of a smooth field.
fragment float4 colours_joint_stops(MODE_ARGS) {
    float falloff = u.params[0], spread = u.params[1], drift = u.params[2];
    float2 p = vc_view(in.uv, u);
    float3 sum = float3(0.0);
    float weight = 0.0;
    for (int i = 0; i < u.personCount; i++) {
        constant GPUPerson& person = persons[i];
        for (int j = 0; j < VC_BODY_JOINTS; j++) {
            if (person.visible[j] < 0.5) continue;
            float d = distance(p, vc_sceneToView(person.joints[j], u));
            float w = 1.0 / pow(d * falloff + 0.02, 2.0);
            sum += vc_palette(float(j) / VC_BODY_JOINTS * spread + person.id * 0.1 + u.time * drift * 0.05, u) * w;
            weight += w;
        }
    }
    for (int i = 0; i < u.handCount; i++) {
        for (int j = 0; j < VC_HAND_JOINTS; j += 4) {   // wrist and fingertips
            if (hands[i].visible[j] < 0.5) continue;
            float d = distance(p, vc_sceneToView(hands[i].joints[j], u));
            float w = 1.0 / pow(d * falloff * 1.5 + 0.02, 2.0);
            sum += vc_palette(0.5 + float(j) / VC_HAND_JOINTS * spread * 0.5 + hands[i].openness * 0.3 + u.time * drift * 0.05, u) * w;
            weight += w;
        }
    }
    for (int i = 0; i < u.faceCount; i++) {
        float d = distance(p, vc_sceneToView(faces[i].centre, u));
        float w = 1.0 / pow(d * falloff + 0.02, 2.0);
        sum += vc_palette(0.8 + faces[i].yaw / 180.0 + u.time * drift * 0.05, u) * w;
        weight += w;
    }
    float3 c = weight > 0.0 ? sum / weight : vc_palette(u.time * 0.02, u) * 0.2;
    return float4(c, 1);
}

// ---- 4. Voronoi People: the screen divided between whoever is nearest.
fragment float4 colours_voronoi(MODE_ARGS) {
    float edge = u.params[0], darken = u.params[1], pulse = u.params[2];
    float2 p = vc_view(in.uv, u);
    float best = 1e9, second = 1e9;
    float bestID = 0.0;
    for (int i = 0; i < u.personCount; i++) {
        constant GPUPerson& person = persons[i];
        for (int j = 0; j < VC_BODY_JOINTS; j++) {
            if (person.visible[j] < 0.5) continue;
            float d = distance(p, vc_sceneToView(person.joints[j], u));
            if (d < best) { second = best; best = d; bestID = person.id; }
            else if (d < second) { second = d; }
        }
    }
    for (int i = 0; i < u.handCount; i++) {
        for (int j = 0; j < VC_HAND_JOINTS; j += 4) {
            if (hands[i].visible[j] < 0.5) continue;
            float d = distance(p, vc_sceneToView(hands[i].joints[j], u));
            float id = 10.0 + float(i) + float(j) * 0.25;
            if (d < best) { second = best; best = d; bestID = id; }
            else if (d < second) { second = d; }
        }
    }
    for (int i = 0; i < u.faceCount; i++) {
        float d = distance(p, vc_sceneToView(faces[i].centre, u));
        if (d < best) { second = best; best = d; bestID = 20.0 + float(i); }
        else if (d < second) { second = d; }
    }
    if (best > 1e8) return float4(vc_palette(u.time * 0.03, u) * 0.15, 1);
    float3 c = vc_palette(bestID * 0.21 + sin(u.time * pulse) * 0.05, u);
    float line = smoothstep(edge, 0.0, second - best);
    c *= 1.0 - line * darken;
    c *= 0.6 + 0.4 * exp(-best * 2.0);
    return float4(c, 1);
}

// ---- 5. Metaballs: joints as blobs that merge into a coloured field.
fragment float4 colours_metaballs(MODE_ARGS) {
    float size = u.params[0], threshold = u.params[1], bands = u.params[2];
    float2 p = vc_view(in.uv, u);
    float field = 0.0;
    for (int i = 0; i < u.personCount; i++) {
        constant GPUPerson& person = persons[i];
        for (int j = 0; j < VC_BODY_JOINTS; j++) {
            if (person.visible[j] < 0.5) continue;
            float d = distance(p, vc_sceneToView(person.joints[j], u));
            field += (size * size) / (d * d + 1e-4);
        }
    }
    for (int i = 0; i < u.handCount; i++) {
        float d = distance(p, vc_sceneToView(hands[i].centre, u));
        field += (size * size) * 2.0 / (d * d + 1e-4);
    }
    for (int i = 0; i < u.faceCount; i++) {
        float d = distance(p, vc_sceneToView(faces[i].centre, u));
        field += (size * size) * (3.0 + faces[i].mouth * 3.0) / (d * d + 1e-4);
    }
    float f = field / max(threshold, 0.01);
    float3 c = vc_palette(fract(log2(f + 1.0) * bands * 0.1 + u.time * 0.02), u);
    c *= smoothstep(0.6, 1.2, f);
    return float4(c, 1);
}

// ---- 6. Rings: ripples radiating from each person, faster when they move.
fragment float4 colours_rings(MODE_ARGS) {
    float spacing = u.params[0], speed = u.params[1], width = u.params[2];
    float2 p = vc_view(in.uv, u);
    float3 c = float3(0.0);
    for (int i = 0; i < u.personCount; i++) {
        constant GPUPerson& person = persons[i];
        float d = distance(p, vc_sceneToView(person.centroid, u));
        float phase = d / spacing - u.time * speed * (0.5 + person.speed * 2.0 + u.activity);
        float ring = smoothstep(1.0 - width, 1.0, 0.5 + 0.5 * cos(phase * 6.28318));
        c += vc_palette(person.id * 0.2 + d * 0.5, u) * ring * exp(-d * 1.2);
    }
    for (int i = 0; i < u.handCount; i++) {
        float d = distance(p, vc_sceneToView(hands[i].centre, u));
        float phase = d / (spacing * 0.5) - u.time * speed * (1.0 + hands[i].openness);
        float ring = smoothstep(1.0 - width, 1.0, 0.5 + 0.5 * cos(phase * 6.28318));
        c += vc_palette(0.5 + float(i) * 0.15, u) * ring * exp(-d * 4.0) * 0.8;
    }
    for (int i = 0; i < u.faceCount; i++) {
        float d = distance(p, vc_sceneToView(faces[i].centre, u));
        float phase = d / (spacing * 0.7) - u.time * speed * (0.5 + faces[i].mouth * 2.0);
        float ring = smoothstep(1.0 - width, 1.0, 0.5 + 0.5 * cos(phase * 6.28318));
        c += vc_palette(0.8 + float(i) * 0.1, u) * ring * exp(-d * 3.0) * 0.8;
    }
    if (u.personCount == 0 && u.handCount == 0 && u.faceCount == 0) {
        float d = distance(p, vc_view(float2(0.5, 0.5), u));
        c = vc_palette(d, u) * 0.15 * (0.5 + 0.5 * cos(d / spacing * 6.28318 - u.time * speed));
    }
    return float4(c, 1);
}

// ---- 7. Stripes: bands that turn with the shoulders and breathe with presence.
fragment float4 colours_stripes(MODE_ARGS) {
    float count = u.params[0], softness = u.params[1], turn = u.params[2];
    float2 p = vc_view(in.uv, u) - vc_view(float2(0.5, 0.5), u);
    float angle = u.time * 0.05;
    float widen = 0.0;
    if (u.personCount > 0) {
        constant GPUPerson& person = persons[0];
        if (person.visible[5] > 0.5 && person.visible[6] > 0.5) {
            float2 s = vc_sceneToView(person.joints[6], u) - vc_sceneToView(person.joints[5], u);
            angle = atan2(s.y, s.x) * turn;
        }
    } else if (u.faceCount > 0) {
        angle = faces[0].roll * 0.01745 * turn;
    }
    if (u.faceCount > 0) widen = faces[0].mouth;
    for (int i = 0; i < u.handCount; i++) widen += hands[i].openness * 0.3;
    float2 q = vc_rotate(p, angle);
    float bands = count * (0.6 + 0.4 * u.presence) / (1.0 + widen);
    float t = q.x * bands + u.time * 0.1;
    float band = fract(t);
    float3 c = vc_palette(floor(t) / bands + 0.1, u);
    c *= mix(0.55, 1.0, smoothstep(0.0, softness, band) * smoothstep(1.0, 1.0 - softness, band));
    return float4(c, 1);
}

// ---- 8. Checkers: a chequerboard warped by whoever stands in it.
fragment float4 colours_checkers(MODE_ARGS) {
    float cells = u.params[0], warp = u.params[1], radius = u.params[2];
    float2 p = vc_view(in.uv, u);
    float2 q = p;
    for (int i = 0; i < u.personCount; i++) {
        constant GPUPerson& person = persons[i];
        for (int j = 0; j < VC_BODY_JOINTS; j++) {
            if (person.visible[j] < 0.5) continue;
            float2 jp = vc_sceneToView(person.joints[j], u);
            float2 dir = p - jp;
            float d = length(dir);
            q += normalize(dir + 1e-5) * warp * 0.05 * exp(-d / radius);
        }
    }
    for (int i = 0; i < u.handCount; i++) {
        for (int j = 0; j < VC_HAND_JOINTS; j += 2) {
            if (hands[i].visible[j] < 0.5) continue;
            float2 dir = p - vc_sceneToView(hands[i].joints[j], u);
            float d = length(dir);
            q += normalize(dir + 1e-5) * warp * 0.03 * exp(-d / (radius * 0.5));
        }
    }
    for (int i = 0; i < u.faceCount; i++) {
        float2 dir = p - vc_sceneToView(faces[i].centre, u);
        float d = length(dir);
        // A face twists the board rather than pushing it.
        q += vc_rotate(dir, faces[i].yaw * 0.01745 * warp) * exp(-d / radius) - dir * exp(-d / radius);
    }
    float2 cell = floor(q * cells);
    float check = fmod(cell.x + cell.y, 2.0);
    float3 a = vc_palette(0.15 + u.time * 0.01, u), b = vc_palette(0.65 + u.time * 0.01, u);
    return float4(check < 1.0 ? a : b, 1);
}

// ---- 9. Memory Wash (feedback): the skeleton paints, and the paint fades.
fragment float4 colours_memory_wash(MODE_ARGS) {
    float decay = u.params[0], brush = u.params[1], hueSpeed = u.params[2];
    float2 p = vc_view(in.uv, u);
    float3 c = u.feedbackAvailable > 0.5 ? previous.sample(vc_sampler, in.uv).rgb * decay : float3(0.0);
    for (int i = 0; i < u.personCount; i++) {
        constant GPUPerson& person = persons[i];
        float d = vc_figureDistance(p, person, u, faces);
        c += vc_palette(u.time * hueSpeed * 0.1 + person.id * 0.3, u) * smoothstep(brush, 0.0, d) * 0.3;
    }
    for (int i = 0; i < u.handCount; i++) {
        float d = vc_handSkeletonDistance(p, hands[i], u);
        c += vc_palette(u.time * hueSpeed * 0.1 + 0.5, u) * smoothstep(brush * 0.7, 0.0, d) * 0.3;
    }
    for (int i = 0; i < u.faceCount; i++) {
        if (faces[i].person >= 0.0) continue;
        float d = vc_faceOutlineDistance(p, faces[i], u);
        c += vc_palette(u.time * hueSpeed * 0.1 + 0.8, u) * smoothstep(brush * 0.7, 0.0, d) * 0.3;
    }
    return float4(min(c, 1.5), 1);
}

// ---- 10. Heat Map (feedback): where people have been, slowly cooling.
fragment float4 colours_heat_map(MODE_ARGS) {
    float cooling = u.params[0], warmth = u.params[1], spot = u.params[2];
    float2 p = vc_view(in.uv, u);
    float heat = u.feedbackAvailable > 0.5 ? previous.sample(vc_sampler, in.uv).a : 0.0;
    heat *= cooling;
    for (int i = 0; i < u.personCount; i++) {
        float d = vc_jointDistance(p, persons[i], u);
        heat += warmth * 0.02 * vc_glow(d, spot);
    }
    for (int i = 0; i < u.handCount; i++) {
        float d = vc_handSkeletonDistance(p, hands[i], u);
        heat += warmth * 0.02 * vc_glow(d, spot * 0.5);
    }
    for (int i = 0; i < u.faceCount; i++) {
        float d = distance(p, vc_sceneToView(faces[i].centre, u));
        heat += warmth * 0.03 * vc_glow(d, spot * 1.5);
    }
    heat = min(heat, 1.0);
    float3 c = vc_palette(heat * 0.9, u) * smoothstep(0.0, 0.15, heat);
    return float4(c, heat);
}

// ---- 11. Kaleido Body: the body-hue field folded into a kaleidoscope.
fragment float4 colours_kaleido(MODE_ARGS) {
    float segments = u.params[0], spin = u.params[1], zoom = u.params[2];
    float2 centre = vc_view(float2(0.5, 0.5), u);
    float2 p = vc_view(in.uv, u) - centre;
    float a = atan2(p.y, p.x) + u.time * spin * 0.1;
    float r = length(p) * zoom;
    float seg = 6.28318 / max(segments, 1.0);
    a = abs(fmod(a + seg * 100.0, seg) - seg * 0.5);
    float2 q = centre + float2(cos(a), sin(a)) * r;
    float3 c = float3(0.0);
    for (int i = 0; i < u.personCount; i++) {
        constant GPUPerson& person = persons[i];
        float d = vc_figureDistance(q, person, u, faces);
        c += vc_palette(person.id * 0.23 + r * 0.3 + u.time * 0.03, u) * (smoothstep(0.01, 0.0, d) + vc_glow(d, 0.06));
    }
    float extras = vc_extrasDistance(q, u, hands, faces);
    c += vc_palette(0.6 + r * 0.3 + u.time * 0.03, u) * (smoothstep(0.006, 0.0, extras) + vc_glow(extras, 0.03));
    c += vc_palette(r * 0.5 + u.time * 0.02, u) * 0.08;
    return float4(c, 1);
}

// ---- 12. Aurora: noise curtains that brighten where hands rise.
fragment float4 colours_aurora(MODE_ARGS) {
    float scale = u.params[0], speed = u.params[1], lift = u.params[2];
    float2 p = vc_view(in.uv, u);
    float2 q = float2(p.x * scale, p.y * scale * 0.5 + u.time * speed * 0.1);
    float n = vc_fbm(q + vc_fbm(q * 0.5 + u.time * 0.02));
    float height = 1.0 - in.uv.y;
    float raise = 0.0;
    for (int i = 0; i < u.handCount; i++) {
        float2 h = vc_sceneToUV(hands[i].centre, u);
        raise += lift * (1.0 - h.y) * exp(-abs(in.uv.x - h.x) * 6.0);
    }
    float mouth = 0.0;
    for (int i = 0; i < u.faceCount; i++) mouth = max(mouth, faces[i].mouth);
    float curtain = smoothstep(0.35, 0.9, n + height * 0.4 + raise + u.presence * 0.1 + mouth * 0.15);
    float3 c = vc_palette(n * 0.7 + height * 0.2 + u.time * 0.01, u) * curtain;
    c += vc_palette(0.1, u) * 0.03;
    return float4(c, 1);
}

// ---- 13. Face Mood: colour follows where the face looks and how open the mouth is.
fragment float4 colours_face_mood(MODE_ARGS) {
    float reach = u.params[0], swing = u.params[1], brighten = u.params[2];
    float2 p = vc_view(in.uv, u);
    if (u.faceCount == 0) {
        float3 idle = vc_palette(u.time * 0.02 + in.uv.y * 0.3, u) * 0.25;
        return float4(idle, 1);
    }
    float3 c = float3(0.0);
    for (int i = 0; i < u.faceCount; i++) {
        constant GPUFace& face = faces[i];
        float2 fc = vc_sceneToView(face.centre, u);
        float2 look = float2(sin(face.yaw * 0.01745), -sin(face.pitch * 0.01745)) * swing;
        float d = distance(p, fc + look * 0.3);
        float hue = 0.5 + face.yaw / 90.0 * 0.4 + face.mouth * 0.2;
        c += vc_palette(hue, u) * (0.3 + face.mouth * brighten) * vc_glow(d, reach * (0.5 + face.size.y * 4.0));
    }
    return float4(c, 1);
}

// ---- 14. Palette Sweep: the palette sweeps across, its phase led by the nose.
fragment float4 colours_palette_sweep(MODE_ARGS) {
    float repeats = u.params[0], speed = u.params[1], follow = u.params[2];
    float phase = u.time * speed * 0.1;
    float tilt = 0.0;
    if (u.personCount > 0 && persons[0].visible[0] > 0.5) {
        float2 nose = vc_sceneToUV(persons[0].joints[0], u);
        phase += nose.x * follow;
        tilt = (nose.y - 0.5) * follow * 0.5;
    } else if (u.faceCount > 0) {
        float2 fc = vc_sceneToUV(faces[0].centre, u);
        phase += fc.x * follow;
        tilt = (fc.y - 0.5) * follow * 0.5;
    }
    for (int i = 0; i < u.handCount; i++) {
        float2 h = vc_sceneToUV(hands[i].centre, u);
        phase += (h.y - 0.5) * follow * 0.3 * hands[i].openness;
    }
    float t = (in.uv.x + in.uv.y * tilt) * repeats + phase;
    float3 c = vc_palette(t, u);
    c *= 0.7 + 0.3 * u.presence;
    return float4(c, 1);
}
