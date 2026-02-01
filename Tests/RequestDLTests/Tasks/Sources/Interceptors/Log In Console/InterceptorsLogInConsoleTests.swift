/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import Logging
@testable import RequestDL

struct InterceptorsLogInConsoleTests {

    @Test
    func consoleTaskResult() async throws {
        // Given
        let data = Data("Hello World!".utf8)
        let records = InlineProperty(wrappedValue: [TestLogHandler.LogRecord]())
        let expectation = AsyncSignal()

        let result = try await Logger.withTesting {
            records.wrappedValue += [$0]
            expectation.signal()
        } perform: {
            // When
            let result = try await MockedTask(content: {
                BaseURL("localhost")
                Payload(data: data)
            })
            .collectData()
            .logInConsole(true)
            .result()

            await expectation.wait()

            return result
        }

        // Then
        #expect(records.wrappedValue.last?.description.contains(
            """
            Head: \(result.head)
            
            \(String(data: data, encoding: .utf8) ?? "")
            """
            ) ?? false
        )
    }

    @Test
    func consoleData() async throws {
        // Given
        let data = Data("Hello World!".utf8)
        let records = InlineProperty(wrappedValue: [TestLogHandler.LogRecord]())
        let expectation = AsyncSignal()

        _ = try await Logger.withTesting {
            records.wrappedValue += [$0]
            expectation.signal()
        } perform: {
            // When
            let result = try await MockedTask(content: {
                BaseURL("localhost")
                Payload(data: data)
            })
            .collectData()
            .extractPayload()
            .logInConsole(true)
            .result()

            await expectation.wait()

            return result
        }

        // Then
        #expect(records.wrappedValue.last?.description.contains(
            """
            \(String(data: data, encoding: .utf8) ?? "")
            """
        ) ?? false)
    }

    @Test
    func consoleDecoded() async throws {
        // Given
        let value = "Hello World!"
        let records = InlineProperty(wrappedValue: [TestLogHandler.LogRecord]())
        let expectation = AsyncSignal()

        _ = try await Logger.withTesting {
            records.wrappedValue += [$0]
            expectation.signal()
        } perform: {
            // When
            let data = try JSONEncoder().encode(value)

            let result = try await MockedTask(content: {
                BaseURL("localhost")
                Payload(data: data)
            })
            .collectData()
            .decode(String.self)
            .extractPayload()
            .logInConsole(true)
            .result()

            await expectation.wait()

            return result
        }

        // Then
        #expect(records.wrappedValue.last?.description.contains(
            "\(value)"
        ) ?? false)
    }
}
