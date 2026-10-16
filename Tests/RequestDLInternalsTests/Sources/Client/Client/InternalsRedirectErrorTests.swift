//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

/// What a redirect an executor could not follow looks like once it is the same whichever executor
/// it was.
struct InternalsRedirectErrorTests {

    @Test(arguments: [
        Internals.RedirectError.Reason.limitReached,
        .cycleDetected,
        .invalidURL(nil),
        .invalidURL("http://[not a url"),
    ])
    func description_saysWhatHappenedForEveryReason(_ reason: Internals.RedirectError.Reason) {
        // Given
        let error = Internals.RedirectError(reason)

        // Then
        #expect(error.reason == reason)
        #expect(!String(describing: error).isEmpty)
    }

    /// An error's description ends up in logs, and the URL of a redirect may carry credentials.
    @Test
    func description_neverHasTheURLInIt() {
        // Given
        let error = Internals.RedirectError(.invalidURL("http://user:secret@[not a url"))

        // Then
        #expect(!String(describing: error).contains("secret"))
    }

    #if canImport(NIOCore)
    /// AsyncHTTPClient's own errors for these conditions are this type's, and nothing else is.
    @Test
    func translating_turnsAsyncHTTPClientsRedirectErrorsIntoThisOne() {
        #expect(
            (Internals.RedirectError.translating(HTTPClientError.redirectLimitReached) as? Internals.RedirectError)?
                .reason == .limitReached
        )
        #expect(
            (Internals.RedirectError.translating(HTTPClientError.redirectCycleDetected) as? Internals.RedirectError)?
                .reason == .cycleDetected
        )
        #expect(
            (Internals.RedirectError.translating(HTTPClientError.invalidURL) as? Internals.RedirectError)?.reason
                == .invalidURL(nil)
        )
    }

    @Test
    func translating_leavesEveryOtherErrorAlone() {
        // Then
        #expect((Internals.RedirectError.translating(HTTPClientError.readTimeout) as? HTTPClientError) == .readTimeout)
        #expect(Internals.RedirectError.translating(CancellationError()) is CancellationError)
    }
    #endif
}
