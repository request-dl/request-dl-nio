/*
 See LICENSE for this package's licensing information.
*/

import Logging

extension Logger {

    static let disabled = Logger(label: "RDL-do-not-log") { _ in
        SwiftLogNoOpLogHandler()
    }
}
