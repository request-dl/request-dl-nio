/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct Resolve<Root: Property> {

    private let root: _GraphValue<_Root>

    init(_ root: Root) {
        self.root = .root(.init(body: root))
    }

    private func inputs() -> _PropertyInputs {
        .init(
            environment: .init(),
            namespaceID: .global,
            seedFactory: .init()
        )
    }

    private func outputs() async throws -> _PropertyOutputs {
        try await _Root._makeProperty(
            property: root,
            inputs: inputs()
        )
    }

    func build() async throws -> (Internals.Session, Internals.Request) {
        let output = try await outputs()

        var make = Make(
            configuration: .init(),
            request: .init()
        )

        try await output.node._make(&make)

        let session = Internals.Session(
            provider: make.provider ?? .shared,
            configuration: make.configuration
        )

        return (session, make.request)
    }
}

extension Resolve {

    @RequestActor
    struct _Root: Property {

        let body: Root
    }
}

extension Node {

    fileprivate func _make(_ make: inout Make) async throws {
        if let property = self as? PropertyNode {
            try await property.make(&make)
        }

        var mutableSelf = self
        while let next = mutableSelf.next() {
            try await next._make(&make)
        }
    }
}

extension Resolve {

    func description() async throws -> String {
        let title = "Resolve"
        let outputs = try await outputs()

        let nodesDescription = outputs.node
            .nodeDescription
            .debug_shiftLines()

        return """
        \(title) {
        \(nodesDescription)
        }
        """
    }

//    Not Available
//    func printDescription() async throws {
//        Internals.Log.debug(try await debugDescription)
//    }
}
