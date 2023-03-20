/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

public protocol TaskResultPrimitive {

    var head: ResponseHead { get }
}

public struct TaskResult<Element>: TaskResultPrimitive {

    public let head: ResponseHead

    public let payload: Element

    public init(
        head: ResponseHead,
        payload: Element
    ) {
        self.head = head
        self.payload = payload
    }
}
