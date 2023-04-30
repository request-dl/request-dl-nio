/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDL

extension StoredObjectToolbox {

    struct CombinedPath: Property {

        @CombinedProperty var paths

        var body: some Property {
            ForEach(paths, id: \.self) {
                RequestDL.Path($0)
            }
        }
    }
}

private extension StoredObjectToolbox {

    @propertyWrapper
    struct CombinedProperty: DynamicValue {

        @OneProperty var one
        @TwoProperty var two

        var wrappedValue: [String] {
            [one, two]
        }
    }

    @propertyWrapper
    struct OneProperty: DynamicValue {

        @StoredObject var factory = Factory()

        var wrappedValue: String {
            "\(factory.rawValue)"
        }
    }

    @propertyWrapper
    struct TwoProperty: DynamicValue {

        @StoredObject var factory1 = Factory()
        @StoredObject var factory2 = Factory()

        var wrappedValue: String {
            "\(factory1.rawValue).\(factory2.rawValue)"
        }
    }
}
