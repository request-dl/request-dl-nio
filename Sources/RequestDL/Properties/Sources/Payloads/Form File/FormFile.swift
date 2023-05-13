/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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
@RequestActor
public struct FormFile: Property {

    let url: URL
    let key: String
    let fileName: String
    let contentType: ContentType

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
        self.contentType = type ?? {
            guard
                !url.pathExtension.isEmpty,
                let contentType = ContentType.allCases.first(where: {
                    $0.rawValue.contains(url.pathExtension)
                })
            else { return "application/octet-stream" }

            return contentType
        }()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension FormFile {

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<FormFile>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        return .leaf(FormNode(inputs.environment.payloadPartLength) {
            let data = (try? Data(contentsOf: property.url)) ?? Data()
            return PartFormRawValue(data, forHeaders: [
                kContentDisposition: kContentDispositionValue(
                    property.fileName,
                    forKey: property.key
                ),
                "Content-Type": "\(property.contentType)"
            ])
        })
    }
}
