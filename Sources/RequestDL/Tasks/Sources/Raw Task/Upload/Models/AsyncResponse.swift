//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A structure that represents an asynchronous response.
public struct AsyncResponse: Sendable, AsyncSequence {

    ///
    /// A structure that defines an async iterator for the asynchronous response.
    ///
    public struct Iterator: Sendable, AsyncIteratorProtocol {

        fileprivate let seed: Internals.TaskSeed
        fileprivate var iterator: Internals.AsyncResponse.Iterator
        fileprivate let onResponseHead: (@Sendable (Result<Internals.ResponseHead, Error>) -> Void)?
        fileprivate let deadline: Internals.ResourceDeadline

        ///
        /// Returns the next element in the sequence, or nil if there are no more elements.
        ///
        /// - Returns: The next element in the sequence.
        ///
        mutating public func next() async throws -> Element? {
            do {
                // `deadline.race(_:)` may run this closure as a real task-group child task, so it
                // captures `iterator`'s *current value* immutably and owns a private mutable copy
                // of it entirely within its own execution, rather than mutating the `var` this
                // method itself owns from what could be a different task.
                let startIterator = iterator
                let (step, updatedIterator) = try await deadline.race(seed: seed) {
                    var iterator = startIterator
                    let step = try await iterator.next()
                    return (step, iterator)
                }
                iterator = updatedIterator

                switch step {
                case .upload(let step):
                    return .upload(
                        UploadStep(
                            chunkSize: step.chunkSize,
                            totalSize: step.totalSize
                        )
                    )
                case .download(let step):
                    // Fires at most once: the underlying iterator only ever produces a single
                    // `.download` case, after which it's exhausted (see
                    // `Internals.AsyncResponse.Iterator.next()`), so there's no later call this
                    // could re-fire from.
                    onResponseHead?(.success(step.head))

                    return .download(
                        DownloadStep(
                            head: .init(step.head),
                            bytes: AsyncBytes(
                                seed: seed,
                                bytes: step.bytes,
                                deadline: deadline
                            )
                        )
                    )
                case .none:
                    return nil
                }
            } catch is Internals.ResourceTimeoutError {
                let error = ResourceTimeoutError()
                onResponseHead?(.failure(error))
                throw error
            } catch {
                onResponseHead?(.failure(error))
                throw error
            }
        }
    }

    public typealias Element = ResponseStep

    // MARK: - Internal properties

    var logger: Internals.TaskLogger? {
        response.logger
    }

    // MARK: - Private properties

    private let seed: Internals.TaskSeed
    private let response: Internals.AsyncResponse
    private let onResponseHead: (@Sendable (Result<Internals.ResponseHead, Error>) -> Void)?
    private let deadline: Internals.ResourceDeadline

    // MARK: - Inits

    init(
        seed: Internals.TaskSeed,
        response: Internals.AsyncResponse,
        onResponseHead: (@Sendable (Result<Internals.ResponseHead, Error>) -> Void)? = nil,
        deadline: Internals.ResourceDeadline = .init(nanoseconds: nil)
    ) {
        self.seed = seed
        self.response = response
        self.onResponseHead = onResponseHead
        self.deadline = deadline
    }

    // MARK: - Public methods

    ///
    /// Returns an async iterator over the elements of the sequence.
    ///
    /// - Returns: An async iterator for the asynchronous response.
    ///
    public func makeAsyncIterator() -> Iterator {
        Iterator(
            seed: seed,
            iterator: response.makeAsyncIterator(),
            onResponseHead: onResponseHead,
            deadline: deadline
        )
    }
}
