//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLInternals

struct DownloadResumptionPolicyTests {

    @Test
    func disabled_hasNoResumption() {
        #expect(DownloadResumptionPolicy.disabled.resumption == nil)
    }

    @Test
    func enabled_usesTheDocumentedDefaults() {
        // When
        let resumption = DownloadResumptionPolicy.enabled().resumption

        // Then
        #expect(resumption?.maximumAttemptsWithoutProgress == 3)
        #expect(resumption?.delay == 1_000_000_000)
    }

    @Test
    func enabled_convertsTheDelayToNanoseconds() {
        #expect(DownloadResumptionPolicy.enabled(delay: 0.25).resumption?.delay == 250_000_000)
        #expect(DownloadResumptionPolicy.enabled(delay: 0).resumption?.delay == .zero)
    }

    @Test
    func enabled_clampsValuesThatCouldNotBeHonoured() {
        // A negative delay is no delay, and a policy always allows at least one attempt.
        #expect(DownloadResumptionPolicy.enabled(delay: -5).resumption?.delay == .zero)
        #expect(
            DownloadResumptionPolicy.enabled(maximumAttemptsWithoutProgress: 0).resumption?
                .maximumAttemptsWithoutProgress == 1
        )
        #expect(
            DownloadResumptionPolicy.enabled(maximumAttemptsWithoutProgress: -3).resumption?
                .maximumAttemptsWithoutProgress == 1
        )
        #expect(DownloadResumptionPolicy.enabled(delay: .infinity).resumption?.delay == .max)
    }

    @Test
    func policies_areEquatableByTheirSettings() {
        #expect(DownloadResumptionPolicy.enabled(delay: 2) == .enabled(delay: 2))
        #expect(DownloadResumptionPolicy.enabled(delay: 2) != .enabled(delay: 3))
        #expect(DownloadResumptionPolicy.enabled() != .disabled)
    }

    // MARK: - Transfer control

    /// Asking for resumption alone must not change how a request body is sent: only something
    /// that can suspend an execution gets the request body producers to wait on the gate.
    @Test
    func resumptionOnly_doesNotGateTheRequestBody() {
        let resumptionOnly = Internals.TransferControl(
            resumption: DownloadResumptionPolicy.enabled().resumption,
            allowsSuspension: false
        )

        #expect(resumptionOnly.uploadGate == nil)
        #expect(Internals.TransferControl().uploadGate != nil)
    }
}
