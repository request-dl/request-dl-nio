/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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
        /// - Throws: An error if the value cannot be encoded.
        public mutating func encode(_ value: String) throws {
            self.value = value
            try encoder.setValue(value)
        }

        /// Drops the key of the current container.
        ///
        /// - Throws: An error if the container does not have a key to drop.
        public mutating func dropKey() throws {
            self.value = nil
            try encoder.setValue(nil)
        }

        /// Returns the unkeyed representation of the current value container.
        ///
        /// - Returns: The unkeyed representation of the current value container.
        ///
        /// - Throws: An error if the container cannot be represented as an unkeyed value.
        public func unkeyed() throws -> String {
            guard let value else {
                throw URLEncoderError(.unset)
            }

            return value
        }
    }
}
