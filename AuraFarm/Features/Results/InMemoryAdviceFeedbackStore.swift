#if DEBUG
    import Foundation

    /// A feedback store that keeps nothing on disk, for the result states gallery and tests.
    final class InMemoryAdviceFeedbackStore: AdviceFeedbackStore, @unchecked Sendable {
        private let lock = NSLock()
        private var saved: [URL: [AdviceFeedback]] = [:]
        /// Makes `record` throw, to test a failing disk.
        var failsToRecord = false

        struct RecordFailure: Error {}

        func all(for sweep: SavedSweep) -> [AdviceFeedback] {
            lock.withLock { saved[sweep.url] ?? [] }
        }

        func record(_ feedback: AdviceFeedback, for sweep: SavedSweep) throws {
            if failsToRecord { throw RecordFailure() }
            lock.withLock {
                var entries = saved[sweep.url] ?? []
                if let index = entries.firstIndex(where: { $0.id == feedback.id }) {
                    entries[index] = feedback
                } else {
                    entries.append(feedback)
                }
                saved[sweep.url] = entries
            }
        }
    }
#endif
