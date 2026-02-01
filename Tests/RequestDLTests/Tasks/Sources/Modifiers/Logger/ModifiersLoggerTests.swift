/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import Logging
@testable import RequestDL

struct ModifiersLoggerTests {

    private struct LogCaptureProperty: Property {
        @PropertyEnvironment(\.logger) var logger

        let closure: @Sendable (Logger?) -> Void

        var body: some Property {
            BaseURL(baseURL())
        }

        private func baseURL() -> String {
            closure(logger)
            return "developers.apple.com"
        }
    }

    @Test
    func logger_whenNotSet() async throws {
        // Given
        let expectation = AsyncSignal()
        let logger = InlineProperty<Logger?>(wrappedValue: nil)

        // When
        _ = try await MockedTask(content: {
            LogCaptureProperty {
                logger.wrappedValue = $0
                expectation.signal()
            }
        })
        .result()

        // Then
        await expectation.wait()

        #expect(logger.wrappedValue?.label == nil)
    }

    @Test
    func logger_whenSet() async throws {
        // Given
        let expectation = AsyncSignal()
        let logger = InlineProperty<Logger?>(wrappedValue: nil)
        let customLogger = Logger(label: "custom")

        // When
        _ = try await MockedTask(content: {
            LogCaptureProperty {
                logger.wrappedValue = $0
                expectation.signal()
            }
        })
        .logger(customLogger)
        .result()

        // Then
        await expectation.wait()

        #expect(logger.wrappedValue?.label == customLogger.label)
    }
}
