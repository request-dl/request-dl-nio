/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    /// The encoder for encoding a value or key.
    public final class Encoder: @unchecked Sendable {

        // MARK: - Public properties

        /// The string representation of whitespace when encoding.
        public var whitespaceRepresentable: String? {
            get { lock.withLock { _whitespaceRepresentable } }
            set { lock.withLock { _whitespaceRepresentable = newValue } }
        }

        // MARK: - Private properties

        private let lock = Lock()

        private var key: Value {
            get { lock.withLock { _key } }
            set { lock.withLock { _key = newValue } }
        }

        private var value: Value {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }

        // MARK: - Unsafe properties

        private var _key: Value
        private var _value: Value

        private var _whitespaceRepresentable: String?

        // MARK: - Inits

        init() {
            _key = .none
            _value = .none
        }

        // MARK: - Public methods

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

        // MARK: - Internal methods

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

        func setKey(_ key: String?) throws {
            try lock.withLockVoid {
                guard _key == .none else {
                    throw URLEncoderError(.alreadySet)
                }

                _key = key.map { .some($0) } ?? .drop
            }
        }

        func setValue(_ value: String?) throws {
            try lock.withLockVoid {
                guard _value == .none else {
                    throw URLEncoderError(.alreadySet)
                }

                _value = value.map { .some($0) } ?? .drop
            }
        }
    }
}

extension URLEncoder.Encoder {

    fileprivate enum Value: Sendable, Hashable {
        case some(String)
        case drop
        case none
    }
}
