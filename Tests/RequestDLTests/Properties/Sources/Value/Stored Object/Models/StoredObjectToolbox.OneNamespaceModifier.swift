//
// See LICENSE for this package's licensing information.
//

import RequestDL

extension StoredObjectToolbox {

    struct OneNamespaceModifier: PropertyModifier {

        @PropertyNamespace var one

        func body(content: Content) -> some Property {
            content
        }
    }
}
