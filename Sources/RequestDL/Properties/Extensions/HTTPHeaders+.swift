//
// See LICENSE for this package's licensing information.
//

extension HTTPHeaders {

    /// The values of `name`, split on commas and trimmed.
    ///
    /// For the list-based fields of RFC 9110, where several field lines and one comma separated
    /// line mean the same thing.
    ///
    /// Trimming goes through the package's own helper, since `trimmingCharacters(in:)` needs
    /// `Foundation.CharacterSet` and this file imports nothing.
    func components(name: String) -> (some Sequence<String>)? {
        self[name]?
            .lazy
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimming(where: \.isWhitespace) }
    }
}
