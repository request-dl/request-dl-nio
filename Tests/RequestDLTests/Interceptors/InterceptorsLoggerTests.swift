/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class InterceptorsLoggerTests: XCTestCase {

    func testConsoleTaskResult() async throws {
        // Given
        let data = Data("Hello World!".utf8)
        var strings = [String]()

        Print.replace { items, separator, _ in
            strings.append(
                items
                    .map { "\($0)" }
                    .joined(separator: separator)
            )
        }

        // When
        defer { Print.restoreRaise() }

        let result = try await MockedTask { data }
            .logInConsole(true)
            .result()

        // Then
        XCTAssertEqual(strings, [
            "[RequestDL] Response: \(result.response)",
            "[RequestDL] Data: \(String(data: data, encoding: .utf8) ?? "")"
        ])
    }

    func testConsoleData() async throws {
        // Given
        let data = Data("Hello World!".utf8)
        var strings = [String]()

        Print.replace { items, separator, _ in
            strings.append(
                items
                    .map { "\($0)" }
                    .joined(separator: separator)
            )
        }

        // When
        defer { Print.restoreRaise() }

        _ = try await MockedTask { data }
            .extractPayload()
            .logInConsole(true)
            .result()

        // Then
        XCTAssertEqual(strings, [
            "[RequestDL] Success: \(String(data: data, encoding: .utf8) ?? "")"
        ])
    }

    func testConsoleDecoded() async throws {
        // Given
        let value = "Hello World!"
        var strings = [String]()

        Print.replace { items, separator, _ in
            strings.append(
                items
                    .map { "\($0)" }
                    .joined(separator: separator)
            )
        }

        // When
        defer { Print.restoreRaise() }

        let data = try JSONEncoder().encode(value)

        _ = try await MockedTask { data }
            .decode(String.self)
            .extractPayload()
            .logInConsole(true)
            .result()

        // Then
        XCTAssertEqual(strings, [
            "[RequestDL] Success: \(value)"
        ])
    }
}
