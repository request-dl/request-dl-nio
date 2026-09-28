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

    package init() {}
}

/// Runs `onAbandoned` exactly once, when the last reference to whichever `Internals.AsyncStream`
/// (or `Internals.AsyncStream.AsyncIterator`) copy is currently carrying this token gets released.
///
/// Exists so a stream built by spawning a background producer task (`Internals.AsyncStream
/// .decompressing(_:using:)` is the one caller today) can be told "nobody is ever going to read
/// this" and cancel that task, instead of it running to completion -- and, since `.untilFirstIteration`
/// buffers everything until read -- growing without bound -- for a response body nobody asked
/// for. See `Internals.AsyncStream.withTerminationToken(_:)`'s own doc comment for how a token
/// actually ends up attached to only the right copies.
private final class AsyncStreamTerminationToken: @unchecked Sendable {

    // MARK: - Private properties

    private let onAbandoned: @Sendable () -> Void

    // MARK: - Inits

    init(_ onAbandoned: @escaping @Sendable () -> Void) {
        self.onAbandoned = onAbandoned
    }

    deinit {
        onAbandoned()
    }
}

/// Releases a flow-controlled stream's `Internals.FlowControlWindow` once the reader that was
/// crediting it is gone.
///
/// One per iterator, shared by every copy of it (`for try await` and the public wrappers'
/// `ResourceDeadline.race` both copy iterators around), so it fires when the last copy goes, not
/// the first.
///
/// Releasing is safe at that point, rather than merely convenient: under `.untilFirstIteration`
/// the subject stops retaining anything once its first iterator exists, so with that iterator
/// gone whatever the producer goes on to append is let go as soon as it is replaced. Keeping the
/// window shut instead would leave the producer -- on the NIO path, an entire connection --
/// paused for a reader that can never come back.
private final class AsyncStreamFlowControlLease: @unchecked Sendable {

    // MARK: - Private properties

    private let window: Internals.FlowControlWindow

    // MARK: - Inits

    init(_ window: Internals.FlowControlWindow) {
        self.window = window
    }

