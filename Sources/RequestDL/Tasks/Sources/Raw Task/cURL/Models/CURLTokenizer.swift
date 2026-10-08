//
// See LICENSE for this package's licensing information.
//

/// Splits a curl command line into shell-style tokens.
///
/// Not a full POSIX shell (no variable expansion, command substitution, or globbing), but it
/// handles the quoting a "copy as cURL" export actually uses: single quotes (literal), double
/// quotes (`\\`, `\"`, `\$`, `` \` `` escapes), backslash-escaping outside quotes, and bash's
/// `$'...'` ANSI-C quoting (`\n \t \r \\ \' \" \xHH`). A trailing `\` at the end of a physical
/// line is a continuation and is removed before tokenizing even begins, since multi-line curl
/// exports are the common case in practice.
///
/// Walks the command as Unicode scalars, not `Character`s. A `Character` is a grapheme cluster, so
/// `"\r\n"` is one `Character` equal to neither `"\r"` nor `"\n"`, and a quote or a space followed
/// by a combining mark is one `Character` equal to neither of them. Both are plain delimiters to
/// a shell, which works on bytes.
enum CURLTokenizer {

    // MARK: - Internal static methods

    static func tokenize(_ command: String) throws -> [String] {
        let characters = Array(removingLineContinuations(command).unicodeScalars)

        var tokens: [String] = []
        var current = ""
        var hasToken = false
        var index = characters.startIndex

        func flush() {
            if hasToken {
                tokens.append(current)
                current = ""
                hasToken = false
            }
        }

        while index < characters.endIndex {
            let character = characters[index]

            switch character {
            case " ", "\t", "\n", "\r":
                flush()
                index += 1

            case "'":
                hasToken = true
                index += 1

                while index < characters.endIndex, characters[index] != "'" {
                    current.unicodeScalars.append(characters[index])
                    index += 1
                }

                guard index < characters.endIndex else {
                    throw CURLParsingError(.unterminatedQuote, token: current)
                }

                index += 1

            case "\"":
                hasToken = true
                index += 1

                while index < characters.endIndex, characters[index] != "\"" {
                    if characters[index] == "\\",
                        index + 1 < characters.endIndex,
                        "\"\\$`".unicodeScalars.contains(characters[index + 1])
                    {
                        current.unicodeScalars.append(characters[index + 1])
                        index += 2
                    } else {
                        current.unicodeScalars.append(characters[index])
                        index += 1
                    }
                }

                guard index < characters.endIndex else {
                    throw CURLParsingError(.unterminatedQuote, token: current)
                }

                index += 1

            case "$" where characters[safe: index + 1] == "'":
                hasToken = true
                index += 2
                try readANSICQuoted(characters, index: &index, into: &current)

            case "\\":
                hasToken = true
                index += 1

                guard index < characters.endIndex else {
                    throw CURLParsingError(.danglingEscape)
                }

                current.unicodeScalars.append(characters[index])
                index += 1

            default:
                hasToken = true
                current.unicodeScalars.append(character)
                index += 1
            }
        }

        flush()
        return tokens
    }

    // MARK: - Private static methods

    /// `\<newline>` (and `\<CRLF>`) removed outright. That is what a shell does before a
    /// command is ever tokenized, and it is how multi-line "copy as cURL" output is written.
    ///
    /// A backslash before a lone carriage return is not a continuation and is left for the
    /// tokenizer, which escapes the carriage return.
    private static func removingLineContinuations(_ command: String) -> String {
        var result = String.UnicodeScalarView()
        var iterator = command.unicodeScalars.makeIterator()

        while let scalar = iterator.next() {
            guard scalar == "\\" else {
                result.append(scalar)
                continue
            }

            var lookahead = iterator

            switch lookahead.next() {
            case "\n":
                iterator = lookahead
            case "\r":
                if lookahead.next() == "\n" {
                    iterator = lookahead
                } else {
                    result.append(scalar)
                }
            default:
                result.append(scalar)
            }
        }

        return String(result)
    }

    /// Reads the body of a `$'...'` literal, starting just past the opening `$'`.
    ///
    /// A `\xHH` escape is one raw *byte*, not one character: consecutive ones are collected and
    /// decoded together as UTF-8, the way the shell hands them to curl. `curlShellQuote` (what
    /// `.description(.cURL)` emits) writes every byte of any non-ASCII value this way, so
    /// turning each byte into its own Unicode scalar instead (Latin-1) re-encoded `é`
    /// (`\xc3\xa9`) as the two characters `Ã©` on the way back out.
    private static func readANSICQuoted(
        _ characters: [Unicode.Scalar],
        index: inout Int,
        into current: inout String
    ) throws {
        var pendingBytes: [UInt8] = []

        func flushPendingBytes() {
            guard !pendingBytes.isEmpty else {
                return
            }

            current += String(decoding: pendingBytes, as: UTF8.self)
            pendingBytes.removeAll(keepingCapacity: true)
        }

        while index < characters.endIndex, characters[index] != "'" {
            guard characters[index] == "\\", index + 1 < characters.endIndex else {
                flushPendingBytes()
                current.unicodeScalars.append(characters[index])
                index += 1
                continue
            }

            let escape = characters[index + 1]

            if escape == "x" {
                let hexStart = index + 2
                let hexEnd = min(hexStart + 2, characters.endIndex)
                var hex = ""
                hex.unicodeScalars.append(contentsOf: characters[hexStart..<hexEnd])

                if !hex.isEmpty, let byte = UInt8(hex, radix: 16) {
                    pendingBytes.append(byte)
                    index = hexEnd
                    continue
                }
            }

            flushPendingBytes()

            switch escape {
            case "n":
                current.unicodeScalars.append("\n")
                index += 2
            case "t":
                current.unicodeScalars.append("\t")
                index += 2
            case "r":
                current.unicodeScalars.append("\r")
                index += 2
            case "\\", "'", "\"":
                current.unicodeScalars.append(escape)
                index += 2
            case "0":
                current.unicodeScalars.append("\0")
                index += 2
            default:
                // Includes a malformed `\x` (no valid hex digits after it), kept as a literal
                // `x` exactly as before.
                current.unicodeScalars.append(escape)
                index += 2
            }
        }

        flushPendingBytes()

        guard index < characters.endIndex else {
            throw CURLParsingError(.unterminatedQuote, token: current)
        }

        index += 1
    }
}

// MARK: - [Unicode.Scalar] extension

extension Array where Element == Unicode.Scalar {

    fileprivate subscript(safe index: Int) -> Unicode.Scalar? {
        indices.contains(index) ? self[index] : nil
    }
}
