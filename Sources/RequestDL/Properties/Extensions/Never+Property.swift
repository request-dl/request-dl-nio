/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Never: Property {

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Property {

    func bodyException() -> Never {
        Internals.Log.failure(
            .accessingNeverBody(self)
        )
    }
}
