/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

/**
 A property type for a file in a form data request.

 `FormFile` can be used to include a file as part of a form data request.

 You can initialize a `FormFile` object with a key, a file URL, and an content type.

 ```swift
 FormFile(
     URL(fileURLWithPath: "/path/to/file"),
     forKey: "my_file",,
     type: .png
 )
 ```
*/
@available(*, deprecated, renamed: "Form")
public struct FormFile: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let url: URL
    let key: String
    let fileName: String
    let contentType: ContentType

    // MARK: - Inits

    /**
     Initializes a new `FormFile` instance with a file located at the specified URL.

     - Parameters:
        - url: The URL location of the file to be sent.
        - key: The name to associate with the file.
        - fileName: The name to associate with the file. If `nil`, the name will be extracted
        from the URL.
        - type: The content type of the file. If `nil`, the type will be extracted from the URL or
        default to `application/octet-stream`.
     */
    public init(
        _ url: URL,
        forKey key: String,
        fileName: String?,
        type: ContentType?
    ) {
        self.url = url
        self.key = key
        self.fileName = fileName ?? {
            url.lastPathComponent
        }()
        self.contentType = type ?? .octetStream
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<FormFile>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let factory = FilePayloadFactory(
            url: property.url,
            contentType: property.contentType
        )

        return .leaf(FormNode(
            fragmentLength: inputs.environment.payloadPartLength,
            item: FormItem(
                name: property.key,
                filename: property.fileName,
                additionalHeaders: nil,
                charset: inputs.environment.charset,
                urlEncoder: inputs.environment.urlEncoder,
                factory: factory
            )
        ))
    }
}
