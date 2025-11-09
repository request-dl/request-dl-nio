/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InterceptorsLogInConsoleTests {

    @Test
    func consoleTaskResult() async throws {
        // Given
        let data = Data("Hello World!".utf8)
        let strings = SendableBox([String]())

        try await Internals.Override.Print.replace { separator, _, items in
            strings(
                strings() + [items
                    .map { "\($0)" }
                    .joined(separator: separator)]
            )
        } perform: {
            // When
            let result = try await MockedTask(content: {
                BaseURL("localhost")
                Payload(data: data)
            })
                .collectData()
                .logInConsole(true)
                .result()

            // Then
            #expect(strings().first?.contains(
                """
                Head: \(result.head)
                
                \(String(data: data, encoding: .utf8) ?? "")
                """
                ) ?? false
            )
        }
    }

    @Test
    func consoleData() async throws {
        // Given
        let data = Data("Hello World!".utf8)
        let strings = SendableBox([String]())

        try await Internals.Override.Print.replace { separator, _, items in
            strings(
                strings() + [items
                    .map { "\($0)" }
                    .joined(separator: separator)]
            )
        } perform: {
            // When
            _ = try await MockedTask(content: {
                BaseURL("localhost")
                Payload(data: data)
            })
            .collectData()
            .extractPayload()
            .logInConsole(true)
            .result()

            // Then
            #expect(strings().first?.contains(
                """
                
                \(String(data: data, encoding: .utf8) ?? "")
                """
            ) ?? false)
        }
    }

    @Test
    func consoleDecoded() async throws {
        // Given
        let value = "Hello World!"
        let strings = SendableBox([String]())

        try await Internals.Override.Print.replace { separator, _, items in
            strings(
                strings() + [items
                    .map { "\($0)" }
                    .joined(separator: separator)]
            )
        } perform: {
            // When
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
            #expect(strings().first?.contains(
                "\(value)"
            ) ?? false)
        }
    }
}
