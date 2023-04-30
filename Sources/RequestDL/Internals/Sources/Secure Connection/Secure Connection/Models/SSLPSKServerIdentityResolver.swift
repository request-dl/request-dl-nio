/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/**
 A protocol for resolving pre-shared key server identities.

 `SSLPSKServerIdentityResolver` defines a function that can be used to resolve a
 pre-shared key server identity based on given client hint and identity.
 */
@available(*, deprecated, message: "RequestDL is for client-side usage only")
public protocol SSLPSKServerIdentityResolver: Sendable, AnyObject {

    /**
     Callback function for resolving a pre-shared key server identity.

     - Parameters:
        - hint: A hint used to identify the pre-shared key identity for the server.
        - clientIdentity: The identity of the client.

     - Returns: A `PSKServerIdentityResponse` object containing the resolved identity.

     - Throws: An error if the identity cannot be resolved.
     */
    func callAsFunction(
        _ hint: String,
        client identity: String
    ) throws -> PSKServerIdentityResponse
}
