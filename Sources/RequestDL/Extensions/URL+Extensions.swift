//
//  File.swift
//  
//
//  Created by Brenno on 24/03/23.
//

import Foundation

extension NSURL {

    var lastPathComponent: String {
        pathComponents?.first ?? ".."
    }
}
