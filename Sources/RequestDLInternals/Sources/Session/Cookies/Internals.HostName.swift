//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
import Foundation
#else
// The standard library's own NFC, since `precomposedStringWithCanonicalMapping` belongs to the full
// `Foundation`, and linking that is what the package avoids off Apple platforms.
@_spi(_Unicode) import Swift
#endif

extension Internals {

    /// The one spelling a host name is compared in: lowercase ASCII, with every label that is not
    /// ASCII in its Punycode form (`xn--...`).
    ///
    /// A Public Suffix List is written in Unicode, while a host reaches the jar as whichever of the
    /// two spellings the URL, the `Domain` attribute and the platform's `Foundation` happened to
    /// use. Compared as they come, `Domain=рф` and a rule for `xn--p1ai` are different strings, and
    /// a cookie for a public suffix gets through. Every host, `Domain` and rule is put through
    /// here before it is compared.
    ///
    /// This is the encoding half of IDNA (RFC 3492 over NFC-normalized, lowercased labels), which is
    /// what comparing needs. It is not the full UTS #46 mapping: characters that mapping would
    /// rewrite (the German `ß`, for instance) keep their own code point.
    package enum HostName {

        // MARK: - Internal static methods

        package static func ascii(_ name: String) -> String {
            let lowercased = name.lowercased()

            guard !lowercased.unicodeScalars.allSatisfy(\.isASCII) else {
                return lowercased
            }

            return labels(of: normalized(lowercased))
                .map { encode(label: $0) }
                .joined(separator: ".")
        }

        private static func normalized(_ name: String) -> String {
            #if canImport(Darwin)
            name.precomposedStringWithCanonicalMapping
            #else
            String(String.UnicodeScalarView(name._nfc))
            #endif
        }

        /// RFC 3492 section 6.3 for one label: `label` unchanged when it is ASCII.
        package static func encode(label: String) -> String {
            guard !label.unicodeScalars.allSatisfy(\.isASCII) else {
                return label
            }

            return "xn--" + punycode(label.unicodeScalars.map(\.value))
        }

        // MARK: - Private static methods

        /// IDNA treats the ideographic full stops as dots too.
        private static func labels(of name: String) -> [String] {
            name.split(
                omittingEmptySubsequences: false,
                whereSeparator: { $0 == "." || $0 == "\u{3002}" || $0 == "\u{FF0E}" || $0 == "\u{FF61}" }
            ).map(String.init)
        }

        private static let base = 36
        private static let minimumThreshold = 1
        private static let maximumThreshold = 26
        private static let skew = 38
        private static let damp = 700

        private static func punycode(_ input: [UInt32]) -> String {
            var output = input.filter { $0 < 0x80 }.compactMap(Unicode.Scalar.init).map(Character.init)
            let basicCount = output.count
            var handled = basicCount

            if basicCount > 0 {
                output.append("-")
            }

            var codePoint = 0x80
            var delta = 0
            var bias = 72

            while handled < input.count {
                let next = input.map(Int.init).filter { $0 >= codePoint }.min() ?? codePoint
                delta += (next - codePoint) * (handled + 1)
                codePoint = next

                for scalar in input.map(Int.init) {
                    if scalar < codePoint {
                        delta += 1
                    }

                    guard scalar == codePoint else {
                        continue
                    }

                    var quotient = delta
                    var k = base

                    while true {
                        let threshold =
                            k <= bias ? minimumThreshold : (k >= bias + maximumThreshold ? maximumThreshold : k - bias)

                        guard quotient >= threshold else {
                            break
                        }

                        output.append(digit(threshold + (quotient - threshold) % (base - threshold)))
                        quotient = (quotient - threshold) / (base - threshold)
                        k += base
                    }

                    output.append(digit(quotient))
                    bias = adapt(delta: delta, points: handled + 1, isFirst: handled == basicCount)
                    delta = 0
                    handled += 1
                }

                delta += 1
                codePoint += 1
            }

            return String(output)
        }

        private static func adapt(delta: Int, points: Int, isFirst: Bool) -> Int {
            var delta = isFirst ? delta / damp : delta / 2
            delta += delta / points

            var k = 0

            while delta > ((base - minimumThreshold) * maximumThreshold) / 2 {
                delta /= base - minimumThreshold
                k += base
            }

            return k + (base - minimumThreshold + 1) * delta / (delta + skew)
        }

        private static func digit(_ value: Int) -> Character {
            Character(Unicode.Scalar(UInt8(value < 26 ? value + 97 : value - 26 + 48)))
        }
    }
}
