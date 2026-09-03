//
// See LICENSE for this package's licensing information.
//

import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Produces the curl command line equivalent of a resolved request.
///
/// Select it with `.cURL`:
///
/// ```swift
/// let command = try await DataTask {
///     BaseURL("example.com")
///     Payload(data: someData)
/// }
/// .description(.cURL)
/// ```
///
/// `-H`/URL/method/a plain body all come straight from ``TaskDescriptorContext/requestConfiguration``
/// — nothing is lost reading those back after resolution. `-u` is recovered by decoding a `Basic`
/// `Authorization` header back to `user:pass`. `-F` is the one thing that couldn't be
/// reconstructed from the final configuration alone — a resolved multipart body is already one
/// opaque byte stream with a boundary — so it's built from ``TaskDescriptorContext/formFields``
/// instead, which is captured earlier, before that flattening happens.
public struct CURLTaskDescriptor: TaskDescriptor {

    // MARK: - Inits

    init() {}

    // MARK: - Public methods

    public func describe(_ context: TaskDescriptorContext) async throws -> String {
        let configuration = context.requestConfiguration

        var fragments = ["curl"]

        if let method = configuration.method {
            fragments.append("-X \(method)")
        }

        fragments.append(curlShellQuote(configuration.url))

        let hasFormFields = !context.formFields.isEmpty
        var basicCredentialsFragment: String?

        for (name, value) in configuration.headers {
            // curl computes this itself; passing it by hand risks disagreeing with what curl
            // actually sends.
            if name.caseInsensitiveCompare("Content-Length") == .orderedSame {
                continue
            }

            // curl derives its own `Content-Type` (with its own multipart boundary) from `-F`
            // flags — the one captured here still carries the boundary from the body this
            // description pass isn't using, which would be actively misleading to print.
            if hasFormFields, name.caseInsensitiveCompare("Content-Type") == .orderedSame {
                continue
            }

            if name.caseInsensitiveCompare("Authorization") == .orderedSame,
                let credentialBytes = basicCredentialBytes(from: value)
            {
                basicCredentialsFragment = "-u " + curlShellQuote(credentialBytes)
                continue
            }

            fragments.append("-H " + curlShellQuote("\(name): \(value)"))
        }

        if let basicCredentialsFragment {
            fragments.append(basicCredentialsFragment)
        }

        if hasFormFields {
            for field in context.formFields {
                fragments.append("-F " + curlShellQuote(formFragmentBytes(field)))
            }
        } else if let body = configuration.body {
            var data = Data()
            data.reserveCapacity(body.totalSize)

            for await buffer in body {
                data.append(contentsOf: buffer.readableBytesView)
            }

            fragments.append("--data-raw " + curlShellQuote(Array(data)))
        }

        return fragments.joined(separator: " \\\n  ")
    }

    // MARK: - Private methods

    /// - Note: The original source path isn't recoverable once a field has already gone through
    /// its `PayloadFactory` — `filename` here is the name curl would show a server, not
    /// necessarily a path that exists on this machine. Round-tripping this description back
    /// through a real upload needs that filename to point at a real file first.
    ///
    /// - Important: Builds this at the byte level, not through `String(decoding:as:)` — a plain
    /// (no `filename`) field's `content` is arbitrary bytes, not necessarily valid UTF-8 (e.g. a
    /// `Form(data:)` field with no filename). Decoding it into a `String` before it ever reaches
    /// `curlShellQuote` would replace anything invalid with U+FFFD *before* that function's own
    /// byte-safe `$'...'` fallback gets a chance to see the original bytes, corrupting the
    /// reconstructed value. Working in `[UInt8]` throughout sidesteps that entirely.
    private func formFragmentBytes(_ field: FormFieldDescriptor) -> [UInt8] {
        guard let filename = field.filename else {
            return Array("\(field.name)=".utf8) + Array(field.content)
        }

        return Array("\(field.name)=@\(filename);type=\(field.contentType)".utf8)
    }

    /// The raw `user:pass` bytes decoded from a `Basic` `Authorization` header, or `nil` when
    /// the header isn't `Basic` or doesn't decode to a plausible `user:pass` pair.
    ///
    /// - Important: Returns bytes, not a `String` split into username/password and rejoined.
    /// RFC 7617 doesn't guarantee `user:pass` is valid UTF-8 (it names a caller-declared charset,
    /// historically ISO-8859-1), and curl's own `-u` argument is exactly this decoded `user:pass`
    /// form already — there's nothing to reformat, only something to avoid corrupting by
    /// round-tripping through a lossy `String(decoding:as:)` the way `formFragmentBytes(_:)`
    /// above already has to avoid.
    private func basicCredentialBytes(from headerValue: String) -> [UInt8]? {
        let prefix = "Basic "

        guard
            headerValue.hasPrefix(prefix),
            let data = Data(base64Encoded: String(headerValue.dropFirst(prefix.count))),
            data.contains(UInt8(ascii: ":"))
        else {
            return nil
        }

        return Array(data)
    }
}

// MARK: - TaskDescriptor extension

extension TaskDescriptor where Self == CURLTaskDescriptor {

    /// Produces the curl command line equivalent of a resolved request.
    public static var cURL: Self {
        .init()
    }
}
