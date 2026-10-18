//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

/// A part of the request body that can't be read while it is being sent fails the request with
/// ``RequestBodyUnreadableError``, and not with whatever each executor happens to call it.
///
/// The condition itself (a file that backs the body cut short or removed after the body was
/// assembled) is covered where it is raised, by `InternalsBodySequenceTests`: through a live
/// request it depends on when each executor opens the file, which is not something to build a
/// test on. What this covers is that it reaches the caller as the public error.
struct RequestBodyUnreadableErrorTests {

    @Test
    func aPartThatCannotBeReadWhileSending_failsTheResponseWithRequestBodyUnreadableError() async throws {
        // Given: the executor ends the exchange with it before a response comes in.
        let head = Internals.AsyncStream<Internals.ResponseHead>()
        head.append(.failure(Internals.RequestBodyPartUnreadableError(expectedBytes: 4_096)))

        let response = AsyncResponse(
            seed: .withoutCancellation,
            response: Internals.AsyncResponse(
                logger: nil,
                uploadingBytes: .zero,
                upload: .empty(),
                decompressionDispatch: .skip,
                head: head,
                download: .empty()
            )
        )

        // Then
        let error = try await #require(throws: RequestBodyUnreadableError.self) {
            for try await _ in response {}
        }

        #expect(error.expectedBytes == 4_096)
    }

    /// Before there is a response at all: in a step ahead of the transport.
    @Test
    func aPartThatCannotBeReadBeforeThereIsAResponse_failsWithRequestBodyUnreadableError() async throws {
        // Given
        let task = RawTask(content: EmptyProperty())

        // Then
        let error = try await #require(throws: RequestBodyUnreadableError.self) {
            try await task.surfacingResourceTimeout {
                throw Internals.RequestBodyPartUnreadableError(expectedBytes: 12)
            }
        }

        #expect(error.expectedBytes == 12)
    }

    @Test
    func theErrorDescribesItself() {
        // Given
        let error = RequestBodyUnreadableError(Internals.RequestBodyPartUnreadableError(expectedBytes: 4_096))

        // Then
        #expect(error.expectedBytes == 4_096)
        #expect(String(describing: error).contains("4096"))
    }
}
