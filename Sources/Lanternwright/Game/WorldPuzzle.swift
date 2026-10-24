/// What a world's puzzle must offer the game, so `Game` does not hard-code any one puzzle: which flags make up its
/// saved state, how to rebuild its visuals from them, which interactables are its own, and what to do when one is
/// clicked. A third world adds a conforming class and one line in `Game.init`; saving, restoring, click routing and
/// per-tick visuals follow automatically.
protocol WorldPuzzle: AnyObject {
    var world: WorldKind { get }
    /// Flags that are the puzzle's saved progress (the save keeps whichever of these are set).
    var persistentFlags: [String] { get }
    /// Bring the puzzle (state and visuals) to what `flags` describe, as when loading a save.
    func restore(from flags: Set<String>)
    /// True for interactable ids this puzzle owns.
    func handles(_ interactableID: String) -> Bool
    func activate(_ interactableID: String)
    func updateVisuals(time: Float)
}
