/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {
    
    public struct ValueContainer {

        private var value: String?
        private let encoder: URLEncoder.Encoder
        
        init(_ encoder: URLEncoder.Encoder) {
            self.encoder = encoder
        }
        
        public mutating func encode(_ value: String) throws {
            self.value = value
            try encoder.setValue(value)
        }

        public mutating func dropKey() throws {
            self.value = nil
            try encoder.setValue(nil)
        }

        public func unkeyed() throws -> String {
            guard let value else {
                throw URLEncoderError(.unset)
            }

            return value
        }
    }
}
