/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A struct representing the reading mode used for reading data.
@RequestActor
public struct ReadingMode: Property {

    private let mode: Internals.Response.ReadingMode

    /// Creates a reading mode with a fixed length for reading data.
    ///
    /// - Parameter length: The fixed length of data to be read.
    public init(length: Int) {
        mode = .length(length)
    }

    /// Creates a reading mode with a separator for reading data.
    ///
    /// - Parameter separator: The separator used for reading data. Data will be read up to and
    /// including the separator.
    public init(separator: [UInt8]) {
        mode = .separator(separator)
    }

    /// Creates a reading mode with a separator for reading data.
    ///
    /// - Parameter separator: The separator used for reading data. Data will be read up to and
    /// including the separator.
    ///
    /// - Note: The separator can be a string protocol conforming type, such as `String` or
    /// `Substring`.
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
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<ReadingMode>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(mode: property.mode))
    }
}
