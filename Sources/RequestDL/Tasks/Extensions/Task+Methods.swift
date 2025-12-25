/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

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

        for index in 0 ..< times {
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

    /**
     A convenience method to send a simple ping request to the server and wait for the result.

     - Parameters:
        - times: Number of times the ping should be sent. Default value is 1.
        - debug: A flag to indicate whether or not to print debug information. Default value is true.

     - Throws: An error if the ping request fails.

     - Returns: Nothing. This function only waits for the server to respond to the ping request.
     */
    @available(*, deprecated, renamed: "ping(_:logger:)")
    @_disfavoredOverload
    public func ping(_ times: Int = 1, debug: Bool = true) async throws {
        if times <= 0 {
            return
        }

        for index in 0 ..< times {
            #if DEBUG
            if debug {
                print("Pinging \(index + 1) started")
            }
            #endif

            let time = Date()
            _ = try await result()

            #if DEBUG
            if debug {
                let interval = Date().timeIntervalSince(time)

                print("Pinging \(index + 1) success \(String(format: "%0.3f", interval))s")
            }
            #endif
        }
    }
}
