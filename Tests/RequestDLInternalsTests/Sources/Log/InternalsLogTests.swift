//
// See LICENSE for this package's licensing information.
//

import Logging
import SwiftAsyncStream
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

struct InternalsLogTests {

    // MARK: - Static factories

    private enum SomeState { case idle }
    private enum SomePhase { case connecting }
    private struct SomeError: Error {}
    private struct SomeBundle {}

    @Test
    func unexpectedStateOrPhaseIncludesStatePhaseAndError() {
        // When
        // `state`/`phase`/`error` must be distinct concrete types: the metadata dictionary
        // keys them by `type(of:)`, so same-typed arguments collide and crash on construction.
        let log = Internals.Log.unexpectedStateOrPhase(
            state: SomeState.idle,
            phase: SomePhase.connecting,
            error: SomeError()
        )

        // Then
        #expect(log.message().description.contains("invalid state or phase"))
        #expect(log.metadata?().count == 3)
    }

    @Test
    func unexpectedStateOrPhaseWithoutErrorOmitsErrorMetadata() {
        // When
        let log = Internals.Log.unexpectedStateOrPhase(state: SomeState.idle, phase: SomePhase.connecting)

        // Then
        #expect(log.metadata?().count == 2)
    }

    @Test
    func cantCreateCertificateOutsideSecureConnectionHasNoMetadata() {
        // When
        let log = Internals.Log.cantCreateCertificateOutsideSecureConnection()

        // Then
        #expect(log.message().description.contains("outside of the allowed context"))
        #expect(log.metadata == nil)
    }

    @Test
    func cantOpenCertificateFileIncludesResourceAndBundleMetadata() {
        // When
        let log = Internals.Log.cantOpenCertificateFile("cert.pem", SomeBundle())

        // Then
        #expect(log.message().description.contains("Couldn't find"))
        #expect(log.metadata?().count == 2)
    }

    @Test
    func unexpectedGraphPathwayHasNoMetadata() {
        // When
        let log = Internals.Log.unexpectedGraphPathway()

        // Then
        #expect(log.message().description.contains("graph pathway"))
        #expect(log.metadata == nil)
    }

    // MARK: - init(_:) without metadata

    @Test
    func initWithoutMetadataLeavesMetadataNil() {
        // When
        let log = Internals.Log("plain message")

        // Then
        #expect(log.message().description == "plain message")
        #expect(log.metadata == nil)
    }

    // MARK: - log(level:logger:)

    @Test
    func logWithoutLoggerPrintsToConsole() {
        // Given
        let log = Internals.Log.cantCreateCertificateOutsideSecureConnection()

        // When / Then (no crash, falls through the `logger == nil` print branch)
        log.log(level: .error, logger: nil)
    }

    @Test
    func logWithLoggerForwardsMessageAndMetadata() async {
        // Given
        let captured = InlineProperty<TestLogHandler.LogRecord?>(wrappedValue: nil)
        let log = Internals.Log.cantOpenCertificateFile("cert.pem", SomeBundle())

        // When
        await Logger.withTestHandler(
            recorded: { captured.wrappedValue = $0 },
            perform: { logger in
                log.log(level: .error, logger: logger)
            }
        )

        // Then
        #expect(captured.wrappedValue?.level == .error)
        #expect(captured.wrappedValue?.metadata.isEmpty == false)
    }

    // MARK: - assertionFailure(logger:) / logMetadata(logger:)

    @Test
    func assertionFailureWithMetadataAndLoggerLogsMetadataThenAsserts() async {
        // Given
        let capturedMetadata = InlineProperty<TestLogHandler.LogRecord?>(wrappedValue: nil)
        let capturedAssertion = InlineProperty<String?>(wrappedValue: nil)
        let log = Internals.Log.cantOpenCertificateFile("cert.pem", SomeBundle())

        // When
        await Logger.withTestHandler(
            recorded: { capturedMetadata.wrappedValue = $0 },
            perform: { logger in
                Internals.Override.AssertionFailure.replace { message, _, _ in
                    capturedAssertion.wrappedValue = message
                } perform: {
                    log.assertionFailure(logger: logger)
                }
            }
        )

        // Then
        // `logMetadata` embeds the metadata description straight into the log message rather
        // than passing it through `Logger.Metadata`, so it shows up on `record.message`.
        #expect(capturedMetadata.wrappedValue?.message.description.contains("cert.pem") == true)
        #expect(capturedAssertion.wrappedValue?.contains("Couldn't find") == true)
    }

    @Test
    func assertionFailureWithoutMetadataSkipsMetadataLogging() {
        // Given
        let capturedAssertion = InlineProperty<String?>(wrappedValue: nil)
        let log = Internals.Log("plain message")

        // When
        Internals.Override.AssertionFailure.replace { message, _, _ in
            capturedAssertion.wrappedValue = message
        } perform: {
            log.assertionFailure(logger: nil)
        }

        // Then
        #expect(capturedAssertion.wrappedValue == "🐞 RequestDL bug: plain message")
    }
}
