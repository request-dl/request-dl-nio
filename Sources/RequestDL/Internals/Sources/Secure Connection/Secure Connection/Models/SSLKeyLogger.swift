/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

/**
 A protocol for implementing `SSLKEYLOGFILE` support.

 `SSLKeyLogger` defines a method that can be used to log keys in the format expected by
 tools that support the `SSLKEYLOGFILE`.
 */
public protocol SSLKeyLogger: Sendable, AnyObject {

    /**
     Function for logging keys in the format expected by tools that support the
     `SSLKEYLOGFILE`.

     - Parameter bytes: The bytes to be logged.
     */
    func callAsFunction(_ bytes: ByteBuffer)
}
