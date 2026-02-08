/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct AsyncPropertyTests {

    @Test
    func asyncProperty() async throws {
        // Given
        var apiKey: String? {
            get async {
                "123ddf4"
            }
        }

        // When
        let resolved = try await resolve(TestProperty {
            AsyncProperty {
                if let apiKey = await apiKey {
                    Authorization(.bearer, token: apiKey)
                }
            }
        })

        // Then
        #expect(
            resolved.requestConfiguration.headers["Authorization"] == ["Bearer 123ddf4"]
        )
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = AsyncProperty {
            EmptyProperty()
        }

        // Then
        try await assertNever(property.body)
    }
}
