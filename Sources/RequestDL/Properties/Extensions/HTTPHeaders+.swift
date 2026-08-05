//
// See LICENSE for this package's licensing information.
//

extension HTTPHeaders {

    /// The values of `name`, split on commas and trimmed.
    ///
    /// For the list-based fields of RFC 9110, where several field lines and one comma separated
    /// line mean the same thing.
    ///
    /// - Note: Must not read `{ $0 + $1.split(separator: ",") }` — two parameters in a one
    /// parameter `flatMap`, which does not compile. That shape looks like a `reduce` turned into
    /// a `flatMap` without dropping the accumulator. The declared return type,
    /// `LazyMapSequence<[Substring], String>`, matches the `flatMap`/`map` pair below exactly.
    ///
    /// Trimming goes through the package's own helper. `trimmingCharacters(in:)` needs
    /// `Foundation.CharacterSet`, and this file imports nothing at all.
    func components(name: String) -> (some Sequence<String>)? {
        self[name]?
            .lazy
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimming(where: \.isWhitespace) }
    }
}
