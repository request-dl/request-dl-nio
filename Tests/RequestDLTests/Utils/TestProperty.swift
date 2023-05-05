/*
 See LICENSE for this package's licensing information.
*/

import RequestDL

struct TestProperty<Content: Property>: Property {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    init(@PropertyBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some Property {
        BaseURL("www.apple.com")
        content
    }
}
