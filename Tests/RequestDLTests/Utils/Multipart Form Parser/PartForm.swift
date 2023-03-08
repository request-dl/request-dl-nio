//
//  File.swift
//
//
//  Created by Brenno on 06/03/23.
//

import Foundation

struct PartForm {

    let headers: [String: String]
    let contents: Data

    init(
        headers: [String: String],
        contents: Data
    ) {
        self.headers = headers
        self.contents = contents
    }
}
