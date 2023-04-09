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

        Internals.Override.Print.replace { separator, _, items in
            strings.append(
                items
                    .map { "\($0)" }
                    .joined(separator: separator)
            )
        }

        // When
        defer { Internals.Override.Print.restoreRaise() }

        let result = try await MockedTask { data }
            .logInConsole(true)
            .result()

        // Then
        XCTAssertTrue(strings.first?.contains(
            """
            Head: \(result.head)
            Payload: \(String(data: data, encoding: .utf8) ?? "")
            """
        ) ?? false)
    }

    func testConsoleData() async throws {
        // Given
        let data = Data("Hello World!".utf8)
        var strings = [String]()

        Internals.Override.Print.replace { separator, _, items in
            strings.append(
                items
                    .map { "\($0)" }
                    .joined(separator: separator)
            )
        }

        // When
        defer { Internals.Override.Print.restoreRaise() }

        _ = try await MockedTask { data }
            .extractPayload()
            .logInConsole(true)
            .result()

        // Then
        XCTAssertTrue(strings.first?.contains(
            """
            Success: \(String(data: data, encoding: .utf8) ?? "")
            """
        ) ?? false)
    }

    func testConsoleDecoded() async throws {
        // Given
        let value = "Hello World!"
        var strings = [String]()

        Internals.Override.Print.replace { separator, _, items in
            strings.append(
                items
                    .map { "\($0)" }
                    .joined(separator: separator)
            )
        }

        // When
        defer { Internals.Override.Print.restoreRaise() }

        let data = try JSONEncoder().encode(value)

        _ = try await MockedTask { data }
            .decode(String.self)
            .extractPayload()
            .logInConsole(true)
            .result()

        // Then
        XCTAssertTrue(strings.first?.contains(
            "Success: \(value)"
        ) ?? false)
    }
}
