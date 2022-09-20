import Foundation

public protocol Target {

    associatedtype HTTPSession: Request
    associatedtype Path: Request
    associatedtype HTTPMethod: Request
    associatedtype HTTPHeaders: Request
    associatedtype Body: Request

    var session: HTTPSession { get }
    var path: Path { get }
    var method: HTTPMethod { get }
    var headers: HTTPHeaders { get }
    var body: Body { get }
}

public extension Target {

    var session: some Request {
        Session(.default)
    }

    var method: some Request {
        Method(.get)
    }

    var headers: some Request {
        Group {
            Headers.Accept(.json)
            Headers.ContentType(.json)
        }
    }

    var body: some Request {
        EmptyRequest()
    }
}

extension Target {

    @RequestBuilder
    func reduced() -> some Request {
        session
        path
        method
        headers
        body
    }
}
