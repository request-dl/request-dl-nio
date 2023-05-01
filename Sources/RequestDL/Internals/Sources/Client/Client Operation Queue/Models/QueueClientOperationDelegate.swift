/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@HTTPClientActor
protocol QueueClientOperationDelegate: AnyObject {

    func operationDidComplete(_ operation: Internals.ClientOperation)
}
