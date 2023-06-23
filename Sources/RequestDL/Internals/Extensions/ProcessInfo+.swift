/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension ProcessInfo {

    var userAgent: String {
        let appName = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName

        let appVersion = Bundle.main.versionString ?? "1.0.0"

        let systemName = ProcessInfo.processInfo.hostName
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersion

        let systemVersionString = String(
            format: "%d.%d.%d",
            systemVersion.majorVersion, systemVersion.minorVersion, systemVersion.patchVersion
        )

        return "\(appName)/\(appVersion) \(systemName)/\(systemVersionString)"
    }
}
