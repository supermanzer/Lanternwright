// The lit lighthouse's beams (F01 W4.3): real geometry that STARTS AT THE LENS. Two opposite beams sweep round it. Each is a tapered ribbon that turns to face the
// camera about its own axis (a cylindrical billboard): it is narrow and hot at the lens, widens like a cone (about 2.6 degrees half-angle) and thins with
// distance, is brightest when you look along it, shimmers faintly along its length, and is added to the scene as light (additive blending). A glow with a
// small starburst sits at the lens itself so the eye can trace the beam back to the lantern room. (The old beam only existed as patches of the two
// horizontal mist sheets, starting 60 m from the lens, so it floated over the sea attached to nothing.)
enum BeamShaders {
    static let source = #"""
struct BeamOut {
    float4 position [[position]];
    float3 worldPos;
    float2 uv;          // x: along 0..1 (ribbon) or -1..1 (glow), y: across -1..1
    float dist;
    float mode;
};

constant float PORTAL_HALF_WIDTH = 1.7, PORTAL_HEIGHT = 3.4;          // the halo quad: the doorway's own size is in the fragment (`LensPortalProps`)

// obj.emissive.xyz = lens position, obj.emissive.w = mode (0 beam, 1 glow); obj.tint.x = direction sign (+1 / -1), tint.y = heading, tint.z = intensity.
vertex BeamOut beam_vertex(uint vid [[vertex_id]],
                           device const Vertex* verts [[buffer(0)]],
                           constant FrameUniforms& frame [[buffer(1)]],
                           constant ObjectUniforms& obj [[buffer(2)]]) {
    float s = verts[vid].position.x, side = verts[vid].position.y;
    float3 lens = obj.emissive.xyz;
    BeamOut o;
    if (obj.emissive.w > 0.5 && obj.emissive.w < 1.5) {                                          // the glow at the lens: a camera-facing square
        float3 toCam = normalize(frame.cameraPos.xyz - lens);
        float3 right = normalize(cross(float3(0.0, 1.0, 0.0), toCam));
        float3 up = cross(toCam, right);
        float size = 11.0;
        float3 p = lens + (right * side + up * (2.0 * s - 1.0)) * size;
        o.worldPos = p; o.position = frame.viewProj * float4(p, 1.0);
        o.uv = float2(side, 2.0 * s - 1.0); o.dist = 0.0; o.mode = 1.0;
        return o;
    }
    if (obj.emissive.w > 2.5) {                                          // S03.7 the lens portal's halo: a quad standing just in front of the doorway: origin = model column 3 (the floor under its centre), right = column 0, up = column 1
        float3 p3 = obj.model.columns[3].xyz + obj.model.columns[0].xyz * side + obj.model.columns[1].xyz * s;
        o.worldPos = p3; o.position = frame.viewProj * float4(p3, 1.0);
        o.uv = float2(side, s); o.dist = 0.0; o.mode = 3.0;
        return o;
    }
    if (obj.emissive.w > 1.5) {                                          // S03.5b: a window's light shaft inside the tower: origin = model column 3, direction = column 2, width = column 0 x, length = column 1 x
        float3 origin = obj.model.columns[3].xyz, dir = obj.model.columns[2].xyz;
        float3 center = origin + dir * (obj.model.columns[1].x * s);
        float3 toCam2 = frame.cameraPos.xyz - center;
        float3 perp2 = normalize(cross(dir, toCam2) + float3(1e-5));
        float3 p2 = center + perp2 * side * obj.model.columns[0].x * (0.6 + 0.8 * s);          // the shaft spreads a little as it goes
        o.worldPos = p2; o.position = frame.viewProj * float4(p2, 1.0);
        o.uv = float2(s, side); o.dist = 0.0; o.mode = 2.0;
        return o;
    }
    float h = obj.tint.y;
    float3 d = float3(sin(h), 0.0, -cos(h)) * obj.tint.x;
    float dist = pow(s, 2.3) * 2800.0;
    float3 center = lens + d * dist;
    float3 toCam = frame.cameraPos.xyz - center;
    float3 perp = normalize(cross(d, toCam) + float3(1e-5));
    float w = 0.35 + 0.046 * dist;
    float3 p = center + perp * side * w;
    o.worldPos = p; o.position = frame.viewProj * float4(p, 1.0);
    o.uv = float2(s, side); o.dist = dist; o.mode = 0.0;
    return o;
}

fragment float4 beam_fragment(BeamOut in [[stage_in]],
                              constant FrameUniforms& frame [[buffer(1)]],
                              constant ObjectUniforms& obj [[buffer(2)]],
                              texture2d<float> distTex [[texture(3)]]) {
    float on = obj.tint.z;
    if (on < 0.001) discard_fragment();
    float t = frame.cameraPos.w;
    // Never draw where the scene is nearer than the beam (terrain and the tower hide it).
    uint2 size = uint2(distTex.get_width(), distTex.get_height());
    float sceneD = distTex.read(min(uint2(in.position.xy), size - 1)).r;
    float myD = length(in.worldPos - frame.cameraPos.xyz);
    float hide = smoothstep(-3.0, 6.0, sceneD - myD);
    if (in.mode > 0.5 && in.mode < 1.5) {
        float r = length(in.uv);
        float core = exp(-r * r * 22.0), halo = exp(-r * r * 3.2) * 0.45;
        float star = exp(-abs(in.uv.x) * 9.0) * exp(-in.uv.y * in.uv.y * 90.0) * 0.8 + exp(-abs(in.uv.y) * 9.0) * exp(-in.uv.x * in.uv.x * 90.0) * 0.5;      // a faint cross of rays
        float3 c = float3(3.4, 2.6, 1.3) * (core * 2.2 + halo + star * 0.6) * on * (0.92 + 0.08 * sin(t * 3.1));
        return float4(c * smoothstep(1.0, 0.7, r) * hide, 1.0);
    }
    if (in.mode > 2.5) {                                                 // the portal's halo: light turned into a doorway. Outside the arch (a 1.1 m wide, 2.1 m tall door with a round head) the light falls off, streaked upward and drifting; a warm rim hugs the edge.
        float px = in.uv.x * PORTAL_HALF_WIDTH, py = in.uv.y * PORTAL_HEIGHT;
        float dist = py > 1.55 ? length(float2(px, py - 1.55)) - 0.55 : max(abs(px) - 0.55, -py);
        if (dist < 0.0) {                                                // inside the doorway: light drifting up through it in soft rays, deeper blue toward the middle, bright and warm at the edge
            float depth = saturate(-dist / 0.55);
            float rays = 0.5 + 0.5 * sin(px * 13.0 + sin(py * 2.6 - t * 1.1) * 1.9 + t * 0.35);
            float3 core = mix(float3(0.80, 0.92, 1.0), float3(0.36, 0.58, 1.0), depth) * (0.55 + 0.9 * rays) + float3(1.0, 0.8, 0.5) * exp(-depth * 9.0) * 1.1;
            return float4(core * obj.tint.z * 1.15 * smoothstep(-0.02, 0.04, sceneD - myD), 1.0);
        }
        float streak = 0.72 + 0.28 * sin(py * 6.5 - t * 1.7 + px * 4.0) * sin(px * 9.0 + t * 0.6);
        float halo = exp(-dist * 3.4) * 0.9 * streak;
        float rim = exp(-dist * 16.0) * 1.6;
        float3 c = (float3(0.62, 0.80, 1.0) * halo + float3(1.0, 0.82, 0.52) * rim) * obj.tint.z * (0.94 + 0.06 * sin(t * 2.3));
        return float4(c * smoothstep(-0.02, 0.04, sceneD - myD), 1.0);
    }
    if (in.mode > 1.5) {                                                 // the window shaft: warm sun, brightest at the window, fading along its length and across; no shadow (light casts none)
        float along2 = smoothstep(0.0, 0.06, in.uv.x) * (1.0 - in.uv.x) * (1.0 - in.uv.x);
        float across2 = exp(-in.uv.y * in.uv.y * 2.4);
        return float4(obj.emissive.xyz * along2 * across2 * smoothstep(0.0, 0.8, sceneD - myD), 1.0);
    }
    float3 lens = obj.emissive.xyz;
    float3 d = float3(sin(obj.tint.y), 0.0, -cos(obj.tint.y)) * obj.tint.x;
    float across = exp(-in.uv.y * in.uv.y * 2.6);
    float dist = in.dist;
    float along = smoothstep(0.0, 14.0, dist) / (1.0 + dist / 380.0) * exp(-dist / 3200.0);
    float aim = abs(dot(normalize(frame.cameraPos.xyz - lens + float3(1e-4)), d));        // 1 when you look straight down the beam
    float boost = 1.0 + 6.0 * pow(aim, 10.0);
    float shimmer = 0.85 + 0.30 * vnoiseV(float3(dist * 0.02 - t * 1.2, in.uv.y * 2.0, 3.0));
    float3 c = float3(3.2, 2.5, 1.3) * across * along * boost * shimmer * on * 1.1;
    return float4(c * hide, 1.0);
}
"""#
}
