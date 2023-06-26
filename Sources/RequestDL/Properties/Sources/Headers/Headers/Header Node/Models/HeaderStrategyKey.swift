/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct HeaderStrategyKey: PropertyEnvironmentKey {
    static let defaultValue: HeaderStrategy = .adding
}

extension PropertyEnvironmentValues {

    var headerStrategy: HeaderStrategy {
        get { self[HeaderStrategyKey.self] }
        set { self[HeaderStrategyKey.self] = newValue }
    }
}

extension Property {

    /**
     Sets the header strategy for the property.

     - Parameter headerStrategy: The header strategy to be set.
     - Returns: A modified version of the property with the updated header strategy.
     */
    public func headerStrategy(_ headerStrategy: HeaderStrategy) -> some Property {
        environment(\.headerStrategy, headerStrategy)
    }
}
