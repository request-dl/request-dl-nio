/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import _RequestDLExtensions

public struct _DictionaryPayload: PayloadProvider {

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
            fatalError(
                """
                An error occurred while trying to serialize JSON data: \(error.localizedDescription).
                """
            )
        }
    }
}
