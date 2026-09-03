//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Parses a curl command line and performs it as a request.
///
/// ```swift
/// try await CURLTask("""
///     curl -X POST https://example.com/users \\
///         -H "Content-Type: application/json" \\
///         -d '{"name":"John Doe"}'
///     """
/// )
/// .result()
/// ```
///
/// Only a documented subset of curl's flags is understood — `-X`/`--request`, `-H`/`--header`
/// (repeatable), `-d`/`--data`/`--data-raw`/`--data-binary`, `-F`/`--form` (repeatable),
/// `-u`/`--user`, `--url` (or a bare trailing URL), and `-G`/`--get`. A small set of flags that
/// only shape curl's own CLI output — `-s`/`--silent`, `-S`/`--show-error`, `-v`/`--verbose`,
/// `-i`/`--include`, `-#`/`--progress-bar`, `-o`/`--output`, `-w`/`--write-out` — is accepted and
/// ignored outright, since none of them affect the request or response in any way.
///
/// Everything else — `-L`/`--location`, `--compressed`, `-k`/`--insecure`, cookie jars,
/// TLS/proxy flags, and so on — throws ``CURLParsingError`` rather than being silently ignored.
/// These aren't merely unimplemented: silently accepting them would change what the request
/// actually does compared to what the pasted command says. `-L` in particular is not a "not yet
/// supported" gap so much as a direction mismatch — this package already follows redirects by
/// default on both transports (curl does not, unless `-L` is given), so a curl command *without*
/// `-L` would need `CURLTask` to actively turn redirect-following off to match, which needs
/// session-level configuration `CURLTask` has no way to express from a single command string
/// today.
///
/// The command is parsed straight into a ``RequestConfiguration`` rather than through
/// `@PropertyBuilder` — there is nothing to declare a `Property` tree from until the string is
/// parsed at runtime — but resolution and execution still go through the same pipeline
/// ``DataTask`` uses, so caching, tracing, and executor requirements all apply the same way.
public struct CURLTask: RequestTask {

    // MARK: - Private properties

    private let command: String

    // MARK: - Inits

    ///
    /// Initializes with a curl command line.
    ///
    /// - Parameter command: The curl command line to parse. A leading literal `curl` token, if
    /// present, is ignored.
    ///
    public init(_ command: String) {
        self.command = command
    }

    // MARK: - Public methods

    ///
    /// Parses the command and performs the request.
    ///
    /// - Returns: A ``TaskResult`` with `Data` as its `payload`.
    /// - Throws: ``CURLParsingError`` if the command doesn't parse, or an error from the request
    /// itself.
    ///
    public func result() async throws -> TaskResult<Data> {
        let configuration = try await CURLCommandParser.parse(command)

        return try await RawTask(
            content: RawRequestConfigurationProperty(configuration: configuration)
        )
        .collectData()
        .result()
    }
}
