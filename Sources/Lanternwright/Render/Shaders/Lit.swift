// Main opaque surface shader: the vertex stage and shared declarations. G10.1.4 split the rest by concern: TerrainMaterial.swift (the ground), ShadowLookup.swift
// (cascaded shadow lookup), LitFragment.swift (the fragment dispatcher). `LitShaders.source` is all of them in the original order: one pipeline, one library source.
enum LitShaders {
    static let source = head + "\n" + TerrainShaders.source + "\n" + ShadowLookupShaders.source + "\n" + LitFragmentShaders.source
    private static let head = #"""
// Depth-only pass from the sun's point of view.
vertex float4 shadow_vertex(uint vid [[vertex_id]],
                            device const Vertex* verts [[buffer(0)]],
                            constant FrameUniforms& frame [[buffer(1)]],
                            constant ObjectUniforms& obj [[buffer(2)]]) {
    float4 wp = obj.model * float4(verts[vid].position.xyz, 1.0);
    wp.xyz = tree_sway(wp.xyz, vertex_sway(verts[vid].position.w), frame.cameraPos.w);
    return frame.sunViewProj * wp;
}

// R09: true only in the pipeline variant that draws tree LOD objects (see ShaderLibrary.function(lodDither:)).
constant bool kLodDither [[function_constant(0)]];

struct LitOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float4 color;      // rgb albedo, a roughness
    float material;
    float stagger;     // per-tree LOD stagger (the vertex's position.w), see tree_lod_level
};

vertex LitOut lit_vertex(uint vid [[vertex_id]],
                         device const Vertex* verts [[buffer(0)]],
                         constant FrameUniforms& frame [[buffer(1)]],
                         constant ObjectUniforms& obj [[buffer(2)]]) {
    Vertex v = verts[vid];
    float3 localPos = v.position.xyz;
    if (v.normal.w > 3.5 && v.normal.w < 4.5) {
        // Birds: flap the wings. Vertices farther from the body (|x|) move more; obj.tint.w is the bird's own phase.
        float wing = abs(localPos.x);
        localPos.y += sin(frame.cameraPos.w * 9.0 + obj.tint.w) * wing * 0.32;
    }
    float4 wp = obj.model * float4(localPos, 1.0);
    wp.xyz = tree_sway(wp.xyz, vertex_sway(v.position.w), frame.cameraPos.w);
    LitOut o;
    o.position = frame.viewProj * wp;
    o.worldPos = wp.xyz;
    o.normal = (obj.model * float4(v.normal.xyz, 0.0)).xyz;   // uniform scale assumed
    o.color = float4(v.color.rgb * obj.tint.rgb, v.color.a);
    o.material = v.normal.w;
    o.stagger = vertex_stagger(v.position.w);      // tree vertices carry 3 + stagger (-1...1) + 4 * round(7 sway) in position.w; everything else has w = 1
    return o;
}
"""#
}
