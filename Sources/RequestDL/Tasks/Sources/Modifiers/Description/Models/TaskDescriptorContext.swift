//
// See LICENSE for this package's licensing information.
//

/// What a ``TaskDescriptor`` has to work with.
///
/// `requestConfiguration` is enough on its own for almost everything a request declares — its
/// URL, method, headers, and a plain body all round-trip losslessly. The one exception is
/// ``RequestDL/Form``: by the time its fields reach `requestConfiguration.body` they're already
/// flattened into one `multipart/form-data` byte stream with a boundary, which is not something
/// a descriptor could reconstruct field by field. `formFields` is captured earlier in the same
/// resolution pass, before that flattening happens, specifically to cover that gap.
public struct TaskDescriptorContext: Sendable {

    /// The fully resolved request.
    public let requestConfiguration: RequestConfiguration

    /// Every ``RequestDL/Form`` field declared, captured before it was flattened into
    /// `requestConfiguration.body`. Empty when no `Form` was declared.
    public let formFields: [FormFieldDescriptor]
}
