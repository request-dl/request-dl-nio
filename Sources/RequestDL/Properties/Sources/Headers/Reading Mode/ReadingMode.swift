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
    /// - Parameter length: The fixed length of data to be read. Must be greater than zero.
    ///
    /// - Precondition: `length > 0`. A non-positive chunk size can never make progress: every
    /// chunk would be silently discarded, and the request would complete with an empty body
    /// instead of raising an error.
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
    /// > Important: There is no limit on how large one item may grow. A source that never sends
    /// the separator keeps filling memory. Use `init(separator:maximumItemSize:)` when the
    /// source is not trusted.
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
    /// > Important: There is no limit on how large one item may grow. A source that never sends
    /// the separator keeps filling memory. Use `init(separator:maximumItemSize:)` when the
    /// source is not trusted.
    ///
    public init<S: StringProtocol>(separator: S) {
        self.init(separator: Array(Data(separator.utf8)))
    }

    ///
    /// Creates a reading mode with a separator for reading data, and a limit on how large one item
    /// may grow.
    ///
    /// Without a limit, a separator that never arrives makes the bytes pile up in memory: a server
    /// that sends a long enough stream with no line break keeps growing the item until the process
    /// runs out of memory, and the download's flow control cannot slow it down. With one, reading
    /// fails with ``ReadingModeItemTooLargeError`` as soon as an item cannot fit, and the items
    /// that came before it have already been delivered.
    ///
    /// - Parameters:
    ///   - separator: The separator used for reading data. Data will be read up to and including
    ///   the separator.
    ///   - maximumItemSize: The most bytes one item may take, separator included. Must be greater
    ///   than zero.
    ///
    /// - Precondition: `maximumItemSize > 0`.
    public init(separator: [UInt8], maximumItemSize: Int) {
        precondition(
            maximumItemSize > 0,
            "ReadingMode(separator:maximumItemSize:) requires maximumItemSize > 0; \(maximumItemSize) fits no item."
        )
        mode = .separator(separator, maximumItemSize: maximumItemSize)
    }

    ///
    /// Creates a reading mode with a separator for reading data, and a limit on how large one item
    /// may grow.
    ///
    /// See `init(separator:maximumItemSize:)` taking bytes for what the limit is for.
    ///
    /// - Parameters:
    ///   - separator: The separator used for reading data, such as a `String` or `Substring`.
    ///   - maximumItemSize: The most bytes one item may take, separator included. Must be greater
    ///   than zero.
    ///
    /// - Precondition: `maximumItemSize > 0`.
    public init<S: StringProtocol>(separator: S, maximumItemSize: Int) {
        self.init(separator: Array(Data(separator.utf8)), maximumItemSize: maximumItemSize)
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
