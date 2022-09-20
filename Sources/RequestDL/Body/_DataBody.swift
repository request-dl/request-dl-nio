import Foundation

// swiftlint:disable type_name
public struct _DataBody: BodyProvider {

    public let data: Data

    init(_ data: Data) {
        self.data = data
    }
}
