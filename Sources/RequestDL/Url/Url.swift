import Foundation

/**
 The Url is the only way to specify the request URL. We have some methods available
 to build the URL in the best way, according to the needs of each developer.

     struct AppleDeveloperURL: Request {

         var body: some Request {
             Url("https://developer.apple.com")
         }
     }
 */
public struct Url: Request {

    public typealias Body = Never

    let `protocol`: Protocol?
    let path: String

    /**
     Defines the URL based on a String.

     - Parameters:
        - path: The URL path in String.

     Use `Url(_:)` when you want to set the base URL or part of it and
     return as a Url type. This implementation does not check the content,
     so it is safe to create URLs with String objects.

     As per the example below:

         struct AppleDeveloperURL: Request {

             var body: some Request {
                 Url("https://developer.apple.com")
             }
         }
     */
    public init(_ path: String) {
        self.protocol = nil
        self.path = path
    }

    /**
     Creates a URL by combining the HTTP communication protocol and the path in String.

     - Parameters:
        - protocol: The HTTP communication protocol;
        - path: The URL path in String.

     The separation of the protocol from the URL path does not reflect in better performance
     or safety of use, it is only considered as another way of specifying a URL.

     As per the example below:

         import RequestDL

         struct AppleDeveloperURL: Request {

             var body: some Request {
                 Url(.https, path: "developer.apple.com")
             }
         }
     */
    public init(_ `protocol`: Protocol, path: String) {
        self.protocol = `protocol`
        self.path = path
    }

    public var body: Body {
        Never.bodyException()
    }
}

extension Url {

    var absoluteString: String {
        "\(`protocol`.map { "\($0.rawValue)://" } ?? "")\(path)"
    }
}

/**
 Combines two Urls.

 - Parameters:
    - lhs: The left Url to be concatenated;
    - rhs: The right Url to match.

 - Returns: New Url combining left and right Url.

 Use this to combine multiple Urls without losing context. You can create multiple
 functions to return a path to the user's profile, or a path to payments, or others.
 After that, use the plus operator to match the base Url with the path Urls without
 losing context.

 As example below:

     import RequestDL

     struct AppleDeveloper: Request {

         private let path: AppleDeveloperPath

         var body: some Request {
             switch path {
             case .wwdc22:
                 baseURL + Url("/wwdc22")
             case .swiftPlaygrounds:
                 baseURL + Url("/swift-playgrounds")
             case .appStore:
                 baseURL + Url("/app-store/whats-new")
             }
         }
     }

     extension AppleDeveloper {

         var baseURL: Url {
             Url(.https, path: "developer.apple.com")
         }
     }
 */
public func + (_ lhs: Url, _ rhs: Url) -> Url {
    let combinedPath = lhs.path.appending(rhs.path)

    if let `protocol` = lhs.protocol {
        return Url(`protocol`, path: combinedPath)
    }

    return Url(combinedPath)
}

/**
 Combine Url and String to create a new Url.

 - Parameters:
    - lhs: The left Url to be concatenated.
    - complementaryPath: The complementary path in String.

 - Returns: New Url by adding the left Url with the complementary path.

 This method combines the Url with the complementary path. Depending on the
 implementation, some errors may occur because this method does not add / between
 the concatenated paths.

 Use this method to add parts of the endpoints.

 As an example:

     import RequestDL

     struct WWDC22Website: Request {

         var body: some Request {
             Url(.https, path: "developer.apple.com") + "/wwdc22"
         }
     }
 */
public func + (
    _ url: Url,
    _ complementaryPath: String
) -> Url {
    let combinedPath = url.path.appending(complementaryPath)

    if let `protocol` = url.protocol {
        return Url(`protocol`, path: combinedPath)
    }

    return Url(combinedPath)
}

extension Url: Equatable {

    public static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.absoluteString == rhs.absoluteString
    }
}

extension Url: PrimitiveRequest {

    struct Object: NodeObject {

        let url: URL

        init(_ url: URL) {
            self.url = url
        }

        func makeRequest(_ request: inout URLRequest, configuration: inout URLSessionConfiguration, delegate: DelegateProxy) {}
    }

    func makeObject() -> Object {
        guard let url = URL(string: absoluteString) else {
            fatalError()
        }

        return .init(url)
    }
}
