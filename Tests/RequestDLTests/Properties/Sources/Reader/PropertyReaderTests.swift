/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct PropertyReaderTests {

    @Test
    func example() async throws {
        for _ in 1 ... 5 {
            let content = PropertyGroup {
                BaseURL(.https, host: "apple.com:1090")
                CustomHeader(name: "Authorization", value: UUID().uuidString)
                ReferenceMemoryProperty()
            }

            let resolved = try await resolve(TestProperty {
                PropertyReader(content) { context in
                    if context.requestConfiguration.url.contains("apple.com:1090") {
                        BaseURL(.http, host: "google.com")
                    }

                    if context.requestConfiguration.headers.contains(name: "Authorization") {
                        Authorization(.bearer, token: UUID().uuidString)
                    }
                }
            })

            #expect(resolved.requestConfiguration.url == "http://google.com?counter=0")
            #expect(
                resolved.requestConfiguration.headers.contains(name: "Authorization") {
                    $0.hasPrefix("Bearer")
                }
            )

            try await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
        }

        let resolved = try await resolve(ReferenceMemoryProperty())

        #expect(resolved.requestConfiguration.url.contains("counter=0"))
    }
}

struct ReferenceMemoryProperty: Property {

    @StoredObject private var object = MemoryReference()

    var body: some Property {
        Query(name: "counter", value: object.counter)
    }
}

private final class MemoryReference: Sendable {

    let counter: Int

    init() {
        counter = ReadCounter.shared.counter
    }
}

private final class ReadCounter: @unchecked Sendable {

    static let shared = ReadCounter()

    var counter: Int {
        lock.withLock {
            let counter = _counter
            _counter += 1
            return counter
        }
    }

    private let lock = Lock()

    private var _counter: Int = .zero
}
