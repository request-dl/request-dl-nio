/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct Resolve<Root: Property> {

    private let root: _GraphValue<_Root>

    init(_ root: Root) {
        self.root = .root(.init(body: root))
    }

    private func inputs() -> _PropertyInputs {
        .init(root: _Root.self, body: \.self)
    }

    private func outputs() async throws -> _PropertyOutputs {
        try await _Root._makeProperty(
            property: root,
            inputs: inputs()
        )
    }

    func build(_ delegate: DelegateProxy) async throws -> (URLSession, URLRequest) {
        let output = try await outputs()

        guard let baseURLNode = output.node.first(of: BaseURL.Node.self) else {
            fatalError(
                """
                Failed to find the required BaseURL object in the context.
                """
            )
        }

        let sessionNode = output.node.first(of: Session.Node.self)

        var make = Make(
            request: URLRequest(url: baseURLNode.baseURL),
            configuration: sessionNode?.configuration ?? .default,
            delegate: delegate
        )

        try await output.node._make(&make)

        let session = URLSession(
            configuration: make.configuration,
            delegate: delegate,
            delegateQueue: sessionNode?.queue
        )

        return (session, make.request)
    }
}

extension Resolve {

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
