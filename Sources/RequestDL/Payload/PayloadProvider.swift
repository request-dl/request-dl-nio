/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Protocol that defines the requirements for a body provider.

 - Note: A body provider must provide the data that will be sent in the request body.
*/
public protocol PayloadProvider {

    /// The data that will be sent in the request body.
    var data: Data { get }
}
