//
//  File.swift
//  
//
//  Created by Brenno on 08/03/23.
//

import Foundation

extension Bundle {

    var normalizedResourceURL: URL {
        if let resourceURL {
            return resourceURL
        }

        return bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resource")
    }
}
