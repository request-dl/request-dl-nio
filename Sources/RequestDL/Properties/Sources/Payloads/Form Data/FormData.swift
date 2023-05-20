/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A representation of data that can be sent in the body of an HTTP request using the `multipart/form-data` format.
@available(*, deprecated, renamed: "Form")
public struct FormData: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let name: String
    let filename: String
    let factory: PayloadFactory

    // MARK: - Inits

    /**
     Creates a new `FormData` instance with the specified parameters.

     - Parameters:
        - data: The data to be sent.
        - key: The name to associate with the data.
        - fileName: The filename to associate with the data, according to RFC 7578.
        Defaults to an empty string.
        - type: The content type of the data.
     */
    public init(
        _ data: Foundation.Data,
        forKey key: String,
        fileName: String = "",
        type: ContentType
    ) {
        self.name = key
        self.filename = fileName
        self.factory = DataPayloadFactory(
            data: data,
            contentType: type
        )
    }

    /**
     Creates a new `FormData` instance by encoding a value as JSON data.

     - Parameters:
        - object: The value to be encoded as JSON data.
        - key: The name to associate with the data.
        - fileName: The filename to associate with the data, according to RFC 7578.
        Defaults to an empty string.
        - encoder: The `JSONEncoder` to use for encoding the value.
     */
    public init<T: Encodable>(
        _ object: T,
        forKey key: String,
        fileName: String = "",
        encoder: JSONEncoder = .init()
    ) {
        self.name = key
        self.filename = fileName
        self.factory = EncodablePayloadFactory(
            object,
            encoder: encoder,
            contentType: .json
        )
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<FormData>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(FormNode(
            fragmentLength: inputs.environment.payloadPartLength,
            item: FormItem(
                name: property.name,
                filename: property.filename,
                additionalHeaders: nil,
                charset: inputs.environment.charset,
                urlEncoder: inputs.environment.urlEncoder,
                factory: property.factory
            )
        ))
    }
}
