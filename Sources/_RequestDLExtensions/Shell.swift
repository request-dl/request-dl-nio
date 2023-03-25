/*
 See LICENSE for this package's licensing information.
*/

import Foundation

#if os(macOS) || os(Linux)
extension Process {

    public static func zsh(_ args: String...) throws -> Process {
        let task = Process()
        #if os(macOS)
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        #elseif os(Linux)
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        #endif
        task.arguments = ["-c"] + args
        try task.run()
        return task
    }
}
#endif
