//
//  Test.swift
//
//
//  Created by Brenno Giovanini de Moura on 06/12/22.
//

import RequestDL

struct Test<Content: Request>: Request {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    init(@RequestBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some Request {
        content
        Url("https://www.apple.com")
    }
}
