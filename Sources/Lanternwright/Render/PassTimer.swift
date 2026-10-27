import Metal
import Foundation

/// G10.0.1: a per-pass GPU timer. Every render and blit encoder of a frame gets a start and an end timestamp (`MTLCounterSampleBuffer`, sampled at the stage
/// boundaries of the encoder), and the frame's table of (pass, ms) is read back when the GPU has finished it, never before: the frame in flight is never waited for.
/// It changes nothing about what is drawn. It is nil unless a tool or the game switches it on (`Renderer.passTimer`), and it is unavailable (nil) on a device
/// that cannot sample counters at stage boundaries, in which case everything simply runs without it.
final class PassTimer: @unchecked Sendable {
    /// One encoder of one frame: its label (read when the frame resolves, since the callers label the encoder after creating it) and its two sample slots.
    private struct Record { let encoder: MTLCommandEncoder; let slot: Int }
    private final class Frame {
        var records: [Record] = []
        var samples = 0
        var resolved = true
    }

    /// The most recent resolved frame: pass labels in encode order with the GPU milliseconds of each, summed by label.
    private(set) var latest: [(pass: String, ms: Double)] = []
    /// GPU milliseconds of the whole frame (command buffer start to end), the figure the table is compared with.
    private(set) var latestFrameMS: Double = 0
    private(set) var framesResolved = 0

    private let device: MTLDevice
    private let lock = NSLock()
    private let capacity = 256
    private var buffers: [MTLCounterSampleBuffer] = []
    private var frames: [Frame] = []
    private var next = 0
    private var cpuBase: MTLTimestamp = 0, gpuBase: MTLTimestamp = 0
    private var gpuScale = 1.0                  // nanoseconds per GPU tick, calibrated against the CPU clock when a frame resolves

    /// Three frames can be in flight at once (the layer's drawable pool); each gets its own sample buffer.
    static let depth = 3

    init?(device: MTLDevice) {
        guard device.supportsCounterSampling(.atStageBoundary),
              let set = device.counterSets?.first(where: { $0.name == MTLCommonCounterSet.timestamp.rawValue }) else { return nil }
        self.device = device
        for _ in 0..<Self.depth {
            let d = MTLCounterSampleBufferDescriptor()
            d.counterSet = set
            d.storageMode = .shared
            d.sampleCount = capacity
            d.label = "pass timer"
            guard let b = try? device.makeCounterSampleBuffer(descriptor: d) else { return nil }
            buffers.append(b)
            frames.append(Frame())
        }
        (cpuBase, gpuBase) = Self.clocks(device)
    }

    private static func clocks(_ d: MTLDevice) -> (MTLTimestamp, MTLTimestamp) {
        let t = d.sampleTimestamps()
        return (t.cpu, t.gpu)
    }
    private var current: Frame?
    private var currentIndex = 0

    /// Start a frame: choose the next sample buffer and arrange for the table to be read when `commandBuffer` completes.
    func begin(_ commandBuffer: MTLCommandBuffer) {
        lock.lock()
        currentIndex = next
        next = (next + 1) % Self.depth
        let f = frames[currentIndex]
        f.records = []; f.samples = 0; f.resolved = false
        current = f
        let index = currentIndex
        lock.unlock()
        commandBuffer.addCompletedHandler { [weak self] cb in self?.resolve(index: index, commandBuffer: cb) }
    }

    /// The frame's encoding is finished: later encoders (debug views, tools) are not part of it.
    func end() { lock.lock(); current = nil; lock.unlock() }

    /// A render encoder for `descriptor` that writes its start and end timestamps. Falls back to a plain encoder when the frame's buffer is full.
    func renderEncoder(_ cb: MTLCommandBuffer, _ descriptor: MTLRenderPassDescriptor) -> MTLRenderCommandEncoder? {
        if let slot = reserve() {
            let a = descriptor.sampleBufferAttachments[0]!
            a.sampleBuffer = buffers[currentIndex]
            a.startOfVertexSampleIndex = slot
            a.endOfFragmentSampleIndex = slot + 1
            guard let enc = cb.makeRenderCommandEncoder(descriptor: descriptor) else { return nil }
            current?.records.append(Record(encoder: enc, slot: slot))
            return enc
        }
        return cb.makeRenderCommandEncoder(descriptor: descriptor)
    }

