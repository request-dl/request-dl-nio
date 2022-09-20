import Foundation

// swiftlint:disable type_name
public struct _StringBody: BodyProvider {

    private let string: String
    private let encoding: String.Encoding

    init(
        _ string: String,
        using encoding: String.Encoding
    ) {
        self.string = string
        self.encoding = encoding
    }

    public var data: Data {
        string.data(using: encoding) ?? Data()
    }
}
