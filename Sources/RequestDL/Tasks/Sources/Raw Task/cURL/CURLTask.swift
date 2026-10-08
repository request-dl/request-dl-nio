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
/// Only a documented subset of curl's flags is understood: `-X`/`--request`, `-H`/`--header`
/// (repeatable), `-d`/`--data`/`--data-raw`/`--data-binary`, `-F`/`--form` (repeatable),
/// `-u`/`--user`, `--url` (or a bare trailing URL), `-G`/`--get`, `-L`/`--location` (with
/// `--max-redirs`), `-k`/`--insecure`, `-x`/`--proxy`, `--resolve`, `--compressed`, `--cacert`,
/// and `--cert`/`-E`/`--key`. A small set of flags that only shape curl's own CLI output
/// (`-s`/`--silent`, `-S`/`--show-error`, `-v`/`--verbose`, `-i`/`--include`,
/// `-#`/`--progress-bar`, `-o`/`--output`, `-w`/`--write-out`) is accepted and ignored
/// outright, since none of them affect the request or response.
///
/// Everything else, such as cookie jars, `--cert-type`/`--key-type` (PEM is assumed), `--resolve`
/// under a pinned `.urlSession` executor, HTTP/3, and non-`http(s)` schemes, throws
/// ``CURLParsingError`` rather than being silently ignored. These aren't merely unimplemented:
/// silently accepting one of them would change what the request actually does compared to what the
/// pasted command says.
///
/// `-L` in particular restores curl's own default rather than only adding an opt-in: this
/// package normally follows redirects by default on both transports, which curl does not unless
/// `-L` is given, so a curl command *without* `-L` executed through `CURLTask` explicitly
/// disables redirect-following to match, not merely "leaves it as the package default." The
/// same applies to `--compressed` and decompression. `--resolve` (`Internals.Session
/// .Configuration.dnsOverride`) is incompatible with the `.urlSession` executor, so a command
/// using it will only run under `.nio`/`.nioTransportServices`.
///
/// - Important: Pass only commands you wrote or trust. A command is a program for the request
/// engine, not just data. `-F name=@path` reads that local file and uploads it. `--cert`/`-E`/
/// `--key` and `--cacert` read the files they name. `-k`/`--insecure` turns certificate
/// verification off, and `-x`/`--proxy` and `--resolve` redirect where the request goes. A
/// command built from user input, a pasted snippet or a network response can therefore leak
/// local files to a host of its choosing or strip TLS protection. Reject or inspect such a
/// command before handing it to `CURLTask`, or build the request with ``DataTask`` instead.
///
/// The command is parsed straight into a ``RequestConfiguration`` rather than through
/// `@PropertyBuilder`, since there is nothing to declare a `Property` tree from until the
/// string is parsed at runtime. Resolution and execution still go through the same pipeline
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

    /// This method is used internally and should not be called directly.
    ///
    /// Parses the command and performs the request, forwarding `environment` to the underlying
    /// `RawTask` the same way ``DataTask`` does. Implementing only `result()` instead dropped it:
    /// every environment-borne modifier wrapping a `CURLTask` (`.logger(_:)`,
    /// `.description(_:onDescribe:)`, `.digestAuthentication()`, `.environment(...)`) was then a
    /// silent no-op.
    ///
    /// - Throws: ``CURLParsingError`` if the command doesn't parse, or an error from the request
    /// itself.
    @_spi(Private)
    public func _result(environment: RequestEnvironmentValues) async throws -> TaskResult<Data> {
        let parsed = try await CURLCommandParser.parseCommand(command)

        return try await RawTask(
            content: RawRequestConfigurationProperty(
                configuration: parsed.requestConfiguration,
                sessionConfigurationEdit: parsed.sessionConfigurationEdit
            )
        )
        .collectData()
        ._result(environment: environment)
    }
}
