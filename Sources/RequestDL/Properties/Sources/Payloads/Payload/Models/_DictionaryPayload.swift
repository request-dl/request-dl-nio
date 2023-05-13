/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _DictionaryPayload: PayloadProvider, @unchecked Sendable {

    // MARK: - Internals properties

    var buffer: Internals.DataBuffer {
        Internals.DataBuffer(data)
    }

    // MARK: - Private properties

    private let dictionary: [String: Any]
    private let options: JSONSerialization.WritingOptions

    private var data: Data {
        do {
            return try JSONSerialization.data(
                withJSONObject: dictionary,
                options: options
            )
        } catch {
            Internals.Log.failure(
                .cantSerializeJSONData(
                    dictionary,
                    options,
                    error
                )
            )
        }
    }

    // MARK: - Inits

    init(
        _ dictionary: [String: Any],
        options: JSONSerialization.WritingOptions
    ) {
        self.dictionary = dictionary
        self.options = options
    }
}
