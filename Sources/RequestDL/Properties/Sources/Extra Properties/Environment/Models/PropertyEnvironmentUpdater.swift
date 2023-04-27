/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct PropertyEnvironmentUpdater<Content> {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    func callAsFunction(_ values: EnvironmentValues) {
        let mirror = PropertyMirror(content)

        for propertyValue in mirror() {
            if let environment = propertyValue as? EnvironmentPropertyValue {
                environment.setValue(for: values)
            }
        }
    }
}
