/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A protocol used to define the properties and methods required for a PSK type.
 */
@available(*, deprecated, renamed: "SSLPSKClientIdentityResolver")
public protocol PSKType {}

/**
 A structure representing the PSK server type.
 */
@available(*, deprecated, renamed: "SSLPSKServerIdentityResolver")
public struct PSKServer: PSKType {}

/**
 A structure representing the PSK client type.
 */
@available(*, deprecated, renamed: "SSLPSKClientIdentityResolver")
public struct PSKClient: PSKType {}

@available(*, deprecated)
extension PSKType where Self == PSKServer {

    /**
     A static property that returns an instance of PSKServer.

     - Returns: An instance of PSKServer.
     */
    @available(*, deprecated, renamed: "SSLPSKServerIdentityResolver")
    public static var server: PSKServer {
        .init()
    }
}

@available(*, deprecated)
extension PSKType where Self == PSKClient {

    /**
     A static property that returns an instance of PSKClient.

     - Returns: An instance of PSKClient.
     */
    @available(*, deprecated, renamed: "SSLPSKClientIdentityResolver")
    public static var client: PSKClient {
        .init()
    }
}
