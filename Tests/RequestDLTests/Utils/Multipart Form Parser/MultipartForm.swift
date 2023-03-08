//
//  MultipartForm.swift
//
//
//  Created by Brenno on 06/03/23.
//

import Foundation

struct MultipartForm {

    let boundary: String
    let items: [PartForm]

    init(_ items: [PartForm], boundary: String) {
        self.boundary = boundary
        self.items = items
    }
}
