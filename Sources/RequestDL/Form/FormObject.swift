//
//  File.swift
//  
//
//  Created by Brenno on 04/03/23.
//

import Foundation

struct FormObject: NodeObject {

    let type: FormType

    init(_ type: FormType) {
        self.type = type
    }

    func makeProperty(_ configuration: MakeConfiguration) {
        let boundary = FormUtils.boundary
        configuration.request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        configuration.request.httpBody = FormUtils.buildBody([type.data], with: boundary)
    }
}
