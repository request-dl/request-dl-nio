/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    /// A container for URL-encoded keys.
    public struct KeyContainer {

        private var key: String?
        private let encoder: URLEncoder.Encoder

        init(_ encoder: URLEncoder.Encoder) {
            self.encoder = encoder
        }

        /// Encodes the given key.
        ///
        /// - Parameter key: The key to be encoded.
        ///
        /// - Throws: An error if the key cannot be encoded.
        public mutating func encode(_ key: String) throws {
            self.key = key
            try encoder.setKey(key)
        }

        /// Drops the key of the current container.
        ///
        /// - Throws: An error if the container does not have a key to drop.
        public mutating func dropKey() throws {
            self.key = nil
            try encoder.setKey(nil)
        }

        /// Returns the unkeyed representation of the current key container.
        ///
        /// - Returns: The unkeyed representation of the current key container.
        ///
        /// - Throws: An error if the container cannot be represented as an unkeyed key.
        public func unkeyed() throws -> String {
            guard let key else {
                throw URLEncoderError(.unset)
            }

            return key
        }
    }
}
