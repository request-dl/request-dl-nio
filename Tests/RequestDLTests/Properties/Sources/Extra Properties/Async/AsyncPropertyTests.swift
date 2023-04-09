/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class AsyncPropertyTests: XCTestCase {

    func testAsyncProperty() async throws {
        // Given
        var apiKey: String? {
            get async {
                "123ddf4"
            }
        }

        // When
        let (_, request) = try await resolve(TestProperty {
            AsyncProperty {
                if let apiKey = await apiKey {
                    Authorization(.bearer, token: apiKey)
                }
            }
        })

        // Then
        XCTAssertEqual(request.headers.getValue(forKey: "Authorization"), "Bearer 123ddf4")
    }

    func testNeverBody() async throws {
        // Given
        let property = AsyncProperty {
            EmptyProperty()
        }

        // Then
        try await assertNever(property.body)
    }
}
