/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

private struct LoggerRequestEnvironmentKey: RequestEnvironmentKey {
    static let defaultValue = Logger.disabled
}

extension RequestEnvironmentValues {

    public internal(set) var logger: Logger {
        get { self[LoggerRequestEnvironmentKey.self] }
        set { self[LoggerRequestEnvironmentKey.self] = newValue }
    }
}
