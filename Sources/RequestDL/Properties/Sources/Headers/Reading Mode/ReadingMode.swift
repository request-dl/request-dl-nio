//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A struct representing the reading mode used for reading data.
public struct ReadingMode: Property {

    private struct Node: PropertyNode {

        let mode: Internals.DownloadStep.ReadingMode

        func make(_ make: inout Make) async throws {
            make.requestConfiguration.readingMode = mode
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let mode: Internals.DownloadStep.ReadingMode

    // MARK: - Inits

    ///
    /// Creates a reading mode with a fixed length for reading data.
    ///
    /// - Parameter length: The fixed length of data to be read. Must be greater than zero: a
    /// chunk size of zero (or negative) can never make progress, since nothing is ever read.
    ///
    /// - Precondition: `length > 0`. `Internals.DownloadBuffer._appendByLength` computes each
    /// read as `min(receivedBytes, length - buffer.readableBytes)`, which is `0` (or negative,
    /// clamped to a `0`-length read by the same comparison) whenever `length <= 0` -- and a
    /// zero-length read is never satisfied (`Internals.Buffer.readData(0)` always returns
    /// `nil`), so every chunk this reading mode receives would be silently discarded forever,
    /// the request completing with an empty body and no error raised anywhere.
    public init(length: Int) {
        precondition(length > 0, "ReadingMode(length:) requires length > 0; \(length) can never make progress.")
        mode = .length(length)
    }

    ///
    /// Creates a reading mode with a separator for reading data.
    ///
    /// - Parameter separator: The separator used for reading data. Data will be read up to and
    /// including the separator.
    ///
    public init(separator: [UInt8]) {
        mode = .separator(separator)
    }

    ///
    /// Creates a reading mode with a separator for reading data.
    ///
    /// - Parameter separator: The separator used for reading data. Data will be read up to and
    /// including the separator.
    ///
    /// > Note: The separator can be a string protocol conforming type, such as `String` or
    /// `Substring`.
    ///
    public init<S: StringProtocol>(separator: S) {
        self.init(separator: Array(Data(separator.utf8)))
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<ReadingMode>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(mode: property.mode))
    }
}
