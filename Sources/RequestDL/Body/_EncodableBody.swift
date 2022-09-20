import Foundation

// swiftlint:disable type_name
public struct _EncodableBody<Object: Encodable>: BodyProvider {

    private let object: Object
    private let encoder: JSONEncoder

    init(
        _ object: Object,
        encoder: JSONEncoder = .init()
    ) {
        self.object = object
        self.encoder = encoder
    }

    public var data: Data {
        do {
            return try encoder.encode(object)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}
