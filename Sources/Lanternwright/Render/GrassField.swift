import Metal
import simd
import Foundation

/// G10.G.1: which grass cells are worth a vertex invocation this frame.
///
/// The grass used to draw one instance per cell of a 272 x 272 grid (74,000) and let the vertex shader find out, seven times per instance, that most of them grow
/// nothing (no density, thinned away by distance) or lie outside the view. A compute pass now asks that question once per cell, and the draw is an indirect one over
/// only the cells that might be seen.
///
/// G10.G.2: distance no longer thins the field blade by blade. The pass and the vertex shader share `grass_chunk_fade` (Shaders/Grass.swift): one factor per 8 x 8 cell chunk from the
/// distance of the chunk's centre, which scales the blades' height to nothing at the draw radius, so a cell is kept or dropped by density alone and never by how far the eye is.
///
/// The pass only ever REJECTS, and only when it is sure: every threshold carries a margin, and the frustum test keeps anything within `frustumMargin` metres of the
/// view (a blade is up to about 5 m tall and leans up to about 7 m in a gust). The vertex shader still runs its own tests on every cell it is given and is the final
/// arbiter, so a culled cell is always one the old path would have drawn nothing for, and the frame is byte-identical (checked by `scripts/grass-frames.sh`,
/// `scripts/frame-hashes.sh` and the grass selftest, which renders both ways and compares the bytes).
///
/// The surviving cell numbers are written in the old instance order (row by row, left to right): equal-depth ties between blades then resolve as they always did, and the
/// frame is reproducible. A count per row, then each row's offset (the sum of the rows before it), then a copy: no atomics, so nothing depends on thread timing.
final class GrassField {
    /// Threads per row: the 272 cells of a row padded to nine whole simdgroups.
    static let rowThreads = 288
    /// A cell is kept if its root is no further than this outside any frustum plane.
    static let frustumMargin: Float = 10

    /// `false` draws every cell, as the grass did before G10.G.1 (the selftest compares the two).
    nonisolated(unsafe) static var cullEnabled = ProcessInfo.processInfo.environment["LW_GRASS_CULL"] != "0"      // LW_GRASS_CULL=0 in the environment: the old path, for tools
    /// Debug (`LW_GRASS_VERTEX_ONLY=1`): the grass runs its cull and vertex stages but rasterises nothing, so `--bench` measures their cost without the fragment shader's.
    static let vertexOnly = ProcessInfo.processInfo.environment["LW_GRASS_VERTEX_ONLY"] == "1"

    let cellsPerSide: Int
    private let cull: MTLComputePipelineState
    private let gather: MTLComputePipelineState
    private let staging: MTLBuffer          // per row: the cell numbers that survived, packed to the left
    private let rowCounts: MTLBuffer        // survivors per row
    let cells: MTLBuffer                    // all survivors, in instance order
    let gridBase: MTLBuffer                 // the world cell of the grid's corner, written by the cull so the vertex shader cannot disagree with it
    let arguments: MTLBuffer                // MTLDrawPrimitivesIndirectArguments
    private(set) var vertexOnlyPipeline: MTLRenderPipelineState?

    init(device: MTLDevice, library: MTLLibrary, cellsPerSide n: Int) {
        cellsPerSide = n
        precondition(n <= GrassField.rowThreads, "a grid row must fit one threadgroup")
        func pipeline(_ name: String) -> MTLComputePipelineState {
            let d = MTLComputePipelineDescriptor()
            d.computeFunction = ShaderLibrary.function(library, name)
            d.label = name
            d.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
            return try! device.makeComputePipelineState(descriptor: d, options: [], reflection: nil)
        }
        cull = pipeline("grass_cull")
        gather = pipeline("grass_gather")
        func buffer(_ bytes: Int, _ label: String) -> MTLBuffer {
            let b = device.makeBuffer(length: bytes, options: .storageModePrivate)!
            b.label = label
            return b
        }
        staging = buffer(n * n * 4, "grass staging")
        rowCounts = buffer(n * 4, "grass row counts")
        cells = buffer(n * n * 4, "grass cells")
        gridBase = buffer(8, "grass grid base")
        arguments = buffer(16, "grass draw arguments")
        if GrassField.vertexOnly {
            let d = MTLRenderPipelineDescriptor()
            d.label = "grass (vertex only)"
            d.vertexFunction = ShaderLibrary.function(library, "grass_vertex")
            d.isRasterizationEnabled = false
            d.colorAttachments[0].pixelFormat = Renderer.hdrFormat
            d.colorAttachments[1].pixelFormat = Renderer.distanceFormat
            d.depthAttachmentPixelFormat = Renderer.depthFormat
            vertexOnlyPipeline = try? device.makeRenderPipelineState(descriptor: d)
        }
    }

