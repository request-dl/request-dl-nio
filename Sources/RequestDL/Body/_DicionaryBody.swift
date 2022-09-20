import Foundation

// swiftlint:disable type_name
public struct _DicionaryBody: BodyProvider {

    private let dictionary: [String: Any]
    private let options: JSONSerialization.WritingOptions

    init(
        _ dictionary: [String: Any],
        options: JSONSerialization.WritingOptions
    ) {
        self.dictionary = dictionary
        self.options = options
    }

    public var data: Data {
        do {
            return try JSONSerialization.data(
                withJSONObject: dictionary,
                options: options
            )
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}
