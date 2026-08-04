//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import class Foundation.ProcessInfo
#endif

#if canImport(Darwin)
import class Foundation.Bundle
#endif

extension ProcessInfo {

    /// A stable identifier for the running application.
    ///
    /// The bundle identifier where there is a bundle, the process name everywhere else. Used
    /// for the `User-Agent` and to name the on-disk cache directory, so it wants to be the same
    /// string across launches of the same program, not globally unique.
    var applicationIdentifier: String {
        #if canImport(Darwin)
        return Bundle.main.bundleIdentifier ?? processName
        #else
        return processName
        #endif
    }

    /// The application's marketing version, when the platform has a notion of one.
    var applicationVersion: String? {
        #if canImport(Darwin)
        return Bundle.main.versionString
        #else
        return nil
        #endif
    }

    /// A `User-Agent` in the `product/version` shape RFC 9110 describes.
    var userAgent: String {
        let version = operatingSystemVersion

        // Interpolation rather than `String(format:)`. The latter is not part of
        // `FoundationEssentials`, so it would not have compiled off Apple, and it is the slower
        // and less checkable of the two anyway.
        let systemVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        return "\(applicationIdentifier)/\(applicationVersion ?? "1.0.0") \(Self.systemName)/\(systemVersion)"
    }

    /// The operating system, not the machine.
    ///
    /// - Important: Must not be `hostName`. That puts the user's machine name into the
    /// `User-Agent` of every outgoing request — on a laptop that is usually the owner's real
    /// name, a privacy leak — and it is useless for the header's actual purpose anyway, since
    /// a server cannot tell platforms apart from a machine name.
    private static var systemName: String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(visionOS)
        return "visionOS"
        #elseif os(Linux)
        return "Linux"
        #elseif os(Android)
        return "Android"
        #elseif os(Windows)
        return "Windows"
        #else
        return "Unknown"
        #endif
    }
}
