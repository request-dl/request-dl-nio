/*
 See LICENSE for this package's licensing information.
*/

import XCTest

#if !canImport(Darwin)
extension XCTestCase {

    public func fulfillment(
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
#endif
