/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS)
extension Process {

    public static func zsh(_ args: String...) throws -> Process {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c"] + args
        try task.run()
        return task
    }
}
#endif
