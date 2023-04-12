/*
 See LICENSE for this package's licensing information.
 */

import Foundation

/**
 An enumeration that represents the context of a secure connection.

 `SecureConnectionContext` provides options to specify whether the secure connection is being used
 on the server or client side in Swift.
 */
public enum SecureConnectionContext {

    /// Indicates that the secure connection is being used on the server side.
    case server

    /// Indicates that the secure connection is being used on the client side.
    case client
}

extension SecureConnectionContext {

    func build() -> Internals.Session.Context {
        switch self {
        case .server:
            return .server
        case .client:
            return .client
        }
    }
}
