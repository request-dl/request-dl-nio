/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct ReadingMode: Property {

    private let mode: Internals.Response.ReadingMode

    public init(length: Int) {
        mode = .length(length)
    }

    public init(separator: [UInt8]) {
        mode = .separator(separator)
    }

    public init<S: StringProtocol>(separator: S) {
        self.init(separator: Array(Data(separator.utf8)))
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension ReadingMode {

    private struct Node: PropertyNode {

        let mode: Internals.Response.ReadingMode

        func make(_ make: inout Make) async throws {
            make.configuration.readingMode = mode
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<ReadingMode>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(Node(mode: property.mode)))
    }
}
