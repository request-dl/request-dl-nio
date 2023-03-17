/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct AnyProperty: Property {

    private let resolver: (Context) async -> Void

    public init<Content: Property>(_ property: Content) {
        resolver = {
            await Content.makeProperty(property, $0)
        }
    }

    public var body: Never {
        bodyException()
    }

    public static func makeProperty(
        _ property: AnyProperty,
        _ context: Context
    ) async {
        await property.resolver(context)
    }
}
