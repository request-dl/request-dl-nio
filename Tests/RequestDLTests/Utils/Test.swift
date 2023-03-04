//
//  Test.swift
//
//
//  Created by Brenno Giovanini de Moura on 06/12/22.
//

import RequestDL

struct Test<Content: Property>: Property {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    init(@PropertyBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some Property {
        content
        BaseURL("www.apple.com")
    }
}
