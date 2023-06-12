/*
 See LICENSE for this package's licensing information.
*/

import XCTest

extension XCTestCase {

    func _fulfillment(
        of expectations: [XCTestExpectation],
        timeout seconds: TimeInterval = .infinity,
        enforceOrder enforceOrderOfFulfillment: Bool = false
    ) async {
        await withUnsafeContinuation { continuation in
            wait(
                for: expectations,
                timeout: seconds,
                enforceOrder: enforceOrderOfFulfillment
            )

            continuation.resume()
        }
    }
}
