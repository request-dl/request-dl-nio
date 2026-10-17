//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Foundation
import Testing

@testable @_spi(Testing) import RequestDLInternals

/// What a request fails with when `URLSession` ends it with an error after its delegate refused
/// a redirect. Normally `URLSession` hands back the 3xx and the client reports the refusal, but
/// under load `bytes(for:delegate:)` was seen to end with a bare `NSURLErrorUnknown` instead
/// (the iPadOS job of a CI run, and the iPad simulator with the CPUs busy).
struct InternalsURLSessionClientRefusedRedirectTests {

    @Test
    func failure_whenTheRedirectWasRefused_isTheRefusalNotTheErrorURLSessionGave() {
        // Given
        let bare = URLError(.unknown)

        // When
        let error = Internals.URLSessionClient.failure(
            bare,
            afterRedirectUnder: .follow(max: 0, allowCycles: false)
        )

        // Then
        #expect((error as? Internals.RedirectError)?.reason == .limitReached)
    }

    @Test
    func failure_whenTheRedirectWasACycle_isCycleDetected() {
        // When
        let error = Internals.URLSessionClient.failure(
            URLError(.unknown),
            afterRedirectUnder: .follow(max: 5, allowCycles: false)
        )

        // Then
        #expect((error as? Internals.RedirectError)?.reason == .cycleDetected)
    }

    @Test
    func failure_whenTheRequestWasCancelled_staysTheCancellation() {
        // When
        let urlError = Internals.URLSessionClient.failure(
            URLError(.cancelled),
            afterRedirectUnder: .follow(max: 0, allowCycles: false)
        )

        let cancellation = Internals.URLSessionClient.failure(
            CancellationError(),
            afterRedirectUnder: .follow(max: 0, allowCycles: false)
        )

        // Then
        #expect((urlError as? URLError)?.code == .cancelled)
        #expect(cancellation is CancellationError)
    }

    @Test
    func failure_whenNothingWasRefused_isTheErrorURLSessionGave() {
        // When
        let error = Internals.URLSessionClient.failure(
            URLError(.timedOut),
            afterRedirectUnder: .disallow
        )

        // Then
        #expect((error as? URLError)?.code == .timedOut)
    }
}

#endif
