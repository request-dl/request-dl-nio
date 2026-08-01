//
// See LICENSE for this package's licensing information.
//

import Logging

#if canImport(FoundationEssentials)
import struct FoundationEssentials.Date
#else
import struct Foundation.Date
#endif

extension RequestTask {

    /**
     A convenience method to send a simple ping request to the server and wait for the response.

     - Parameters:
        - times: Number of times the ping should be sent. Must be greater than zero. Default is `1`.
        - logger: An optional `Logger` used to record timing and lifecycle events for each ping attempt.
                  Log messages are emitted at the `.debug` level and will only appear if the logger’s
                  effective log level includes `.debug` (e.g., in debug builds or when explicitly enabled).

     - Throws: An error if any ping request fails (i.e., if the underlying `result()` call throws).

     - Returns: `Void`. This method does not return data—it only ensures the request completes successfully.
     */
    public func ping(_ times: Int = 1, logger: Logger? = nil) async throws {
        if times <= 0 {
            return
        }

        for index in 0..<times {
            logger?.debug("Pinging \(index + 1) started")

            let time = Date()

            if let logger {
                _ = try await self.logger(logger).result()
            } else {
                _ = try await result()
            }

            let interval = Date().timeIntervalSince(time)
            logger?.debug("Pinging \(index + 1) succeeded in \(String(format: "%.3f", interval))s")
        }
    }
}
