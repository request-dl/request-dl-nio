import Foundation

protocol PrimitiveRequest: Request {

    associatedtype Object: NodeObject
    func makeObject() -> Object
}

extension PrimitiveRequest {

    public static func makeRequest(_ request: Self, _ context: Context) async {
        let node = Node(
            root: context.root,
            object: request.makeObject(),
            children: []
        )

        let newContext = context.append(node)

        guard Body.self != Never.self else {
            return
        }

        await Body.makeRequest(request.body, newContext)
    }
}
