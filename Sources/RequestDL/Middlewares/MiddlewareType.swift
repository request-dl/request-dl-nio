import Foundation

public protocol MiddlewareType {

    associatedtype Element

    func received(_ result: Result<Element, Error>)
}
