/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct PropertyNamespaceUpdater<Content> {

    private let content: Content

    init(_ content: Content) {
        self.content = content
    }

    func callAsFunction(_ hashValue: Int) -> Namespace.ID? {
        let mirror = PropertyMirror(content)

        var labels = [String]()
        var latestID: Namespace.ID?

        for child in mirror() {
            guard let namespace = child.value as? Namespace else {
                continue
            }

            labels.append(child.label ?? "nil")
            let namespaceID = Namespace.ID(
                base: Content.self,
                namespace: labels.joined(separator: "."),
                hashValue: hashValue
            )

            namespace._namespaceID = namespaceID
            latestID = namespaceID
        }

        return latestID
    }
}
