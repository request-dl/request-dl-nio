/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol QueueClientOperationDelegate: AnyObject, Sendable {

    func operationDidComplete(_ operation: Internals.ClientOperation)
}