    deinit {
        window.release()
    }
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
    /// reader once reading starts. That gap is itself unbounded, though; a body stream that must
    /// not outrun its reader is additionally metered by an `Internals.FlowControlWindow`, see
    /// `init(flowControl:)`.
    package struct AsyncStream<Element: Sendable>: Sendable, Hashable, AsyncSequence {

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

        /// The window this stream charges as elements go in and credits as they come out, and
        /// how much each element counts for. See `init(flowControl:)`.
        ///
        /// `weight` is evaluated on both sides, against the same element value, so charging and
        /// crediting agree by construction instead of by bookkeeping kept in sync by hand.
        fileprivate struct FlowControl: Sendable {
            let window: Internals.FlowControlWindow
            let weight: @Sendable (Element) -> Int
        }

        package struct AsyncIterator: Sendable, AsyncIteratorProtocol {

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

            /// Its own strong reference to whichever token the `Internals.AsyncStream` that
            /// created this iterator was carrying (see `makeAsyncIterator()`), not merely
            /// whatever's left of that stream value's own reference. That distinction matters:
            /// `for try await` guarantees its own iterator variable stays alive across every call
            /// to `next()`, since it's `mutating` and has to persist between them -- but the
            /// *stream* value itself has no such guarantee. The compiler is free to release a
            /// `for`/`for await` loop's sequence expression as soon as `makeAsyncIterator()`
            /// returns, once nothing else still references it, and a token that only the
            /// original stream value held would then fire mid-read, cancelling a producer that
            /// is, in fact, still being consumed. Holding its own reference here means this
            /// iterator's own lifetime -- not whatever happens to the stream value that produced
            /// it -- is what the token's deinit actually answers to from this point on.
            fileprivate var terminationToken: AsyncStreamTerminationToken?

            /// `nil` unless the stream is flow controlled and this iterator actually took over
            /// its buffer (an iterator that only reports `AlreadyConsumedError` credits nothing,
            /// and must not release a window another reader is still draining).
            fileprivate var flowControl: FlowControl?
            fileprivate var flowControlLease: AsyncStreamFlowControlLease?

            // MARK: - Internal methods

            package mutating func next() async throws -> Element? {
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
                        // Credited as the element is handed over, not after the caller is done
                        // with it: from here on it is the caller's memory, not the stream's
                        // backlog, and whatever the caller does with it is outside the window's
                        // business.
                        if let flowControl {
                            flowControl.window.credit(flowControl.weight(element))
                        }

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

        /// Not part of this stream's identity (see `==`/`hash(into:)`, both `identity`-only):
        /// two copies of "the same" stream can disagree on whether they carry a token at all,
        /// which is exactly what `withTerminationToken(_:)` relies on. `nil` for every stream
        /// this doesn't opt into one.
        private var terminationToken: AsyncStreamTerminationToken?

        /// Set at construction only, never through a copying method the way `terminationToken`
        /// is: the producer's copy has to charge and every reader's copy has to credit, so a copy
        /// of this stream that silently lacked it would unbalance the window for good.
        private let flowControl: FlowControl?

        // MARK: - Inits

        /// Creates a new stream.
        /// - Parameter bufferingPolicy: `.unbounded` keeps everything for every reader.
        /// `.untilFirstIteration` keeps everything until somebody starts reading and then
        /// releases it to that reader, which makes the stream single use.
        package init(bufferingPolicy: SubjectBufferingPolicy = .unbounded) {
            self.init(bufferingPolicy: bufferingPolicy, flowControl: nil)
        }

        private init(bufferingPolicy: SubjectBufferingPolicy, flowControl: FlowControl?) {
            subject = .init(bufferingPolicy: bufferingPolicy)
            identity = .init()
            terminationToken = nil
            self.flowControl = flowControl
        }

        // MARK: - Internal static methods

        package static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.identity === rhs.identity
        }

        package static func empty() -> AsyncStream<Element> {
            let asyncStream = AsyncStream()
            asyncStream.close()
            return asyncStream
        }

        package static func constant(_ value: Element) -> AsyncStream<Element> {
            let asyncStream = AsyncStream()
            asyncStream.append(.success(value))
            asyncStream.close()
            return asyncStream
        }

        package static func throwing(_ error: Error) -> AsyncStream<Element> {
            let asyncStream = AsyncStream()
            asyncStream.append(.failure(error))
            asyncStream.close()
            return asyncStream
        }

        // MARK: - Internal methods

        /// A copy of this stream that cancels whatever `onAbandoned` runs once nobody could ever
        /// read from it again -- either because this copy (or whatever `AsyncIterator`
        /// `makeAsyncIterator()` later derives from it) is released without the stream ever being
        /// read to completion, or without ever being read from at all.
        ///
        /// Built for exactly one caller today, `Internals.AsyncStream.decompressing(_:using:)`'s
        /// background producer task: without this, a caller that inspects only a response's head
        /// and discards its body stream unread left that task running to completion regardless,
        /// decoding and buffering (under `.untilFirstIteration`, without bound, since nothing
        /// ever reads it) a body nobody asked for.
        ///
        /// - Important: Call this on the copy about to be *returned* to whoever might not read
        /// it, after any producer has already captured its own copy of `self` to append/close
        /// through. A producer that captured *this* returned copy instead -- carrying the token
        /// itself -- would have the token's own strong reference keep it alive for exactly as
        /// long as the producer keeps running, which is the one thing this exists to detect the
        /// absence of.
        package func withTerminationToken(_ onAbandoned: @escaping @Sendable () -> Void) -> Self {
            var copy = self
            copy.terminationToken = AsyncStreamTerminationToken(onAbandoned)
            return copy
        }

        package func append(_ value: Result<Element, Error>) {
            switch value {
            case .success(let element):
                // Charged before sending, never after: once sent, a reader can take and credit
                // it immediately, and a credit landing ahead of its own charge could resume a
                // producer on a backlog that was never actually drained.
                if let flowControl {
                    flowControl.window.charge(flowControl.weight(element))
                }

                subject.send(.success(element))

            case .failure(let error):
                // A failure ends the stream, matching the previous behaviour where appending
                // one triggered a close.
                subject.send(.failure(error))
                subject.completed()
            }
        }

        package func close() {
            subject.completed()
        }

        package func makeAsyncIterator() -> AsyncIterator {
            // Handed its own strong reference to `terminationToken`, alongside whatever this
            // stream value's own copy still is: once the iterator exists, it -- not this stream
            // value, which a caller may have no further reason to keep around -- is what
            // `for try await` guarantees stays alive for the rest of the read. See `AsyncIterator
            // .terminationToken`'s own doc comment.
            guard let iterator = subject.makeIteratorIfAvailable() else {
                return .init(
                    state: .failed(AlreadyConsumedError()),
                    terminationToken: terminationToken,
                    flowControl: nil,
                    flowControlLease: nil
                )
            }

            return .init(
                state: .iterating(iterator),
                terminationToken: terminationToken,
                flowControl: flowControl,
                flowControlLease: flowControl.map { AsyncStreamFlowControlLease($0.window) }
            )
        }

        package func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(identity))
        }
    }
}

// MARK: - Flow control

extension Internals.AsyncStream where Element == Internals.DataBuffer {

    /// Creates a single-reader stream of body chunks metered by `flowControl`: every chunk
    /// appended charges its `readableBytes`, and the reader credits the same amount back as it
    /// takes each one.
    ///
    /// Always `.untilFirstIteration`. A window describes the backlog ahead of *one* reader; with
    /// a policy that let several read, each would credit the same bytes again and the window
    /// would drift open without anything having actually been drained.
    ///
    /// - Parameter flowControl: `nil` builds an ordinary stream, exactly like
    ///   `init(bufferingPolicy: .untilFirstIteration)`.
    package init(flowControl: Internals.FlowControlWindow?) {
        self.init(
            bufferingPolicy: .untilFirstIteration,
            flowControl: flowControl.map { FlowControl(window: $0, weight: { $0.readableBytes }) }
        )
    }

    /// The window this stream is metered by, if any.
    ///
    /// Read by `Internals.AsyncStream.decompressing(_:using:)`, which has to meter its own
    /// output the same way whenever its source is, or it would quietly drain a bounded source
    /// into an unbounded stream of its own.
    package var flowControlWindow: Internals.FlowControlWindow? {
        flowControl?.window
    }
}
