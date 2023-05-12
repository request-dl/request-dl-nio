/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A representation of data that can be sent in the body of an HTTP request using the `multipart/form-data` format.
@RequestActor
public struct FormData: Property {

    let buffer: Internals.DataBuffer
    let fileName: String
    let key: String
    let contentType: ContentType

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
        self.buffer = Internals.DataBuffer(data)
        self.key = key
        self.fileName = fileName
        self.contentType = type
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
        self.key = key
        self.fileName = fileName
        self.buffer = _EncodablePayload(object, encoder: encoder).buffer
        self.contentType = .json
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension FormData {

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<FormData>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(FormNode(inputs.environment.payloadPartLength) {
            PartFormRawValue(property.buffer.getData() ?? Data(), forHeaders: [
                kContentDisposition: kContentDispositionValue(
                    property.fileName,
                    forKey: property.key
                ),
                "Content-Type": property.contentType
            ])
        })
    }
}
