/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    /// The encoder for encoding a value or key.
    public class Encoder {

        fileprivate var key: Value
        fileprivate var value: Value

        init() {
            key = .none
            value = .none
        }

        /// The string representation of whitespace when encoding.
        public var whitespaceRepresentable: String?

        /// Creates a new value container for encoding a value.
        ///
        /// - Returns: A new value container.
        public func valueContainer() -> ValueContainer {
            .init(self)
        }

        /// Creates a new key container for encoding a key.
        ///
        /// - Returns: A new key container.
        public func keyContainer() -> KeyContainer {
            .init(self)
        }
    }
}

extension URLEncoder.Encoder {

    func getKey() throws -> String? {
        switch key {
        case .drop:
            return nil
        case .some(let key):
            return key
        case .none:
            throw URLEncoderError(.unset)
        }
    }

    func setKey(_ key: String?) throws {
        guard self.key == .none else {
            throw URLEncoderError(.alreadySet)
        }

        self.key = key.map { .some($0) } ?? .drop
    }
}

extension URLEncoder.Encoder {

    func getValue() throws -> String? {
        switch value {
        case .drop:
            return nil
        case .some(let value):
            return value
        case .none:
            throw URLEncoderError(.unset)
        }
    }

    func setValue(_ value: String?) throws {
        guard self.value == .none else {
            throw URLEncoderError(.alreadySet)
        }

        self.value = value.map { .some($0) } ?? .drop
    }
}

extension URLEncoder.Encoder {

    fileprivate enum Value: Equatable {
        case some(String)
        case drop
        case none
    }
}
