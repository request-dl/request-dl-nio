//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Quotes `bytes` for safe use as one argument in a shell command line.
///
/// Printable ASCII with no single quote goes out as `'...'`, which is the most legible form and
/// what almost every real header/URL/body ends up as. Anything else — a literal `'`, control
/// characters, non-ASCII bytes, bytes that aren't valid UTF-8 at all — goes out as bash's
/// `$'...'` ANSI-C form instead, with every byte written as a `\xHH` escape. That form is
/// interpreted by the shell before curl ever sees the argument, so it reproduces the exact
/// original bytes without assuming they're text.
func curlShellQuote(_ bytes: some Sequence<UInt8>) -> String {
    let bytes = Array(bytes)

    guard bytes.allSatisfy(isPlainShellSafe) else {
        let escaped = bytes.map { "\\x" + hex($0) }.joined()
        return "$'\(escaped)'"
    }

    let string = String(decoding: bytes, as: UTF8.self)
    return "'" + string.escapingSingleQuotes() + "'"
}

func curlShellQuote(_ string: String) -> String {
    curlShellQuote(Array(string.utf8))
}

// MARK: - Private functions

/// Printable ASCII, space included, minus the single quote — safe to place verbatim inside a
/// `'...'` argument with no escaping at all.
private func isPlainShellSafe(_ byte: UInt8) -> Bool {
    (0x20...0x7E).contains(byte) && byte != 0x27
}

/// Two lowercase hex digits, zero-padded — `String(byte, radix: 16)` alone drops the leading
/// zero (`0xa` prints as `"a"`, not `"0a"`), which `\xHH` needs to stay exactly two digits.
private func hex(_ byte: UInt8) -> String {
    let digits = String(byte, radix: 16)
    return digits.count == 1 ? "0" + digits : digits
}

// MARK: - String extension

extension String {

    /// - Note: A single-`Character` scan, not Foundation's `replacingOccurrences(of:with:)` (this
    /// file otherwise needs nothing beyond `Data`, which `FoundationEssentials` already provides)
    /// and not the stdlib's own `replacing(_:with:)`/`firstRange(of:)` either — both are gated to
    /// macOS 13/iOS 16, newer than this package's macOS 12/iOS 15 minimum. The only caller ever
    /// escapes one character (`'`), so there's no need for a general substring search at all.
    fileprivate func escapingSingleQuotes() -> String {
        var result = ""
        result.reserveCapacity(count)

        for character in self {
            if character == "'" {
                result += "'\\''"
            } else {
                result.append(character)
            }
        }

        return result
    }
}
