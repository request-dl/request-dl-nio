/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import Logging
@testable import RequestDL

class ModifiersLoggerTests: XCTestCase {

    private struct LogCaptureProperty: Property {
        @PropertyEnvironment(\.logger) var logger

        let closure: @Sendable (Logger) -> Void

        var body: some Property {
            BaseURL(baseURL())
        }

        private func baseURL() -> String {
            closure(logger)
            return "developers.apple.com"
        }
    }

    func testLogger_whenNotSet() async throws {
        // Given
        let expectation = expectation(description: "logger")
        let logger = SendableBox<Logger?>(nil)

        // When
        _ = try await MockedTask(content: {
            LogCaptureProperty {
                logger($0)
                expectation.fulfill()
            }
        })
        .result()

        // Then
        await _fulfillment(of: [expectation])

        XCTAssertEqual(logger()?.label, Logger.disabled.label)
    }

    func testLogger_whenSet() async throws {
        // Given
        let expectation = expectation(description: "logger")
        let logger = SendableBox<Logger?>(nil)
        let customLogger = Logger(label: "custom")

        // When
        _ = try await MockedTask(content: {
            LogCaptureProperty {
                logger($0)
                expectation.fulfill()
            }
        })
        .logger(customLogger)
        .result()

        // Then
        await _fulfillment(of: [expectation])

        XCTAssertEqual(logger()?.label, customLogger.label)
    }
}
