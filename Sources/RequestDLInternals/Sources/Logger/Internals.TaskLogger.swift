//
// See LICENSE for this package's licensing information.
//

import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

extension Internals {

    package struct TaskLogger: Sendable, Hashable {

        package let logger: Logger

        private let id: String
        private let baseURL: String
        private let pathComponents: [String]

        package init?(baseURL: String, pathComponents: [String], logger: Logger?) {
            guard let logger else {
                return nil
            }

            self.id = UUID().uuidString
            self.baseURL = baseURL
            self.pathComponents = pathComponents
            self.logger = logger
        }

        package static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.baseURL == rhs.baseURL
                && lhs.pathComponents == rhs.pathComponents
        }

        package func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(baseURL)
            hasher.combine(pathComponents)
        }

        package func log(
            level: Logger.Level,
            _ message: @escaping @autoclosure () -> Logger.Message,
            additionalMetadata: @escaping @autoclosure () -> Logger.Metadata? = nil,
            file: String = #file,
            function: String = #function,
            line: UInt = #line
        ) {
            logger.log(
                level: level,
                message(),
                metadata: [
                    "id": .string(id),
                    "base_url": .string(baseURL),
                    "path_components": .array(pathComponents.map { .string($0) }),
                ].merging(additionalMetadata() ?? [:]) { $1 },
                file: file,
                function: function,
                line: line
            )
        }
    }
}
