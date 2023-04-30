/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDL

extension StoredObjectToolbox {

    struct Path: Property {

        @StoredObject var factory = Factory()

        var body: some Property {
            RequestDL.Path("\(factory.rawValue)")
        }
    }
}
