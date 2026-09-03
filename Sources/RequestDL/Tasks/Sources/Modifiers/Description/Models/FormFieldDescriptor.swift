//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// One ``RequestDL/Form`` field, captured before it was flattened into a multipart body.
public struct FormFieldDescriptor: Sendable {

    /// The field's name.
    public let name: String

    /// The field's filename, when it was declared with one — a plain text field has none.
    public let filename: String?

    /// The field's `Content-Type`.
    public let contentType: String

    /// The field's raw bytes, exactly as they'd appear in the multipart part.
    public let content: Data
}
