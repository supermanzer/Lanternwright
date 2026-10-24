import Foundation

enum Ease {
    case linear, inOutCubic, outCubic

    func apply(_ t: Float) -> Float {
        switch self {
        case .linear: return t
        case .outCubic: let u = 1 - t; return 1 - u * u * u
        case .inOutCubic: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        }
    }
}

/// A tiny tween system. A tween calls `apply` with an eased 0...1 value each tick for `duration` seconds after
/// `delay`. It is driven by the game's fixed tick, so animation (and tests of it) are deterministic.
final class Animator {
    private struct Tween {
        var elapsed: Float = 0
        let delay: Float
        let duration: Float
        let ease: Ease
        let apply: (Float) -> Void
        let completion: (() -> Void)?
    }
    private var tweens: [Tween] = []

    var isIdle: Bool { tweens.isEmpty }

    func tween(delay: Float = 0, duration: Float, ease: Ease = .inOutCubic,
               apply: @escaping (Float) -> Void, completion: (() -> Void)? = nil) {
        tweens.append(Tween(delay: delay, duration: duration, ease: ease, apply: apply, completion: completion))
    }

    /// Run `action` once, `delay` seconds from now.
    func after(_ delay: Float, _ action: @escaping () -> Void) {
        tweens.append(Tween(delay: delay, duration: 0, ease: .linear, apply: { _ in }, completion: action))
    }

    func update(_ dt: Float) {
        var running: [Tween] = []
        var finished: [Tween] = []
        for var t in tweens {
            t.elapsed += dt
            if t.elapsed >= t.delay {
                let local = t.elapsed - t.delay
                if t.duration <= 0 {
                    finished.append(t)
                    continue
                }
                let p = min(local / t.duration, 1)
                t.apply(t.ease.apply(p))
                if p >= 1 { finished.append(t); continue }
            }
            running.append(t)
        }
        tweens = running      // completions below may add new tweens, so commit the survivors first
        for t in finished {
            if t.duration <= 0 { t.apply(1) }
            t.completion?()
        }
    }
}
