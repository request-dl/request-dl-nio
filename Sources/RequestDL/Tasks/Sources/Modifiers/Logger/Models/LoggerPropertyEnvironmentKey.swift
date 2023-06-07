/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

private struct LoggerPropertyEnvironmentKey: PropertyEnvironmentKey {
    static let defaultValue = Logger.disabled
}

extension PropertyEnvironmentValues {

    var logger: Logger {
        get { self[LoggerPropertyEnvironmentKey.self] }
        set { self[LoggerPropertyEnvironmentKey.self] = newValue }
    }
}
