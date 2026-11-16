//
// See LICENSE for this package's licensing information.
//

extension Modifiers {

    /// A modifier that accepts only a response whose `Content-Type` header matches one of a
    /// specific set of ``ContentType``s.
    ///
    /// Unlike ``AcceptOnlyStatusCode``, this inspects the response body's declared type rather
    /// than the status line, catching cases a 2xx status code alone would miss: for example, a
    /// proxy or CDN returning an HTML error page with a `200 OK` status.
    ///
    /// Matching ignores parameters (`charset`, etc.) on both sides and honors the `*/*` and
    /// `type/*` wildcards from RFC 9110, so `.acceptOnlyContentType(.json)` also accepts a
    /// response declaring `application/json; charset=utf-8`.
    public struct AcceptOnlyContentType<Input: TaskResultPrimitive>: RequestTaskModifier {

        // MARK: - Internal properties

        let contentTypes: [ContentType]

        // MARK: - Public methods

        ///
        /// Modifies a task to accept only a response whose `Content-Type` matches one of the
        /// specified content types.
        ///
        /// - Parameter task: The task to modify.
        /// - Returns: The modified task that accepts only the specified content types.
        /// - Throws: An `UnacceptableContentTypeError` if the response has no `Content-Type`
        /// header, or if it does not match any of the accepted content types. An empty list
        /// accepts nothing.
        ///
        public func body(_ task: Content) async throws -> Input {
            let result = try await task.result()

            guard matches(result.head.headers.first(name: "Content-Type")) else {
                throw UnacceptableContentTypeError<Content.Element>(data: result)
            }

            return result
        }

        // MARK: - Private methods

        private func matches(_ rawContentType: String?) -> Bool {
            guard let rawContentType else {
                return false
            }

            let responseContentType = ContentType(rawContentType)

            return contentTypes.contains {
                $0.matches(responseContentType)
            }
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask where Element: TaskResultPrimitive {

    ///
    /// Returns a modified task that accepts only a response whose `Content-Type` matches one of
    /// the specified content types.
    ///
    /// - Parameter contentTypes: The content types to accept. An empty list (calling this with no
    /// arguments) accepts no response at all, so every response throws.
    /// - Returns: A modified task that accepts only the specified content types.
    /// - Throws: An `UnacceptableContentTypeError` when the response's `Content-Type` is missing or
    /// matches none of the content types.
    ///
    public func acceptOnlyContentType(
        _ contentTypes: ContentType...
    ) -> ModifiedRequestTask<Modifiers.AcceptOnlyContentType<Element>> {
        acceptOnlyContentType(contentTypes)
    }

    ///
    /// Returns a modified task that accepts only a response whose `Content-Type` matches one of
    /// the specified content types.
    ///
    /// - Parameter contentTypes: The content types to accept. An empty array (an intersection with
    /// nothing in common, a list read from a configuration with nothing in it) accepts no response at
    /// all, so every response throws. To accept any response that declares a `Content-Type`, pass
    /// `"*/*"`.
    /// - Returns: A modified task that accepts only the specified content types.
    /// - Throws: An `UnacceptableContentTypeError` when the response's `Content-Type` is missing or
    /// matches none of the content types.
    ///
    public func acceptOnlyContentType(
        _ contentTypes: [ContentType]
    ) -> ModifiedRequestTask<Modifiers.AcceptOnlyContentType<Element>> {
        modifier(Modifiers.AcceptOnlyContentType(contentTypes: contentTypes))
    }
}
