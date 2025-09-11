/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InterceptorsLogInConsoleTests: XCTestCase {

    func testConsoleTaskResult() async throws {
        // Given
        let data = Data("Hello World!".utf8)
        let strings = SendableBox([String]())

        Internals.Override.Print.replace { separator, _, items in
            strings(
                strings() + [items
                    .map { "\($0)" }
                    .joined(separator: separator)]
            )
        }

        // When
        defer { Internals.Override.Print.restore() }

        let result = try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .collectData()
        .logInConsole(true)
        .result()

        // Then
        XCTAssertTrue(strings().first?.contains(
            """
            Head: \(result.head)
            Payload: \(String(data: data, encoding: .utf8) ?? "")
            """
        ) ?? false)
    }

    func testConsoleData() async throws {
        // Given
        let data = Data("Hello World!".utf8)
        let strings = SendableBox([String]())

        Internals.Override.Print.replace { separator, _, items in
            strings(
                strings() + [items
                    .map { "\($0)" }
                    .joined(separator: separator)]
            )
        }

        // When
        defer { Internals.Override.Print.restore() }

        _ = try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .collectData()
        .extractPayload()
        .logInConsole(true)
        .result()

        // Then
        XCTAssertTrue(strings().first?.contains(
            """
            Success: \(String(data: data, encoding: .utf8) ?? "")
            """
        ) ?? false)
    }

    func testConsoleDecoded() async throws {
        // Given
        let value = "Hello World!"
        let strings = SendableBox([String]())

        Internals.Override.Print.replace { separator, _, items in
            strings(
                strings() + [items
                    .map { "\($0)" }
                    .joined(separator: separator)]
            )
        }

        // When
        defer { Internals.Override.Print.restore() }

        let data = try JSONEncoder().encode(value)

        _ = try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .collectData()
        .decode(String.self)
        .extractPayload()
        .logInConsole(true)
        .result()

        // Then
        XCTAssertTrue(strings().first?.contains(
            "Success: \(value)"
        ) ?? false)
    }
}
