//
// See LICENSE for this package's licensing information.
//

protocol IndexFactory: Sendable, AnyObject {

    var rawValue: Int { get }

    init()
}
