//
//  File.swift
//
//
//  Created by Brenno on 06/03/23.
//

import Foundation

#if os(macOS)
extension Process {

    static func zsh(_ args: String...) throws -> Process {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c"] + args
        try task.run()
        return task
    }
}
#endif
