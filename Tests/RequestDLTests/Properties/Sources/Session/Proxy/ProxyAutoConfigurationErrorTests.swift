//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

struct ProxyAutoConfigurationErrorTests {

    @Test
    func init_carriesTheReasonAndWhatTheSystemReported() {
        // When
        let timedOut = ProxyAutoConfigurationError(.init(reason: .timedOut))
        let failed = ProxyAutoConfigurationError(.init(reason: .failed, details: "PAC file error"))

        // Then
        #expect(timedOut.reason == .timedOut)
        #expect(timedOut.details == nil)
        #expect(failed.reason == .failed)
        #expect(failed.details == "PAC file error")
    }

    @Test
    func description_whenTheScriptTookTooLong_saysSo() {
        // Given
        let error = ProxyAutoConfigurationError(.init(reason: .timedOut))

        // Then
        #expect(error.description.contains("did not finish in time"))
    }

    @Test
    func description_saysWhatHappenedAndWhatPolicyCausedIt() {
        // Given
        let error = ProxyAutoConfigurationError(.init(reason: .failed, details: "PAC file error"))

        // Then
        #expect(error.description.contains("PAC file error"))
        #expect(error.description.contains("could not be fetched or run"))
        #expect(error.description.contains("SystemProxy(onPACFailure: .fail)"))
    }
}
