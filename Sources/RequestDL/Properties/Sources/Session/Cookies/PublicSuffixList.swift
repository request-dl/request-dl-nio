//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The rules of a [Public Suffix List](https://publicsuffix.org), which a ``CookieJar`` uses to
/// refuse a cookie set for a `Domain` under which unrelated parties register names.
///
/// RequestDL does not ship a list: it changes as new domains appear, and keeping it current is not
/// the job of a networking library. Download `public_suffix_list.dat` and bundle it with your app,
/// or fetch it yourself, and parse it once:
///
/// ```swift
/// let list = try PublicSuffixList(contentsOf: bundledListURL)
/// let jar = CookieJar(publicSuffixList: list)
/// ```
///
/// Parsing a list costs a few milliseconds, so keep the value and reuse it for every jar. A file that
/// is not a list, such as the HTML or JSON error page a failed download saved in its place, is refused
/// with a ``PublicSuffixListError`` instead of being taken for a list that protects from nothing. A
/// plain-text body made only of words cannot be told from a list of one-label names, so download the
/// list over HTTPS, check the status, and bundle it rather than fetching it blindly. Names are
/// compared in their Punycode form, so a list written in Unicode covers a host in either spelling.
public struct PublicSuffixList: Sendable {

    // MARK: - Internal properties

    let list: Internals.PublicSuffixList

    // MARK: - Inits

    /// Parses the contents of a `public_suffix_list.dat` file.
    ///
    /// - Parameter data: The UTF-8 contents of the file.
    /// - Throws: ``PublicSuffixListError`` when `data` is not text, has no rule in it, or has a line
    ///   that cannot be a rule.
    public init(data: Data) throws {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw PublicSuffixListError.notText
        }

        list = try Self.parse(contents)
    }

    /// Reads and parses a `public_suffix_list.dat` file.
    ///
    /// - Parameter fileURL: Where the file is.
    /// - Throws: The error reading the file throws, or ``PublicSuffixListError``.
    public init(contentsOf fileURL: URL) throws {
        try self.init(data: Data(contentsOf: fileURL))
    }

    // MARK: - Private static methods

    private static func parse(_ contents: String) throws -> Internals.PublicSuffixList {
        do {
            return try Internals.PublicSuffixList(contents)
        } catch Internals.PublicSuffixList.ParseError.malformed {
            throw PublicSuffixListError.malformed
        } catch {
            throw PublicSuffixListError.noRules
        }
    }
}

/// Why a ``PublicSuffixList`` could not be made.
public enum PublicSuffixListError: Error, Sendable, Equatable {

    /// The data is not UTF-8 text.
    case notText

    /// The text has no rule in it, so it is not a Public Suffix List.
    case noRules

    /// The text has a line that cannot be a rule, so it is not a Public Suffix List: an HTML or JSON
    /// page, or HTTP headers, saved where the list should be.
    case malformed
}
