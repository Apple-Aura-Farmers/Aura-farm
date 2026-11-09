#if DEBUG
    import Foundation

    /// An advice store that keeps nothing on disk, for the result states gallery and tests.
    final class InMemoryAdviceStore: AdviceStore, @unchecked Sendable {
        private let lock = NSLock()
        private var saved: [URL: SavedAdvice]
        /// Makes `save` throw, to test a failing disk.
        var failsToSave = false
        /// How many times `save` succeeded.
        private(set) var saveCount = 0

        struct SaveFailure: Error {}

        init(saved: [URL: SavedAdvice] = [:]) {
            self.saved = saved
        }

        func load(for sweep: SavedSweep) -> SavedAdvice? {
            lock.withLock { saved[sweep.url] }
        }

        func save(_ advice: SavedAdvice, for sweep: SavedSweep) throws {
            if failsToSave { throw SaveFailure() }
            lock.withLock {
                saved[sweep.url] = advice
                saveCount += 1
            }
        }
    }
#endif
