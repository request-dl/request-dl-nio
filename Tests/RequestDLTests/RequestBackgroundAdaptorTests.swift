/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class RequestBackgroundAdaptorTests: XCTestCase {

    func testBackgroundAdaptor() async {
        // Given
        let backgroundAdaptor = RequestBackgroundAdaptor()
        let backgroundService = BackgroundService.shared
        var backgroundCalled = false

        // When
        backgroundAdaptor.wrappedValue = { _ in
            backgroundCalled = true
        }

        backgroundService.completionHandler?("")

        // Then
        XCTAssertTrue(backgroundCalled)
    }
}
