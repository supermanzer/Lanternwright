import Foundation

/// The player's contact with water (F02 A5, user note #29: "interacting with the water should have some sort of water sounds"). A pure state machine over the ground
/// height under the feet (metres above the waterline; negative = under water) and the walking speed, so the sounds can be tested without a speaker:
///
/// - **entering** (first contact, once per entry): a splash whose strength follows the speed you came in at;
/// - **leaving**: the drip tail of a foot coming out;
/// - **wading**: a continuous low wash while moving, scaled by depth and speed (different from stepping on wet sand, which is a footfall);
/// - **standing**: a quiet lap against the legs.
///
/// Wet starts at 2 cm under the waterline and ends at 10 cm above it, so a foot on the line does not flutter between the two.
struct WaterContact {
    enum Event: Equatable { case enter(Float), leave }
    private(set) var wet = false
    /// Metres of water at the foot (0 out of the water; about 5 cm at the line, up to the wading limit).
    private(set) var depth: Float = 0

    mutating func update(groundY: Float, speed: Float) -> Event? {
        let was = wet
        if wet { if groundY > 0.10 { wet = false } } else if groundY < -0.02 { wet = true }
        depth = wet ? max(0, -groundY) + 0.05 : 0
        if wet && !was { return .enter(WaterContact.entryStrength(speed: speed)) }
        if !wet && was { return .leave }
        return nil
    }
    /// 0.1 at a crawl, about 0.5 at a walk (3.2 m/s), 1 at a run (6.5 m/s).
    static func entryStrength(speed: Float) -> Float { min(max(speed / 6.5, 0.1), 1) }
    /// 0...1: the wash of water against the legs while moving; exactly 0 out of the water or standing still.
    func drag(speed: Float) -> Float { wet ? min(1, (0.3 + depth / 0.35) * min(speed / 3.2, 1.2)) * (speed > 0.3 ? 1 : 0) : 0 }
    /// 0...1: the quiet lap while standing in the water; exactly 0 out of it or while moving.
    func lap(speed: Float) -> Float { wet && speed <= 0.3 ? min(1, 0.4 + depth / 0.4) : 0 }
}
