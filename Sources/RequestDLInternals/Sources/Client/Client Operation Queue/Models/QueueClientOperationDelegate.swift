//
// See LICENSE for this package's licensing information.
//

package protocol QueueClientOperationDelegate: Sendable, AnyObject {

    func operationDidComplete(_ operation: Internals.ClientOperation)
}
