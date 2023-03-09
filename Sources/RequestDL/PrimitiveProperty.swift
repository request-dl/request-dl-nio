/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol PrimitiveProperty: Property {

    associatedtype Object: NodeObject
    func makeObject() -> Object
}

extension PrimitiveProperty {

    /// This method is used internally and should not be called directly.
    public static func makeProperty(
        _ property: Self,
        _ context: Context
    ) async {
        let node = Node(
            root: context.root,
            object: property.makeObject(),
            children: []
        )

        let newContext = context.append(node)

        guard Body.self != Never.self else {
            return
        }

        await Body.makeProperty(property.body, newContext)
    }
}
