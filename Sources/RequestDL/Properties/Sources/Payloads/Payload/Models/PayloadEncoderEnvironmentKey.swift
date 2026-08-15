//
// See LICENSE for this package's licensing information.
//

private struct PayloadEncoderKey: RequestEnvironmentKey {
    static var defaultValue: (any PayloadEncoder)? { nil }
}

extension RequestEnvironmentValues {

    var payloadEncoder: (any PayloadEncoder)? {
        get { self[PayloadEncoderKey.self] }
        set { self[PayloadEncoderKey.self] = newValue }
    }
}

extension Property {

    ///
    /// Sets a default ``PayloadEncoder`` for every `Payload(_:encoder:contentType:)` in scope
    /// that passes `encoder: nil`.
    ///
    /// - Parameter encoder: The encoder to use when a `Payload` does not specify one.
    /// - Returns: A modified property with the specified default encoder.
    ///
    public func payloadEncoder<Encoder: PayloadEncoder>(_ encoder: Encoder) -> some Property {
        environment(\.payloadEncoder, encoder)
    }
}
