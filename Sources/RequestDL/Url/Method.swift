import Foundation

/**
 Defines the request method.

     extension ProductsAPI {

         func get() -> AnyTask<Error> {
             Task {
                 BaseUrl() + "/products"
                 Method(.get)
             }
             .eraseToAnyTask()
         }
     }
 */
public struct Method: Request {

    public typealias Body = Never

    let methodType: MethodType

    /**
     Initializes with the type of request to be made

     - Parameters:
        - methodType: Requisition method

     In the example below, a GET request is made to the Apple developers website.

         extension AppleDevelopersAPI {

             func get() -> AnyTask<Error> {
                 Task {
                     Url(.https, path: "developer.apple.com")
                     Method(.get)
                 }
                 .eraseToAnyTask()
             }
         }
     */
    public init(_ methodType: MethodType) {
        self.methodType = methodType
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension Method: PrimitiveRequest {

    struct Object: NodeObject {

        private let httpMethod: String

        init(_ httpMethod: String) {
            self.httpMethod = httpMethod
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {
            request.httpMethod = httpMethod
        }
    }

    func makeObject() -> Object {
        .init(methodType.rawValue)
    }
}
