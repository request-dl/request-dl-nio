/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

/**
 A protocol for resolving pre-shared key client identities.

 ``SSLPSKIdentityResolver`` defines a function that can be used to resolve
 a pre-shared key client identity based on a given hint.
 */
public protocol SSLPSKIdentityResolver: Sendable, AnyObject {

    /**
     Function for resolving a pre-shared key client identity.

     - Parameter context: PSK Client Context with hint used to identify the pre-shared key identity.

     - Returns: A `PSKClientIdentityResponse` object containing the resolved identity.

     - Throws: An error if the identity cannot be resolved.
     */
    func callAsFunction(_ context: PSKClientContext) throws -> PSKClientIdentityResponse
}
