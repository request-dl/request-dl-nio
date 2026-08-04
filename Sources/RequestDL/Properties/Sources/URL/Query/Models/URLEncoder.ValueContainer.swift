//
// See LICENSE for this package's licensing information.
//

extension URLEncoder {

    /// A container for URL-encoded values.
    public struct ValueContainer: Sendable {

        // MARK: - Private properties

        private var value: String?
        private let encoder: URLEncoder.Encoder

        // MARK: - Inits

        init(_ encoder: URLEncoder.Encoder) {
            self.encoder = encoder
        }

        // MARK: - Public methods

        /// Encodes the given value.
        ///
        /// - Parameter value: The value to be encoded.
        ///
        /// - Throws: ``URLEncoderError`` when this container has already encoded or dropped
        /// something. Each container writes once.
        public mutating func encode(_ value: String) throws {
            self.value = value
            try encoder.setValue(value)
        }

        /// Drops the value, and with it the whole query item.
        ///
        /// A dropped value makes the pair unrepresentable, so the encoder emits nothing at all
        /// for it rather than a bare `key=`. Use ``encode(_:)`` with an empty string for that.
        ///
        /// - Note: Renamed from `dropKey()` in 4.0. It never touched the key: it lives on the
        /// value container and calls the encoder's value setter. The name and the doc comment
        /// were copied from ``KeyContainer/dropKey()`` and described the wrong half of the
        /// pair.
        ///
        /// - Throws: ``URLEncoderError`` when this container has already written.
        public mutating func dropValue() throws {
            self.value = nil
            try encoder.setValue(nil)
        }

        /// Returns the unkeyed representation of the current value container.
        ///
        /// - Returns: The unkeyed representation of the current value container.
        ///
        /// - Throws: ``URLEncoderError`` when nothing has been encoded, or when the value was
        /// dropped.
        public func unkeyed() throws -> String {
            guard let value else {
                throw URLEncoderError(.unset)
            }

            return value
        }
    }
}
