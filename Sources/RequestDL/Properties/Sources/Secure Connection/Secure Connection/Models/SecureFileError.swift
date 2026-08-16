//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import SystemPackage

/// An error thrown when RequestDL cannot load a certificate or private key from a file path.
///
/// ``Certificate``, ``Certificates``, ``TrustRoots``, ``AdditionalTrustRoots``, and ``PrivateKey``
/// all accept a plain `String` path, which is handed to the underlying TLS library exactly as
/// given. That library only ever reports a generic "failed to load" failure back, with no mention
/// of which path it tried or why opening it failed — this type exists to close that gap.
public struct SecureFileError: Error, Sendable {

    /// The kind of resource RequestDL was trying to load from ``path``.
    public enum Resource: Sendable, Hashable {
        /// A certificate, loaded by ``Certificate``, ``Certificates``, ``TrustRoots``, or
        /// ``AdditionalTrustRoots``.
        case certificate
        /// A private key, loaded by ``PrivateKey``.
        case privateKey

        init(_ resource: Internals.SecureFileLoadError.Resource) {
            switch resource {
            case .certificate:
                self = .certificate
            case .privateKey:
                self = .privateKey
            }
        }
    }

    /// The specific reason loading failed.
    public enum Context: Sendable {
        /// The file could not be opened. `reason` is the underlying system failure, such as
        /// "No such file or directory" or "Permission denied".
        case cantOpenFile(reason: String)

        /// The file opened, but its contents could not be parsed in the expected format.
        case invalidContents(any Error)
    }

    // MARK: - Public properties

    /// The kind of resource RequestDL was trying to load.
    public let resource: Resource

    /// The exact path that was passed in, unmodified.
    public let path: String

    /// Whether ``path`` is relative, rather than an absolute path.
    ///
    /// A relative path is resolved by the underlying TLS library against the current process's
    /// working directory — not your app's bundle, not the directory your source file lives in,
    /// and on iOS/tvOS/watchOS not anywhere predictable at all. This is `true` whenever that is
    /// the likely cause of a ``Context/cantOpenFile(reason:)`` failure.
    public let isRelativePath: Bool

    /// The reason loading failed.
    public let context: Context

    // MARK: - Inits

    init(resource: Resource, path: String, underlying: any Error) {
        self.resource = resource
        self.path = path

        let filePath = FilePath(path)
        self.isRelativePath = filePath.isRelative
        self.context =
            filePath.probeOpenFailure().map { .cantOpenFile(reason: $0.description) }
            ?? .invalidContents(underlying)
    }

    /// Rewraps the raw load-failure context `Internals.Certificate`/`Internals.PrivateKey`
    /// throw from `RequestDLInternals`, where the public, documented ``SecureFileError`` itself
    /// isn't reachable.
    init(_ error: Internals.SecureFileLoadError) {
        self.init(
            resource: Resource(error.resource),
            path: error.path,
            underlying: error.underlying
        )
    }
}

// MARK: - CustomStringConvertible

extension SecureFileError: CustomStringConvertible {

    public var description: String {
        var message = "RequestDL failed to load a \(resourceDescription) from \"\(path)\"."

        switch context {
        case .cantOpenFile(let reason):
            message += " \(reason)."
        case .invalidContents(let error):
            message += " The file was opened, but its contents could not be parsed: \(error)"
        }

        guard isRelativePath else {
            return message
        }

        return
            message
                + """


                "\(path)" is a relative path, resolved against the process's current working \
                directory rather than your app bundle or project directory — on iOS, tvOS, and \
                watchOS that directory is not predictable, which is almost always why this fails on \
                device or in the simulator despite the file being right there in your project.

                Pass an absolute path instead, or, if the file ships inside your app bundle, use \
                \(bundleInitializerHint).
                """
    }

    private var resourceDescription: String {
        switch resource {
        case .certificate:
            return "certificate"
        case .privateKey:
            return "private key"
        }
    }

    private var bundleInitializerHint: String {
        switch resource {
        case .certificate:
            return "Certificate(_:in:format:) with the bundle that contains it (e.g. .module or .main)"
        case .privateKey:
            return "PrivateKey(_:in:format:) with the bundle that contains it (e.g. .module or .main)"
        }
    }
}

// MARK: - File probing

extension FilePath {

    /// Attempts to open this path for reading, purely to see whether it can be. The descriptor,
    /// if any, is closed and discarded immediately.
    ///
    /// This exists because NIOSSL's own file loading only ever throws a generic
    /// `NIOSSLError.failedToLoadCertificate`, with no way to tell a missing file apart from a
    /// malformed one. Probing separately, before handing the path to NIOSSL, recovers that
    /// distinction from the same system call NIOSSL itself is about to make.
    fileprivate func probeOpenFailure() -> Errno? {
        do {
            let descriptor = try FileDescriptor.open(self, .readOnly)
            try? descriptor.close()
            return nil
        } catch let errno as Errno {
            return errno
        } catch {
            return nil
        }
    }
}
