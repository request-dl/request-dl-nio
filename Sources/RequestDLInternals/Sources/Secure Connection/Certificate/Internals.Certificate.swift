//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

import SwiftASN1

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

extension Internals {

    package struct Certificate: Sendable, Hashable {

        package enum Source: Hashable {
            case file(String)
            case bytes([UInt8])
        }

        // MARK: - Internal properties

        package let source: Source
        package let format: Format

        // MARK: - Inits

        package init(_ file: String, format: Format) {
            self.source = .file(file)
            self.format = format
        }

        package init(_ bytes: [UInt8], format: Format) {
            self.source = .bytes(bytes)
            self.format = format
        }

        // MARK: - Internal methods

        /// The DER bytes of every certificate this configuration resolves to: one for `.der`
        /// (which can only ever hold a single certificate), one per `-----BEGIN CERTIFICATE-----`
        /// block for `.pem` (a bundle can hold a leaf plus intermediates).
        ///
        /// Portable counterpart to `build()`: reads the exact same bytes, without NIOSSL parsing
        /// them into a `NIOSSLCertificate` first only to export the DER right back out again.
        /// Built on `SwiftASN1`'s own `PEMDocument.parseMultiple(pemString:)`, not a hand-rolled
        /// PEM splitter. `SwiftASN1` is already a portable dependency of this package (`X509`'s
        /// own non-Darwin trust evaluator uses it), and it already handles what a hand-rolled
        /// version would have to get right itself: locating every `-----BEGIN/END-----` pair and
        /// base64-decoding each one. Verified against `NIOSSLCertificate.fromPEMFile`'s own DER
        /// output for byte-for-byte equality. See `InternalsCertificateTests`.
        ///
        /// - Important: Deliberately matches `build()`'s own asymmetry between the two `.pem`
        /// sources, confirmed by that same test suite, not assumed: `.file` reads every
        /// certificate in the bundle (`NIOSSLCertificate.fromPEMFile`'s own behavior), but
        /// `.bytes` only ever reads the *first* one, since `build()`'s `.bytes` case constructs a
        /// single `NIOSSLCertificate(bytes:format:)` rather than calling `.fromPEMBytes`. Fixing
        /// that asymmetry would be a real behavior change, so it is left alone here on purpose.
        package func resolvedDERBytes() throws -> [Data] {
            let raw: Data

            switch source {
            case .bytes(let bytes):
                raw = Data(bytes)
            case .file(let file):
                do {
                    raw = try Data(contentsOf: URL(fileURLWithPath: file))
                } catch {
                    throw SecureFileLoadError(resource: .certificate, path: file, underlying: error)
                }
            }

            switch format {
            case .der:
                return [raw]
            case .pem:
                do {
                    let documents = try Self.resolvedPEMCertificateDERBytes(of: raw)

                    switch source {
                    case .bytes:
                        return [documents[0]]
                    case .file:
                        return documents
                    }
                } catch {
                    if case .file(let file) = source {
                        throw SecureFileLoadError(resource: .certificate, path: file, underlying: error)
                    }
                    throw error
                }
            }
        }

        /// Every certificate's DER bytes found in a `.pem`-format blob, in order. This is the
        /// shared parsing step `resolvedDERBytes()` builds on, and that `CertificateChain`/
        /// `TrustRoots`/`AdditionalTrustRoots`'s own portable methods call directly for their
        /// multi-certificate `.bytes`/`.file` cases (both, unlike `Certificate.resolvedDERBytes()`'s
        /// own `.bytes` case; see that method's doc comment for why `Certificate` alone truncates
        /// a single-certificate `.bytes` source there).
        package static func resolvedPEMCertificateDERBytes(of pemData: Data) throws -> [Data] {
            guard let pemString = String(data: pemData, encoding: .utf8) else {
                throw MalformedPEMError()
            }

            let documents = try PEMDocument.parseMultiple(pemString: pemString)
                .filter { $0.discriminator == "CERTIFICATE" }

            guard !documents.isEmpty else {
                throw MalformedPEMError()
            }

            return documents.map { Data($0.derBytes) }
        }

        // MARK: - Internal methods (build)

        #if canImport(NIOCore)
        package func build() throws -> [NIOSSLCertificate] {
            switch source {
            case .bytes(let bytes):
                return try [NIOSSLCertificate(bytes: bytes, format: format.build())]
            case .file(let file):
                do {
                    switch format {
                    case .der:
                        return try [NIOSSLCertificate.fromDERFile(file)]
                    case .pem:
                        return try NIOSSLCertificate.fromPEMFile(file)
                    }
                } catch {
                    throw SecureFileLoadError(resource: .certificate, path: file, underlying: error)
                }
            }
        }
        #endif
    }

    /// A PEM string that isn't valid UTF-8, or that `PEMDocument.parseMultiple(pemString:)`
    /// couldn't make sense of (no `-----BEGIN-----` marker, malformed base64, ...).
    package struct MalformedPEMError: Error, Sendable {}
}
