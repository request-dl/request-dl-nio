/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

private struct LoggerRequestEnvironmentKey: RequestEnvironmentKey {
    static var defaultValue: Logger? {
        nil
    }
}

extension RequestEnvironmentValues {

    public internal(set) var logger: Logger? {
        get { self[LoggerRequestEnvironmentKey.self] }
        set { self[LoggerRequestEnvironmentKey.self] = newValue }
    }
}
