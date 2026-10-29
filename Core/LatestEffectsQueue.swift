import Foundation

/// Serializes system side effects without locking timer commands. Intermediate
/// refreshes are coalesced so a slow effect is followed by the latest state.
@MainActor public final class LatestEffectsQueue<Value: Sendable> {
    private var latest: Value?
    private var worker: Task<Void, Never>?
    private let apply: @MainActor (Value) async -> Void

    public init(apply: @escaping @MainActor (Value) async -> Void) { self.apply = apply }

    public func submit(_ value: Value) {
        latest = value
        guard worker == nil else { return }
        worker = Task {
            while let value = self.latest {
                self.latest = nil
                await self.apply(value)
            }
            self.worker = nil
        }
    }

    public func waitForIdle() async { await worker?.value }
}
