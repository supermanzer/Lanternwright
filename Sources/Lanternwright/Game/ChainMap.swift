import Foundation

/// S04.8: the chain shown as a map for the first time (S04 plan; page 14 describes it): brass pins on slate, Varrow the first link, a chain of pins the player does not know, the last with no name.
/// Data only: the overlay draws it as a reading card, from these normalised points (0...1 across the card, y down). One prop in the Archive (builder A's `ti_chain_map`), read like the door note.
enum ChainMap {
    static let interactableName = "ti_chain_map"
    /// The pins, in chain order. The first is Varrow (the only name on the card); the rest are unnamed; the last is drawn as an empty ring: the pin with no name.
    static let pins: [(x: Double, y: Double)] = [(0.10, 0.72), (0.22, 0.52), (0.31, 0.66), (0.43, 0.40), (0.52, 0.56), (0.63, 0.30), (0.72, 0.46), (0.83, 0.24), (0.92, 0.38)]
    static let firstName = "Varrow"
}
