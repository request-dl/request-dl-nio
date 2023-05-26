/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@available(*, deprecated)
@globalActor
public actor RequestActor {

    public static let shared = RequestActor()
}


@available(*, unavailable)
func unavailableMethod() {
    print("Hello World!")
}
