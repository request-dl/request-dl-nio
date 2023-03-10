/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class PayloadProviderTests: XCTestCase {

    struct PayloadProviderMock: PayloadProvider {
        let data: Data

        init(_ data: Data) {
            self.data = data
        }
    }

    func testPayloadProvider() async throws {
        // Given
        let data = Data("foo".utf8)

        // When
        let payload = PayloadProviderMock(data)

        // Then
        XCTAssertEqual(payload.data, data)
    }
}
