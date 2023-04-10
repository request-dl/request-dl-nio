/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A protocol used to define the properties and methods required for a PSK type.
 */
public protocol PSKType {}

/**
 A structure representing the PSK server type.
 */
public struct PSKServer: PSKType {}

/**
 A structure representing the PSK client type.
 */
public struct PSKClient: PSKType {}

extension PSKType where Self == PSKServer {

    /**
     A static property that returns an instance of PSKServer.

     - Returns: An instance of PSKServer.
     */
    public static var server: PSKServer {
        .init()
    }
}

extension PSKType where Self == PSKClient {
    
    /**
     A static property that returns an instance of PSKClient.
     
     - Returns: An instance of PSKClient.
     */
    public static var client: PSKClient {
        .init()
    }
}
