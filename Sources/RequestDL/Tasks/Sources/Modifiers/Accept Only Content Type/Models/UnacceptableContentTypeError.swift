//
// See LICENSE for this package's licensing information.
//

/// A error type representing a validation error due to an unexpected or missing `Content-Type`
/// response header.
///
/// ```swift
/// do {
///     let result = try await DataTask {
///         BaseURL("apple.com")
///     }
///     .acceptOnlyContentType(.json)
///     .result()
///     // use validated result
/// } catch let error as UnacceptableContentTypeError<Data> {
///     // handle validation error
/// }
/// ```
public struct UnacceptableContentTypeError<Element: Sendable>: TaskError {

    /// The data that caused the validation error.
    public let data: Element
}
