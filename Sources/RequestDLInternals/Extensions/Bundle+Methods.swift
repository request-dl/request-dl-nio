/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Bundle {

    private struct File {
        let name: String
        let `extension`: String?
        let subdirectory: String?
    }

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

        if !nameWithExtension.contains(".") {
            return .init(
                name: "\(nameWithExtension)",
                extension: nil,
                subdirectory: components.isEmpty ? nil : components.joined(separator: "/")
            )
        }

        var nameComponents = nameWithExtension.split(separator: ".")
        let `extension` = nameComponents.removeLast()

        return .init(
            name: nameComponents.joined(separator: "."),
            extension: "\(`extension`)",
            subdirectory: components.joined(separator: "/")
        )
    }

    public func resolveURL(forResourceName name: String) -> URL? {
        let file = resolve(name: name)

        let urls = urls(
            forResourcesWithExtension: file.extension,
            subdirectory: file.subdirectory,
            localization: nil
        ) ?? []

        return (urls as [URL]).first(where: {
            if let pathExtension = file.extension {
                return $0.lastPathComponent == "\(file.name).\(pathExtension)"
            } else {
                return $0.deletingPathExtension().lastPathComponent == file.name
            }
        })
    }

    public var normalizedResourceURL: URL {
        if let resourceURL {
            return resourceURL
        }

        return bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
    }
}
