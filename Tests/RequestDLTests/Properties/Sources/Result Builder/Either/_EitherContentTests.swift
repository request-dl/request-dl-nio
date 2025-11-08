/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct _EitherContentTests {

    @Test
    func conditionalFirstBuilder() async throws {
        // Given
        let chooseFirst = true

        @PropertyBuilder
        var result: some Property {
            if chooseFirst {
                BaseURL("google.com")
            } else {
                OriginHeader("https://apple.com")
            }
        }

        // When
        let resolved = try await resolve(result)

        // Then
        #expect(result is _EitherContent<BaseURL, OriginHeader>)
        #expect(resolved.request.url == "https://google.com")
        #expect(resolved.request.headers.isEmpty)
    }

    @Test
    func conditionalSecondBuilder() async throws {
        // Given
        let chooseFirst = false

        @PropertyBuilder
        var result: some Property {
            if chooseFirst {
                OriginHeader("https://apple.com")
            } else {
                BaseURL("127.0.0.1")
            }
        }

        // When
        let resolved = try await resolve(result)

        // Then
        #expect(result is _EitherContent<OriginHeader, BaseURL>)
        #expect(resolved.request.url == "https://127.0.0.1")
        #expect(resolved.request.headers.isEmpty)
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = _EitherContent<EmptyProperty, EmptyProperty>(first: .init())

        // Then
        try await assertNever(property.body)
    }
}

func assertNever<T>(_ closure: @autoclosure @escaping @Sendable () throws -> T) async throws {
    try await withUnsafeThrowingContinuation { continuation in
        Internals.Override.FatalError.replace { message, file, line in
            Internals.Override.FatalError.restore()
            continuation.resume()
            Thread.exit()
            Swift.fatalError(message, file: file, line: line)
        }

        Thread {
            do {
                _ = try closure()
            } catch {
                continuation.resume(with: .failure(error))
            }
        }.start()
    }
}
