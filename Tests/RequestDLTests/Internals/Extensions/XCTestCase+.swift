/*
 See LICENSE for this package's licensing information.
*/

#if swift(<5.8) || !canImport(Darwin)
import XCTest

extension XCTestCase {

    func fulfillment(
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
