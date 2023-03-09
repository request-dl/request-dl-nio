/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Bundle {

    func resolve(name: String) -> (name: String, subdirectory: String?) {
        guard name.contains("/") else {
            return (name, nil)
        }

        var components = name.split(separator: "/")

        return (
            name: String(components.removeLast()),
            subdirectory: String(components.joined(separator: "/"))
        )
    }

    func resolveURL(forResourceName name: String) -> URL? {
        let (name, subdirectory) = resolve(name: name)

        let urls = urls(
            forResourcesWithExtension: nil,
            subdirectory: subdirectory
        ) ?? []

        guard !name.contains(".") else {
            return urls.first(where: { $0.lastPathComponent == name })
        }

        return urls.first(where: {
            let path = $0.lastPathComponent

            guard path.contains(".") else {
                return path == name
            }

            return path
                .split(separator: ".", omittingEmptySubsequences: false)
                .dropLast()
                .joined(separator: ".") == name
        })
    }
}
