//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

/// Thrown when a response body is read a second time.
///
/// The bytes of a response are buffered until somebody starts reading them, and released to
/// that reader as it advances. There is nothing left for a second reader, so this is raised
/// instead of handing back whatever survived, which would be a partial result that changes
/// with how far the first reader got.
public struct AlreadyConsumedError: Error, CustomStringConvertible {

    public var description: String {
        """
        This response body has already been consumed. Read it once and keep the result, or \
        issue the request again.
        """
    }

    init() {}
}

extension Internals {

    /// A replaying broadcast stream of values, terminated by completion or by an error.
    ///
    /// Backed by `ReplaySubject`. Replay is load bearing rather than incidental: `constant(_:)`,
    /// `throwing(_:)` and `empty()` produce and finish during construction, and on the live path
    /// the download iterator is only created when the caller reaches for the bytes, long after
    /// they start arriving.
    ///
    /// Streams that are only ever read once should be built with `.untilFirstIteration`, which
    /// keeps that guarantee while dropping the retained bytes to the gap between producer and
    /// reader once reading starts.
    struct AsyncStream<Element: Sendable>: Sendable, Hashable, AsyncSequence {

        // MARK: - Inner types

        /// What travels through the subject.
        ///
        /// `Result<Element, Error>` cannot be carried directly because `any Error` is not
        /// `Sendable`. Marking this payload unchecked states the assumption in one visible
        /// place, instead of burying it under an unchecked conformance on a whole storage
        /// class the way the previous implementation did.
        fileprivate enum Value: @unchecked Sendable {
            case success(Element)
            case failure(any Error)
        }

        /// Anchor for `Hashable`.
        ///
        /// The subject is a value type, so equality needs something that copies of this stream
        /// share and separately created streams do not.
        fileprivate final class Identity: Sendable {}

        struct AsyncIterator: Sendable, AsyncIteratorProtocol {

            // MARK: - Inner types

            fileprivate enum State: @unchecked Sendable {
                case iterating(SubjectAsyncIterator<Value>)
                /// Raised on the first `next()`. `makeAsyncIterator()` cannot throw, so a
                /// stream with nothing left to give hands back an iterator that explains
                /// itself the moment somebody reads from it.
                case failed(any Error)
                case done
            }

            // MARK: - Private properties

            fileprivate var state: State

            // MARK: - Internal methods

            mutating func next() async throws -> Element? {
                switch state {
                case .done:
                    return nil

                case .failed(let error):
                    state = .done
                    throw error

                case .iterating(var iterator):
                    guard let value = await iterator.next() else {
                        state = .done
                        return nil
                    }

                    state = .iterating(iterator)

                    switch value {
                    case .success(let element):
                        return element

                    case .failure(let error):
                        state = .done
                        throw error
                    }
                }
            }
        }

        // MARK: - Private properties

        private let subject: ReplaySubject<Value>
        private let identity: Identity

        // MARK: - Inits

        /// Creates a new stream.
        /// - Parameter bufferingPolicy: `.unbounded` keeps everything for every reader.
        /// `.untilFirstIteration` keeps everything until somebody starts reading and then
        /// releases it to that reader, which makes the stream single use.
        init(bufferingPolicy: SubjectBufferingPolicy = .unbounded) {
            subject = .init(bufferingPolicy: bufferingPolicy)
            identity = .init()
        }

        // MARK: - Internal static methods

        static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.identity === rhs.identity
        }

        static func empty() -> AsyncStream<Element> {
            let asyncStream = AsyncStream()
            asyncStream.close()
            return asyncStream
        }

        static func constant(_ value: Element) -> AsyncStream<Element> {
            let asyncStream = AsyncStream()
            asyncStream.append(.success(value))
            asyncStream.close()
            return asyncStream
        }

        static func throwing(_ error: Error) -> AsyncStream<Element> {
            let asyncStream = AsyncStream()
            asyncStream.append(.failure(error))
            asyncStream.close()
            return asyncStream
        }

        // MARK: - Internal methods

        func append(_ value: Result<Element, Error>) {
            switch value {
            case .success(let element):
                subject.send(.success(element))

            case .failure(let error):
                // A failure ends the stream, matching the previous behaviour where appending
                // one triggered a close.
                subject.send(.failure(error))
                subject.completed()
            }
        }

        func close() {
            subject.completed()
        }

        func makeAsyncIterator() -> AsyncIterator {
            guard let iterator = subject.makeIteratorIfAvailable() else {
                return .init(state: .failed(AlreadyConsumedError()))
            }

            return .init(state: .iterating(iterator))
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(identity))
        }
    }
}
