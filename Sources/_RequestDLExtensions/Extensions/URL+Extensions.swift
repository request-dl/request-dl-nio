/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URL {

    public func createPathIfNeeded() throws {
        let diretories = deletingLastPathComponent()

        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(
                at: diretories,
                withIntermediateDirectories: true
            )
        }

        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
    }

    public func removeIfNeeded() throws {
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(at: self)
        }
    }
}
