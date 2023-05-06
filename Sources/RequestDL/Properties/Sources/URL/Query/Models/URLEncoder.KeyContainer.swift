/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    public struct KeyContainer {

        private var key: String?
        private let encoder: URLEncoder.Encoder

        init(_ encoder: URLEncoder.Encoder) {
            self.encoder = encoder
        }

        public mutating func encode(_ key: String) throws {
            self.key = key
            try encoder.setKey(key)
        }

        public mutating func dropKey() throws {
            self.key = nil
            try encoder.setKey(nil)
        }

        public func unkeyed() throws -> String {
            guard let key else {
                throw URLEncoderError(.unset)
            }

            return key
        }
    }
}
