//
// See LICENSE for this package's licensing information.
//

import Testing

@_spi(Private) @testable import RequestDL

/// What `.resumingUploads(...)` asks for, read back off the environment it sets, without running
/// anything.
struct ResumingUploadsModifierTests {

    // MARK: - Private types

    /// A task that runs nothing and answers with what the environment says about resumable uploads.
    private struct Probe: RequestTask {

        func result() async throws -> ResumableUploadSetup? {
            try await _result(environment: RequestEnvironmentValues())
        }

        func _result(environment: RequestEnvironmentValues) async throws -> ResumableUploadSetup? {
            environment.resumableUploadSetup
        }
    }

    // MARK: - Tests

    @Test
    func aTaskThatIsNotMadeResumable_hasNoSetup() async throws {
        #expect(try await Probe().result() == nil)
    }

    @Test
    func withNoArguments_isTheIETFProtocol_withTheDefaults() async throws {
        // When
        let setup = try #require(try await Probe().resumingUploads().result())

        // Then
        #expect(setup.dialect is IETFResumableUploadDialect)
        #expect(setup.maximumAttemptsWithoutProgress == 3)
        #expect(setup.delay == 1_000_000_000)
        #expect(setup.cancellation == .terminate)
    }

    @Test
    func theProtocolIsChosenBySayingItsName() async throws {
        // When
        let ietf = try #require(try await Probe().resumingUploads(.ietf).result())
        let tus = try #require(try await Probe().resumingUploads(.tus).result())
        let explicit = try #require(try await Probe().resumingUploads(TUSResumableUpload()).result())

        // Then
        #expect(ietf.dialect is IETFResumableUploadDialect)
        #expect(tus.dialect is TUSResumableUploadDialect)
        #expect(explicit.dialect is TUSResumableUploadDialect)
    }

    @Test
    func theBudgetAndTheDelayAreWhatWasAsked() async throws {
        // When
        let setup = try #require(
            try await Probe()
                .resumingUploads(
                    .tus,
                    maximumAttemptsWithoutProgress: 7,
                    delay: 0.25,
                    onCancellation: .keepOnServer
                )
                .result()
        )

        // Then
        #expect(setup.maximumAttemptsWithoutProgress == 7)
        #expect(setup.delay == 250_000_000)
        #expect(setup.cancellation == .keepOnServer)
    }

    @Test
    func nonsenseValues_areClamped() async throws {
        // When
        let setup = try #require(
            try await Probe()
                .resumingUploads(maximumAttemptsWithoutProgress: -4, delay: -2)
                .result()
        )

        // Then: at least one attempt, and no waiting for a negative time.
        #expect(setup.maximumAttemptsWithoutProgress == 1)
        #expect(setup.delay == 0)
    }

    @Test
    func aDelayTooLongToCount_isAsLongAsThereIs() async throws {
        // When
        let setup = try #require(try await Probe().resumingUploads(delay: .greatestFiniteMagnitude).result())

        // Then
        #expect(setup.delay == .max)
    }

    @Test
    func whenSeveralAreChained_theOneClosestToTheTaskWins() async throws {
        // When
        let setup = try #require(
            try await Probe()
                .resumingUploads(.tus)
                .resumingUploads(.ietf)
                .result()
        )

        // Then: each sets it on the way down, so the inner one is the last to.
        #expect(setup.dialect is TUSResumableUploadDialect)
    }
}
