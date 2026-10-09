//
// See LICENSE for this package's licensing information.
//

#if canImport(Network)

import Foundation
import Network

/// Answers one HTTP/1.1 request on a connection of an `NWListener` with a fixed response, and
/// closes the connection.
///
/// A server that reads once, answers and cancels is not enough. A request can arrive in more
/// than one segment, more often on a loaded machine, and closing a socket that still holds
/// unread data resets the connection instead of ending it, which can make the client lose the
/// response it was just sent. The request is read up to the end of its head before the answer,
/// and the answer ends the stream with a final message, so the client sees the whole of it
/// followed by a normal close.
package enum SingleHTTPResponse {

    // MARK: - Package static methods

    /// - Parameters:
    ///   - connection: A connection that was started on `queue`.
    ///   - response: The bytes to send, head and body.
    ///   - delay: Seconds to hold the response back after the request arrived.
    ///   - queue: The queue the connection runs on.
    package static func serve(
        _ connection: NWConnection,
        with response: Data,
        after delay: TimeInterval = 0,
        on queue: DispatchQueue
    ) {
        receive(connection, received: Data(), response: response, delay: delay, queue: queue)
    }

    // MARK: - Private static methods

    private static func receive(
        _ connection: NWConnection,
        received: Data,
        response: Data,
        delay: TimeInterval,
        queue: DispatchQueue
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            var received = received

            if let data {
                received.append(data)
            }

            let hasWholeHead = received.range(of: Data("\r\n\r\n".utf8)) != nil

            guard hasWholeHead || isComplete || error != nil else {
                receive(connection, received: received, response: response, delay: delay, queue: queue)
                return
            }

            queue.asyncAfter(deadline: .now() + delay) {
                connection.send(
                    content: response,
                    contentContext: .finalMessage,
                    isComplete: true,
                    completion: .contentProcessed { _ in
                        connection.cancel()
                    }
                )
            }
        }
    }
}

#endif
