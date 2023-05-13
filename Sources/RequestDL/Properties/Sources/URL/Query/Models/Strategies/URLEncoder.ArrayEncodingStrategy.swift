/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    /// Defines strategies for encoding index key in a url encoded format
    public enum ArrayEncodingStrategy: URLSingleEncodingStrategy {

        /// Uses no index in the encoding. This is the default.
        case droppingIndex

        /// Encodes the index in square brackets, e.g. `[0]`.
        case subscripted

        /// Encodes the index as a dot followed by the index value, e.g. `.1`.
        case accessMember

        /// Encodes the index using a custom closure that takes an `Int` and a
        /// `URLEncoder.Encoder` as input parameters and throws an error.
        case custom(@Sendable (Int, URLEncoder.Encoder) throws -> Void)

        // MARK: - Internal methods

        func encode(_ index: Int, in encoder: URLEncoder.Encoder) throws {
            switch self {
            case .droppingIndex:
                try encodeDroppingIndex(index, in: encoder)
            case .subscripted:
                try encodeSubscripted(index, in: encoder)
            case .accessMember:
                try encodeAccessMember(index, in: encoder)
            case .custom(let closure):
                try closure(index, encoder)
            }
        }

        // MARK: - Private methods

        private func encodeDroppingIndex(_ index: Int, in encoder: URLEncoder.Encoder) throws {
           var container = encoder.keyContainer()
           try container.encode("")
       }

        private func encodeSubscripted(_ index: Int, in encoder: URLEncoder.Encoder) throws {
           var container = encoder.keyContainer()
           try container.encode("[\(index)]")
       }

        private func encodeAccessMember(_ index: Int, in encoder: URLEncoder.Encoder) throws {
           var container = encoder.keyContainer()
           try container.encode(".\(index)")
       }
    }
}
