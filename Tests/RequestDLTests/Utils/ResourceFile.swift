//
//  File.swift
//
//
//  Created by Brenno on 06/03/23.
//

import Foundation

struct ResourceFile {

    let resource: String

    init(_ resource: String) {
        self.resource = resource
    }

    func data() throws -> Data {
        try Data(contentsOf: url())
    }

    func url() throws -> URL {
        guard
            let urls = Bundle.module.urls(forResourcesWithExtension: nil, subdirectory: nil),
            let url = urls.first(where: {
                let displayName = $0.lastPathComponent

                if displayName == resource {
                    return true
                }

                let fileName = displayName.split(separator: ".").first.map {
                    String($0)
                }

                return fileName == resource
            })
        else { throw FileNotFoundError() }

        return url
    }
}

struct FileNotFoundError: Error {}
