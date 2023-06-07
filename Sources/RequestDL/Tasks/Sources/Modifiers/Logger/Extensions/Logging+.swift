//
//  File.swift
//  
//
//  Created by Brenno on 07/06/23.
//

import Logging

extension Logger {

    static let disabled = Logger(label: "RDL-do-not-log") { _ in
        SwiftLogNoOpLogHandler()
    }
}
