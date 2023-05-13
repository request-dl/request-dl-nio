/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class _EitherContentTests: XCTestCase {

    func testConditionalFirstBuilder() async throws {
        // Given
        let chooseFirst = true

        @PropertyBuilder
        var result: some Property {
            if chooseFirst {
                BaseURL("google.com")
            } else {
                Headers.Origin("https://apple.com")
            }
        }

        // When
        let resolved = try await resolve(result)

        // Then
        XCTAssertTrue(result is _EitherContent<BaseURL, RequestDL.Headers.Origin>)
        XCTAssertEqual(resolved.request.url, "https://google.com")
        XCTAssertTrue(resolved.request.headers.isEmpty)
    }

    func testConditionalSecondBuilder() async throws {
        // Given
        let chooseFirst = false

        @PropertyBuilder
        var result: some Property {
            if chooseFirst {
                Headers.Origin("https://apple.com")
            } else {
                BaseURL("127.0.0.1")
            }
        }

        // When
        let resolved = try await resolve(result)

        // Then
        XCTAssertTrue(result is _EitherContent<RequestDL.Headers.Origin, BaseURL>)
        XCTAssertEqual(resolved.request.url, "https://127.0.0.1")
        XCTAssertTrue(resolved.request.headers.isEmpty)
    }

    func testNeverBody() async throws {
        // Given
        let property = _EitherContent<EmptyProperty, EmptyProperty>(first: .init())

        // Then
        try await assertNever(property.body)
    }
}

func assertNever<T>(_ closure: @autoclosure @escaping () throws -> T) async throws {
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
