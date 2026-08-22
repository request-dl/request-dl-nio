//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
import Foundation

extension Bundle {

    /// A resource name split into the pieces `Bundle` wants.
    private struct File {

        package let name: String
        package let `extension`: String?
        package let subdirectory: String?
    }

    /// Splits `"dir/file.pem"` into its directory, stem and extension.
    ///
    /// - Note: A name with no extension keeps everything before the last slash as the
    /// subdirectory, and a name with no slash has no subdirectory at all.
    private func resolve(name: String) -> File {
        guard !name.isEmpty else {
            return .init(
                name: name,
                extension: nil,
                subdirectory: nil
            )
        }

        var components = name.split(separator: "/")
        let nameWithExtension = components.removeLast()

        let subdirectory = components.isEmpty ? nil : components.joined(separator: "/")

        guard nameWithExtension.contains(".") else {
            return .init(
                name: String(nameWithExtension),
                extension: nil,
                subdirectory: subdirectory
            )
        }

        var nameComponents = nameWithExtension.split(separator: ".")
        let `extension` = nameComponents.removeLast()

        return .init(
            name: nameComponents.joined(separator: "."),
            extension: String(`extension`),
            subdirectory: subdirectory
        )
    }

    /// Locates a resource by a path-like name, with or without an extension.
    package func resolveURL(forResourceName name: String) -> URL? {
        let file = resolve(name: name)

        let urls =
            urls(
                forResourcesWithExtension: file.extension,
                subdirectory: file.subdirectory,
                localization: nil
            ) ?? []

        return urls.first { url in
            guard let pathExtension = file.extension else {
                return url.deletingPathExtension().lastPathComponent == file.name
            }

            return url.lastPathComponent == "\(file.name).\(pathExtension)"
        }
    }

    /// The resource directory, reconstructed for the bundles that do not report one.
    package var normalizedResourceURL: URL {
        if let resourceURL {
            return resourceURL
        }

        return
            bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
    }
}

extension Bundle {

    /// `CFBundleShortVersionString`, the marketing version.
    package var versionString: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

#endif
