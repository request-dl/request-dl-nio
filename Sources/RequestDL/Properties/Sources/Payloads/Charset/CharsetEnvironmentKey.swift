//
// See LICENSE for this package's licensing information.
//

private struct CharsetEnvironmentKey: RequestEnvironmentKey {

    static var defaultValue: Charset {
        .utf8
    }
}

extension RequestEnvironmentValues {

    var charset: Charset {
        get { self[CharsetEnvironmentKey.self] }
        set { self[CharsetEnvironmentKey.self] = newValue }
    }
}

extension Property {

    ///
    /// Specifies the character set (charset) to be used for encoding data.
    ///
    /// Applies to payloads whose bytes are produced from text: a `String` payload, and any
    /// payload encoded as `application/x-www-form-urlencoded`. Those encode through the charset
    /// and declare it on the `Content-Type`.
    ///
    /// > Important: It has no effect on JSON payloads. `JSONEncoder` and `JSONSerialization`
    /// always emit UTF-8, so the charset is neither used nor declared there. Declaring it anyway
    /// would put an encoding on the header that the body does not have.
    ///
    /// It also has no effect on `Data` and file payloads, whose bytes are opaque and were not
    /// produced here.
    ///
    /// - Parameter charset: The character set to use for encoding.
    /// - Returns: A modified property with the specified charset.
    ///
    public func charset(_ charset: Charset) -> some Property {
        environment(\.charset, charset)
    }
}
