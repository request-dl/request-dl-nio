import Foundation

protocol NodeType: AnyObject {

    var children: [NodeType] { get set }

    func fetchObject() -> NodeObject?
}
