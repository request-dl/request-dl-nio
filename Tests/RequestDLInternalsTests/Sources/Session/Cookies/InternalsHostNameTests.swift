//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDLInternals

struct InternalsHostNameTests {

    @Test(arguments: [
        ("münchen.de", "xn--mnchen-3ya.de"),
        ("bücher.example", "xn--bcher-kva.example"),
        ("рф", "xn--p1ai"),
        ("пример.рф", "xn--e1afmkfd.xn--p1ai"),
        ("例え.jp", "xn--r8jz45g.jp"),
        ("日本語.jp", "xn--wgv71a119e.jp"),
        ("MÜNCHEN.DE", "xn--mnchen-3ya.de"),
        ("Example.COM", "example.com"),
        ("xn--p1ai", "xn--p1ai"),
        ("127.0.0.1", "127.0.0.1"),
        ("::1", "::1"),
        // The decomposed spelling of the same name.
        ("mu\u{308}nchen.de", "xn--mnchen-3ya.de"),
        // The ideographic full stop separates labels.
        ("例え\u{3002}jp", "xn--r8jz45g.jp")
    ])
    func ascii_encodesEveryNonASCIILabelAsPunycode(name: String, expected: String) {
        #expect(Internals.HostName.ascii(name) == expected)
    }

    /// The vectors of RFC 3492 section 7.1 (without the `xn--` prefix, which is IDNA's).
    @Test(arguments: [
        ("ليهمابتكلموشعربي؟", "egbpdaj6bu4bxfgehfvwxn"),
        ("他们为什么不说中文", "ihqwcrb4cv8a8dqg056pqjye"),
        ("Pročprostěnemluvíčesky", "Proprostnemluvesky-uyb24dma41a"),
        ("MajiでKoiする5秒前", "MajiKoi5-783gue6qz075azm5e")
    ])
    func encode_matchesTheRFC3492Vectors(label: String, expected: String) {
        #expect(Internals.HostName.encode(label: label) == "xn--" + expected)
    }
}