    /// How many cells the last culling pass kept (reads the draw arguments back; waits for the GPU, so tools and tests only).
    func survivorCount(queue: MTLCommandQueue) -> Int {
        guard let readback = arguments.device.makeBuffer(length: 16, options: .storageModeShared), let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else { return -1 }
        blit.copy(from: arguments, sourceOffset: 0, to: readback, destinationOffset: 0, size: 16)
        blit.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        return Int(readback.contents().bindMemory(to: UInt32.self, capacity: 4)[1])
    }

    /// Fill `cells`, `gridBase` and `arguments` for this frame. `params` are the same two vectors the vertex shader gets (buffer 3).
    func encodeCull(_ commandBuffer: MTLCommandBuffer, frame: inout FrameUniforms, params: inout [SIMD4<Float>], terrain: MTLTexture) {
        guard let enc = commandBuffer.makeComputeCommandEncoder() else { return }
        enc.label = "grass cull"
        enc.setBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.setBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride * params.count, index: 3)
        enc.setTexture(terrain, index: 5)
        let group = MTLSize(width: GrassField.rowThreads, height: 1, depth: 1)
        let grid = MTLSize(width: cellsPerSide, height: 1, depth: 1)           // one threadgroup per row of the grid
        enc.setComputePipelineState(cull)
        enc.setBuffer(staging, offset: 0, index: 4)
        enc.setBuffer(rowCounts, offset: 0, index: 5)
        enc.setBuffer(gridBase, offset: 0, index: 6)
        enc.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
        enc.memoryBarrier(scope: .buffers)
        enc.setComputePipelineState(gather)
        enc.setBuffer(cells, offset: 0, index: 7)
        enc.setBuffer(arguments, offset: 0, index: 8)
        enc.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
        enc.endEncoding()
    }
}

