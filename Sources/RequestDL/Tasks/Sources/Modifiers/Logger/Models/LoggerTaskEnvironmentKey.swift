/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

private struct LoggerTaskEnvironmentKey: TaskEnvironmentKey {
    static let defaultValue = Logger.disabled
}

extension TaskEnvironmentValues {

    var logger: Logger {
        get { self[LoggerTaskEnvironmentKey.self] }
        set { self[LoggerTaskEnvironmentKey.self] = newValue }
    }
}
