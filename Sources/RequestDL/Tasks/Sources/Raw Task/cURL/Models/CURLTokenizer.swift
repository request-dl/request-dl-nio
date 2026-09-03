//
// See LICENSE for this package's licensing information.
//

/// Splits a curl command line into shell-style tokens.
///
/// Not a full POSIX shell — no variable expansion, no command substitution, no globbing — but it
/// handles the quoting a "copy as cURL" export actually uses: single quotes (literal), double
/// quotes (`\\`, `\"`, `\$`, `` \` `` escapes), backslash-escaping outside quotes, and bash's
/// `$'...'` ANSI-C quoting (`\n \t \r \\ \' \" \xHH`). A trailing `\` at the end of a physical
/// line is a continuation and is removed before tokenizing even begins, since multi-line curl
/// exports are the common case in practice.
enum CURLTokenizer {

    // MARK: - Internal static methods

    static func tokenize(_ command: String) throws -> [String] {
        let characters = Array(removingLineContinuations(command))

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
                    current.append(characters[index])
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
                        "\"\\$`".contains(characters[index + 1])
                    {
                        current.append(characters[index + 1])
                        index += 2
                    } else {
                        current.append(characters[index])
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

                current.append(characters[index])
                index += 1

            default:
                hasToken = true
                current.append(character)
                index += 1
            }
        }

        flush()
        return tokens
    }

    // MARK: - Private static methods

    /// `\<newline>` (and `\<CRLF>`) removed outright — that is what a shell does before a
    /// command is ever tokenized, and it is how multi-line "copy as cURL" output is written.
    private static func removingLineContinuations(_ command: String) -> String {
        var result = ""
        var iterator = command.makeIterator()

        while let character = iterator.next() {
            guard character == "\\" else {
                result.append(character)
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
                    result.append(character)
                }
            default:
                result.append(character)
            }
        }

        return result
    }

    /// Reads the body of a `$'...'` literal, starting just past the opening `$'`.
    private static func readANSICQuoted(
        _ characters: [Character],
        index: inout Int,
        into current: inout String
    ) throws {
        while index < characters.endIndex, characters[index] != "'" {
            guard characters[index] == "\\", index + 1 < characters.endIndex else {
                current.append(characters[index])
                index += 1
                continue
            }

            let escape = characters[index + 1]

            switch escape {
            case "n":
                current.append("\n")
                index += 2
            case "t":
                current.append("\t")
                index += 2
            case "r":
                current.append("\r")
                index += 2
            case "\\", "'", "\"":
                current.append(escape)
                index += 2
            case "0":
                current.append("\0")
                index += 2
            case "x":
                let hexStart = index + 2
                let hexEnd = min(hexStart + 2, characters.endIndex)
                let hex = String(characters[hexStart..<hexEnd])

                if let byte = UInt8(hex, radix: 16), !hex.isEmpty {
                    current.append(Character(UnicodeScalar(byte)))
                    index = hexEnd
                } else {
                    current.append(escape)
                    index += 2
                }
            default:
                current.append(escape)
                index += 2
            }
        }

        guard index < characters.endIndex else {
            throw CURLParsingError(.unterminatedQuote, token: current)
        }

        index += 1
    }
}

// MARK: - [Character] extension

extension Array where Element == Character {

    fileprivate subscript(safe index: Int) -> Character? {
        indices.contains(index) ? self[index] : nil
    }
}
