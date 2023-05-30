/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

public struct Log: Property {

    private struct Node: PropertyNode {

        let logger: Logger

        func make(_ make: inout Make) async throws {
            make.logger = logger
        }
    }

    // MARK: - Public properties

    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let logger: Logger

    // MARK: - Inits

    public init(_ logger: Logger) {
        self.logger = logger
    }

    // MARK: - Public static methods
    public static func _makeProperty(
        property: _GraphValue<Log>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(logger: property.logger))
    }
}
