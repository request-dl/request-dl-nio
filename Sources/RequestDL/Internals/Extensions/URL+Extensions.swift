//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import struct FoundationEssentials.URL
import struct FoundationEssentials.URLComponents
import class FoundationEssentials.FileManager
#else
import struct Foundation.URL
import struct Foundation.URLComponents
import class Foundation.FileManager
#endif

extension URL {

    private func unknown_absolutePath(percentEncoded: Bool) -> String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return ""
        }

        let path = components.path.removingPercentEncoding ?? components.path
        components.path =
            percentEncoded
            ? {
                (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")
            }() : path
        return components.path
    }

    #if canImport(Darwin)
    private func darwin_absolutePath(percentEncoded: Bool) -> String {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return path(percentEncoded: percentEncoded)
        } else {
            return unknown_absolutePath(percentEncoded: percentEncoded)
        }
    }
    #endif

    func absolutePath(percentEncoded: Bool = true) -> String {
        #if canImport(Darwin)
        return absoluteURL.darwin_absolutePath(percentEncoded: percentEncoded)
        #else
        return absoluteURL.unknown_absolutePath(percentEncoded: percentEncoded)
        #endif
    }

    func createPathIfNeeded() throws {
        let path = absolutePath(percentEncoded: false)

        let directories = deletingLastPathComponent()

        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(
                at: directories,
                withIntermediateDirectories: true
            )
        }

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
    }

    func removeIfNeeded() throws {
        let path = absolutePath(percentEncoded: false)

        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(at: self)
        }
    }
}
