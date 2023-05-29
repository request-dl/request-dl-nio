/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDL

extension StoredObjectToolbox {

    struct Query: Property {

        @StoredObject var factory = Factory()

        var body: some Property {
            RequestDL.Query(name: "index", value: factory.rawValue)
        }
    }
}
