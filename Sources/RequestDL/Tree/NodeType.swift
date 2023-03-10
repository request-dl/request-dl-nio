/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol NodeType: AnyObject {

    var children: [NodeType] { get set }

    func fetchObject() -> NodeObject?
}
