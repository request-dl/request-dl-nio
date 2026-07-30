/*
 See LICENSE for this package's licensing information.
*/

import SwiftAsyncStream

extension Internals {

    /// A replaying broadcast stream of values, terminated by completion or by an error.
    ///
    /// Backed by `ReplaySubject`, so every iterator starts at the first element ever appended.
    /// That is load bearing rather than incidental: `constant(_:)`, `throwing(_:)` and
    /// `empty()` produce and finish during construction, and on the live path the download
    /// iterator is only created when the caller reaches for the bytes, long after they start
    /// arriving.
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

            // MARK: - Private properties

            fileprivate var iterator: SubjectAsyncIterator<Value>?

            // MARK: - Internal methods

            mutating func next() async throws -> Element? {
                guard var iterator = self.iterator else {
                    return nil
                }

                guard let value = await iterator.next() else {
                    self.iterator = nil
                    return nil
                }

                self.iterator = iterator

                switch value {
                case .success(let element):
                    return element

                case .failure(let error):
                    // Terminal. Anything after a throw stays finished.
                    self.iterator = nil
                    throw error
                }
            }
        }

        // MARK: - Private properties

        private let subject: ReplaySubject<Value>
        private let identity: Identity

        // MARK: - Inits

        init() {
            subject = .init(bufferingPolicy: .unbounded)
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
            .init(iterator: subject.makeAsyncIterator())
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(identity))
        }
    }
}
