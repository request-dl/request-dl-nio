//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import Testing

@testable import RequestDLInternals

#if canImport(Network)
import Network
#endif

/// Which failures a lost connection is told apart from, for the two things that carry on after
/// one: a download that reconnects and an upload that continues.
struct InternalsNIODownloadReconnectionTransientFailureTests {

    private struct Unrelated: Error {}

    @Test
    func aFailureThatIsNotAboutTheConnection_isNotTransient() {
        #expect(!Internals.NIODownloadReconnection.isTransientTransportFailure(Unrelated()))
        #expect(!Internals.NIODownloadReconnection.isTransientTransportFailure(CancellationError()))
    }

    #if canImport(Network)

    /// What `NIOTransportServices` reports for a connection that is reset while a request body is
    /// written. It is its own type, which is not an `NWError`, and this target doesn't depend on
    /// the module that declares it, so it is recognised by name and by the code it wraps. A type
    /// with the same name and shape stands in for it.
    private struct NWPOSIXError: Error {
        let errorCode: POSIXErrorCode
    }

    @Test(arguments: [POSIXErrorCode.ECONNRESET, .EPIPE, .ECONNABORTED, .ETIMEDOUT, .ENOTCONN, .ECONNREFUSED])
    func aConnectionResetByTheNetworkFrameworkTransport_isTransient(_ code: POSIXErrorCode) {
        #expect(Internals.NIODownloadReconnection.isTransientTransportFailure(NWPOSIXError(errorCode: code)))
    }

    @Test(arguments: [POSIXErrorCode.EACCES, .ENOENT, .EINVAL])
    func aPOSIXFailureThatIsNotAboutTheConnection_isNotTransient(_ code: POSIXErrorCode) {
        #expect(!Internals.NIODownloadReconnection.isTransientTransportFailure(NWPOSIXError(errorCode: code)))
    }

    private struct SomethingElse: Error {
        let errorCode: POSIXErrorCode
    }

    @Test
    func anErrorThatMerelyLooksLikeIt_isNotTransient() {
        #expect(
            !Internals.NIODownloadReconnection.isTransientTransportFailure(SomethingElse(errorCode: .ECONNRESET))
        )
    }

    #endif
}

#endif
