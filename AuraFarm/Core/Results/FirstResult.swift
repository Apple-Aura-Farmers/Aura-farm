//
//  FirstResult.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 13/11/26.
//

import Foundation

/// Runs some work against a timer and returns whichever finishes first, without waiting for the
/// other one.
///
/// A task group cannot do this: it waits for every child before it returns, so work that ignores
/// cancellation (a model request that has stalled, say) would hold the caller long after the
/// timer had gone off, and the screen would sit on its spinner. Here the loser is cancelled and
/// left to finish on its own.
///
/// One instance runs once.
final class FirstResult<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var isFinished = false

    /// The work's result or error, or `timeoutError` if the timer goes off first. If the caller is
    /// cancelled it throws `CancellationError` at once, whether or not the work notices.
    func run(
        timeout: Duration,
        timeoutError: any Error,
        work: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
                lock.lock()
                if isFinished {
                    // Cancelled before it began.
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                lock.unlock()

                let worker = Task {
                    do {
                        let value = try await work()
                        self.finish(.success(value))
                    } catch {
                        self.finish(.failure(error))
                    }
                }
                let timer = Task {
                    guard (try? await Task.sleep(for: timeout)) != nil else { return }
                    self.finish(.failure(timeoutError))
                }

                lock.lock()
                tasks = [worker, timer]
                let alreadyFinished = isFinished
                lock.unlock()
                // One of them finished before both were started.
                if alreadyFinished {
                    worker.cancel()
                    timer.cancel()
                }
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    /// Hands back the first result and cancels both tasks. Later calls do nothing.
    private func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        lock.unlock()

        for task in tasks { task.cancel() }
        continuation?.resume(with: result)
    }
}
