/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol QueueClientOperationDelegate: Sendable, AnyObject {

    func operationDidComplete(_ operation: Internals.ClientOperation)
}
