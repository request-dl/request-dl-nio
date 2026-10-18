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
/// - Important: Pass only commands you wrote or trust, or say what the command may do. A
/// command is a program for the request engine, not just data. `-F name=@path` reads that local
/// file and uploads it. `--cert`/`-E`/`--key` and `--cacert` read the files they name.
/// `-k`/`--insecure` turns certificate verification off, and `-x`/`--proxy` and `--resolve`
/// redirect where the request goes. A command built from user input, a pasted snippet or a
/// network response can therefore leak local files to a host of its choosing or strip TLS
/// protection. ``init(_:allowing:)`` refuses those flags unless the capability that covers them
/// is given, so a command from a source you do not control can run with none of them:
///
/// ```swift
/// try await CURLTask(pasted, allowing: [])
///     .result()
/// ```
///
/// `CURLTask(_:)` allows all of them, as it always did.
///
/// The command is parsed straight into a ``RequestConfiguration`` rather than through
/// `@PropertyBuilder`, since there is nothing to declare a `Property` tree from until the
/// string is parsed at runtime. Resolution and execution still go through the same pipeline
/// ``DataTask`` uses, so caching, tracing, and executor requirements all apply the same way.
public struct CURLTask: RequestTask {

    // MARK: - Public types

    /// What a curl command may do beyond describing a request: the flags that touch the machine
    /// or change where, and how safely, the request goes. ``CURLTask/init(_:)`` allows all of
    /// them; ``CURLTask/init(_:allowing:)`` refuses the flag of any that is not given, with
    /// ``CURLParsingError/Context/unsupportedFlag``, before a file is opened or a request is
    /// built.
    public struct Capabilities: OptionSet, Sendable, Hashable {

        /// Reading a file from this machine: `-F name=@path` (any path, relative ones included,
        /// which resolve against the working directory), `--cacert`, `--cert`/`-E` and `--key`.
        public static let localFiles = Capabilities(rawValue: 1 << 0)

        /// Turning certificate verification off: `-k`/`--insecure`.
        public static let disabledTLSVerification = Capabilities(rawValue: 1 << 1)

        /// Sending the request through a proxy: `-x`/`--proxy`.
        public static let proxy = Capabilities(rawValue: 1 << 2)

        /// Sending the request to an address other than the one DNS gives for the host:
        /// `--resolve`.
        public static let dnsOverrides = Capabilities(rawValue: 1 << 3)

        /// Every capability, which is what ``CURLTask/init(_:)`` allows.
        public static let all: Capabilities = [
            .localFiles, .disabledTLSVerification, .proxy, .dnsOverrides,
        ]

        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    // MARK: - Private properties

    private let command: String
    private let capabilities: Capabilities

    // MARK: - Inits

    ///
    /// Initializes with a curl command line.
    ///
    /// The command may use every flag the subset covers, local files, a proxy and
    /// `-k`/`--insecure` included. Pass only commands you wrote or trust, or use
    /// ``init(_:allowing:)``.
    ///
    /// - Parameter command: The curl command line to parse. A leading literal `curl` token, if
    /// present, is ignored.
    ///
    public init(_ command: String) {
        self.init(command, allowing: .all)
    }

    ///
    /// Initializes with a curl command line that may only use the given capabilities.
    ///
    /// A flag that needs a capability that is not in `capabilities` throws
    /// ``CURLParsingError`` with ``CURLParsingError/Context/unsupportedFlag`` and the flag as
    /// the token, while the command is parsed: before any file is opened and before anything is
    /// sent.
    ///
    /// ```swift
    /// // A command from a source you do not control, with nothing it could leak or redirect.
    /// CURLTask(pasted, allowing: [])
    ///
    /// // The same, but it may name a proxy.
    /// CURLTask(pasted, allowing: .proxy)
    /// ```
    ///
    /// - Parameters:
    ///   - command: The curl command line to parse. A leading literal `curl` token, if present,
    ///   is ignored.
    ///   - capabilities: What the command may do. An empty set refuses all of it.
    ///
    public init(_ command: String, allowing capabilities: Capabilities) {
        self.command = command
        self.capabilities = capabilities
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
    /// - Throws: ``CURLParsingError`` if the command doesn't parse or uses a flag its capabilities
    /// do not cover, or an error from the request itself.
    @_spi(Private)
    public func _result(environment: RequestEnvironmentValues) async throws -> TaskResult<Data> {
        let parsed = try await CURLCommandParser.parseCommand(command, allowing: capabilities)

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
