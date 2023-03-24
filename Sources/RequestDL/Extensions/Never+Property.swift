/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Never: Property {

    public var body: Never {
        bodyException()
    }
}

extension Property {

    func bodyException() -> Never {
        fatalError("An unexpected attempt was made to access the property body.")
    }
}