    func blitEncoder(_ cb: MTLCommandBuffer) -> MTLBlitCommandEncoder? {
        if let slot = reserve() {
            let d = MTLBlitPassDescriptor()
            let a = d.sampleBufferAttachments[0]!
            a.sampleBuffer = buffers[currentIndex]
            a.startOfEncoderSampleIndex = slot
            a.endOfEncoderSampleIndex = slot + 1
            guard let enc = cb.makeBlitCommandEncoder(descriptor: d) else { return nil }
            current?.records.append(Record(encoder: enc, slot: slot))
            return enc
        }
        return cb.makeBlitCommandEncoder()
    }

    private func reserve() -> Int? {
        guard let f = current, f.samples + 2 <= capacity else { return nil }
        let s = f.samples
        f.samples += 2
        return s
    }

    /// Read the frame's samples once the GPU is done with it, together with the command buffer's own GPU window (the figure the table is compared with).
    private func resolve(index: Int, commandBuffer cb: MTLCommandBuffer) {
        lock.lock(); defer { lock.unlock() }
        let f = frames[index]
        guard !f.resolved else { return }
        f.resolved = true
        let (cpu, gpu) = Self.clocks(device)
        if gpu > gpuBase, cpu > cpuBase { gpuScale = Double(cpu - cpuBase) / Double(gpu - gpuBase) }
        guard f.samples > 0, let data = try? buffers[index].resolveCounterRange(0..<f.samples), data.count >= f.samples * MemoryLayout<MTLCounterResultTimestamp>.stride else { return }
        var order: [String] = [], sums: [String: Double] = [:]
        // Apple GPUs start a pass's vertex work while the previous pass's fragments are still running, so the raw start-to-end intervals overlap and
        // their sum is several frames long. A pass is charged from the later of its own start and the previous pass's end, to its own end: the time the frame
        // spent finishing it. The charges then add up to the busy time of the frame, and the table can be compared with the frame figure.
        data.withUnsafeBytes { raw in
            let t = raw.bindMemory(to: UInt64.self)
            var previousEnd: UInt64 = 0
            for r in f.records {
                let a = t[r.slot], b = t[r.slot + 1]
                guard a != UInt64.max, b != UInt64.max, b >= a else { continue }      // MTLCounterErrorValue: the GPU did not write this sample
                let label = r.encoder.label ?? "unlabelled"
                if sums[label] == nil { order.append(label) }
                sums[label, default: 0] += Double(b > max(a, previousEnd) ? b - max(a, previousEnd) : 0) * gpuScale / 1e6
                previousEnd = max(previousEnd, b)
            }
        }
        latest = order.map { ($0, sums[$0]!) }
        latestFrameMS = max(0, cb.gpuEndTime - cb.gpuStartTime) * 1000
        framesResolved += 1
        f.records = []
    }

    /// The latest table on one line for the F-key feedback context: `frame 5.0 | shadow 4096 0.44, opaque + sky 3.17, ...` (passes under 0.02 ms left out).
    var summary: String {
        lock.lock(); defer { lock.unlock() }
        guard !latest.isEmpty else { return "none yet" }
        return String(format: "frame %.2f | ", latestFrameMS) + latest.filter { $0.ms >= 0.02 }.map { String(format: "%@ %.2f", $0.pass, $0.ms) }.joined(separator: ", ")
    }

    /// For a tool that has waited for the command buffer: make sure its frame is resolved before reading `latest`.
    func drain(_ cb: MTLCommandBuffer) {
        guard cb.status == .completed else { return }
        lock.lock(); let pending = frames.indices.filter { !frames[$0].resolved && !frames[$0].records.isEmpty }; lock.unlock()
        for i in pending { resolve(index: i, commandBuffer: cb) }
    }
}
