/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

extension Internals {

    struct TaskLogger: Sendable, Hashable {

        let logger: Logger

        private let id: String
        private let baseURL: String
        private let pathComponents: [String]

        init?(requestConfiguration: RequestConfiguration, logger: Logger?) {
            guard let logger else {
                return nil
            }

            self.id = UUID().uuidString
            baseURL = requestConfiguration.baseURL
            pathComponents = requestConfiguration.pathComponents
            self.logger = logger
        }

        static func == (_ lhs: Self, _ rhs: Self) -> Bool {
            lhs.id == rhs.id
                && lhs.baseURL == rhs.baseURL
                && lhs.pathComponents == rhs.pathComponents
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(baseURL)
            hasher.combine(pathComponents)
        }

        func log(
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
                    "path_components": .array(pathComponents.map { .string($0) })
                ].merging(additionalMetadata() ?? [:]) { $1 },
                file: file,
                function: function,
                line: line
            )
        }
    }
}
