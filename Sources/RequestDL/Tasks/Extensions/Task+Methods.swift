/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Task {

    /**
     A convenience method to send a simple ping request to the server and wait for the result.

     - Parameters:
        - times: Number of times the ping should be sent. Default value is 1.
        - debug: A flag to indicate whether or not to print debug information. Default value is true.

     - Throws: An error if the ping request fails.

     - Returns: Nothing. This function only waits for the server to respond to the ping request.
     */
    public func ping(_ times: Int = 1, debug: Bool = true) async throws {
        guard times > 0 else {
            Internals.Log.failure(
                .timesShouldBeGreaterThanZero(times)
            )
        }

        for index in 0 ..< times {
            if debug {
                Internals.Log.debug("Pinging \(index + 1) started")
            }

            let time = Date()
            _ = try await result()

            if debug {
                let interval = Date().timeIntervalSince(time)

                Internals.Log.debug("Pinging \(index + 1) success \(String(format: "%0.3f", interval))s")
            }
        }
    }
}