enum GrassCullShaders {
    /// Registered after `GrassShaders` (it uses `GrassParams`, `hash22` and `terrain_sample` from there). The density terms below are a COPY of the first half of
    /// `grass_vertex` (no shared function: moving that code into a function changed the Glass Wood frame by a few bits under fast-math, and the field has to stay
    /// byte-identical). If the grass rules change, change both; the grass selftest renders culled and unculled and fails if a single byte differs.
    static let source = #"""
constant uint kGrassRowThreads = 288;
constant uint kGrassSimdGroups = 9;

kernel void grass_cull(uint row [[threadgroup_position_in_grid]], uint ix [[thread_position_in_threadgroup]],
                       uint sid [[simdgroup_index_in_threadgroup]], uint lane [[thread_index_in_simdgroup]],
                       constant FrameUniforms& frame [[buffer(1)]], constant GrassParams& gp [[buffer(3)]],
                       texture2d<float> terrainTex [[texture(5)]],
                       device uint* staging [[buffer(4)]], device uint* rowCounts [[buffer(5)]], device int2* baseOut [[buffer(6)]]) {
    threadgroup uint simdTotals[kGrassSimdGroups];
    float cell = gp.field.x;
    int n = int(gp.field.y);
    float radius = gp.field.z;
    int2 base = int2(floor(frame.cameraPos.xz / cell)) - int2(n / 2);
    if (row == 0 && ix == 0) baseOut[0] = base;

    bool keepCell = false;
    if (int(ix) < n) {
        int2 gcell = base + int2(int(ix), int(row));
        float2 rnd = hash22(float2(gcell));
        float2 xz = (float2(gcell) + rnd) * cell;
        float fade = grass_chunk_fade(gcell, frame.cameraPos.xz, cell, radius);   // G10.G.2: the same chunk factor as the vertex shader; it drops a whole chunk at fade < 0.002
        float h = hash22(float2(gcell) + 17.0).x;
        // Cheapest tests first, each only rejecting with a margin (the vertex shader rejects at density < 0.22 and at hash > keep, and every factor after the first
        // few is at most 1, so the partial products below are upper bounds of the density it will compute).
        if (fade >= 0.002 - 0.0005) {
            float4 ts = terrain_sample(terrainTex, xz);
            float y = ts.x;
            // Within reach of the view? The planes of the view-projection, each taken from its rows; a root further than `margin` outside one is out. The margin
            // covers the blade itself (up to about 5.3 m tall, leaning up to about 7 m).
            float3 p = float3(xz.x, y, xz.y);
            float4x4 m = frame.viewProj;
            float4 r0 = float4(m[0][0], m[1][0], m[2][0], m[3][0]), r1 = float4(m[0][1], m[1][1], m[2][1], m[3][1]);
            float4 r2 = float4(m[0][2], m[1][2], m[2][2], m[3][2]), r3 = float4(m[0][3], m[1][3], m[2][3], m[3][3]);
            float4 planes[5] = { r3 + r0, r3 - r0, r3 + r1, r3 - r1, r2 };          // left, right, bottom, top, near (the far plane is beyond the field)
            bool inside = true;
            for (int k = 0; k < 5; k++) {
                float4 pl = planes[k];
                float d = (dot(pl.xyz, p) + pl.w) / max(length(pl.xyz), 1e-6);
                if (d < -\#(GrassField.frustumMargin)) inside = false;
            }
            // Sand, the path, a landmark pad and the bare summit: no density whatever the noise says.
            float grows = smoothstep(2.2, 4.0, y) * (1.0 - smoothstep(0.35, 0.9, ts.y)) * (1.0 - ts.z) * (1.0 - smoothstep(52.0, 64.0, y));
            if (inside && grows >= 0.22 - 0.002) {
                float hx = terrain_sample(terrainTex, xz + float2(2.0, 0.0)).x - terrain_sample(terrainTex, xz - float2(2.0, 0.0)).x;
                float hz = terrain_sample(terrainTex, xz + float2(0.0, 2.0)).x - terrain_sample(terrainTex, xz - float2(0.0, 2.0)).x;
                float ny = 1.0 / sqrt(1.0 + (hx * hx + hz * hz) / 16.0);
                float density = smoothstep(2.2, 4.0, y) * (1.0 - smoothstep(0.35, 0.9, ts.y)) * (1.0 - ts.z) * smoothstep(0.80, 0.90, ny) * (1.0 - smoothstep(52.0, 64.0, y));
                if (density >= 0.22 - 0.002) {
                    float3 cp = float3(xz.x, 3.0, xz.y) * 0.09;
                    float clump = 0.55 * vnoiseV(cp) + 0.30 * vnoiseV(cp * 2.1 + 5.0) + 0.12 * vnoiseV(cp * 4.3 + 9.0);
                    float tuft = vnoiseV(float3(xz.x, 9.0, xz.y) * 0.55);
                    bool glassW = frame.worldB.x > 0.5;
                    float gb8 = vnoiseV(float3(xz.x, 1.0, xz.y) * 0.125 + 4.1), gb30 = vnoiseV(float3(xz.x, 1.0, xz.y) * 0.033 + 9.3);
                    density *= mix(0.55, 1.0, smoothstep(0.25, 0.5, gb30)) * mix(0.7, 1.0, smoothstep(0.2, 0.45, gb8));
                    density *= mix(glassW ? 0.04 : 0.45, 1.0, glassW ? smoothstep(0.36, 0.56, clump) : smoothstep(0.28, 0.50, clump)) * (0.78 + 0.22 * tuft) * (1.0 - 0.9 * ts.w);
                    keepCell = density >= 0.22 - 0.002 && h <= density + 0.002;
                }
            }
        }
    }

    // Row-order compaction without atomics: a prefix sum inside each simdgroup, then over the group totals.
    uint flag = keepCell ? 1u : 0u;
    uint before = simd_prefix_exclusive_sum(flag);
    uint total = simd_sum(flag);
    if (lane == 0) simdTotals[sid] = total;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    uint offset = 0;
    for (uint k = 0; k < sid; k++) offset += simdTotals[k];
    if (keepCell) staging[row * uint(n) + offset + before] = row * uint(n) + ix;
    if (ix == 0) {
        uint all = 0;
        for (uint k = 0; k < kGrassSimdGroups; k++) all += simdTotals[k];
        rowCounts[row] = all;
    }
}

kernel void grass_gather(uint row [[threadgroup_position_in_grid]], uint tid [[thread_position_in_threadgroup]],
                         uint sid [[simdgroup_index_in_threadgroup]], uint lane [[thread_index_in_simdgroup]],
                         constant GrassParams& gp [[buffer(3)]],
                         device const uint* staging [[buffer(4)]], device const uint* rowCounts [[buffer(5)]],
                         device uint* cells [[buffer(7)]], device uint* args [[buffer(8)]]) {
    threadgroup uint parts[kGrassSimdGroups];
    uint n = uint(gp.field.y);
    uint acc = 0;
    for (uint r = tid; r < row; r += kGrassRowThreads) acc += rowCounts[r];       // this row starts after every survivor of the rows before it
    uint s = simd_sum(acc);
    if (lane == 0) parts[sid] = s;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    uint offset = 0;
    for (uint k = 0; k < kGrassSimdGroups; k++) offset += parts[k];
    uint count = rowCounts[row];
    for (uint k = tid; k < count; k += kGrassRowThreads) cells[offset + k] = staging[row * n + k];
    if (row == n - 1 && tid == 0) {                                                // MTLDrawPrimitivesIndirectArguments
        args[0] = 7; args[1] = offset + count; args[2] = 0; args[3] = 0;
    }
}
"""#
}
