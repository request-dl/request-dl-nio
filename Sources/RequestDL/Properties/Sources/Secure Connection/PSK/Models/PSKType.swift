/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public protocol PSKType {}

public struct PSKServer: PSKType {}

public struct PSKClient: PSKType {}

extension PSKType where Self == PSKServer {

    public static var server: PSKServer {
        .init()
    }
}

extension PSKType where Self == PSKClient {

    public static var client: PSKClient {
        .init()
    }
}
