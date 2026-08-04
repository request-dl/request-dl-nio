//
// See LICENSE for this package's licensing information.
//

import RequestDL

extension StoredObjectToolbox {

    struct CombinedPath: Property {

        @CombinedProperty var paths

        var body: some Property {
            PropertyForEach(paths, id: \.self) {
                RequestDL.Path($0)
            }
        }
    }
}

extension StoredObjectToolbox {

    @propertyWrapper
    fileprivate struct CombinedProperty: DynamicValue {

        @OneProperty var one
        @TwoProperty var two

        var wrappedValue: [String] {
            [one, two]
        }
    }

    @propertyWrapper
    fileprivate struct OneProperty: DynamicValue {

        @StoredObject var factory = Factory()

        var wrappedValue: String {
            "\(factory.rawValue)"
        }
    }

    @propertyWrapper
    fileprivate struct TwoProperty: DynamicValue {

        @StoredObject var factory1 = Factory()
        @StoredObject var factory2 = Factory()

        var wrappedValue: String {
            "\(factory1.rawValue).\(factory2.rawValue)"
        }
    }
}
