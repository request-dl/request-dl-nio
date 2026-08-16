//
// See LICENSE for this package's licensing information.
//

import Dispatch
import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#endif

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
        #expect(resolved.requestConfiguration.url == "https://google.com")
        #expect(resolved.requestConfiguration.headers.isEmpty)
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
        #expect(resolved.requestConfiguration.url == "https://127.0.0.1")
        #expect(resolved.requestConfiguration.headers.isEmpty)
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
        // A queue of its own, not `Task` and not the global concurrent queue. The override
        // below must never return — its signature is `-> Never`, matching the real
        // `fatalError` it stands in for — and the only portable way to make that true without
        // `Foundation`'s `Thread.exit()` is to park the thread it runs on forever. Parking a
        // `Task`'s cooperative-pool thread or a global queue's worker that way would starve
        // unrelated work; a queue nothing else shares can be blocked at no cost to anything
        // else.
        DispatchQueue(label: "RequestDL.assertNever").async {
            Internals.Override.FatalError.replace { message, file, line in
                continuation.resume()
                DispatchSemaphore(value: 0).wait()
                Swift.fatalError(message, file: file, line: line)
            } perform: {
                do {
                    _ = try closure()
                } catch {
                    continuation.resume(with: .failure(error))
                }
            }
        }
    }
}
