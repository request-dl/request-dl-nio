/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDL

extension StoredObjectToolbox {

    struct TwoNamespaceModifier: PropertyModifier {

        @Namespace var two

        func body(content: Content) -> some Property {
            content
        }
    }
}
