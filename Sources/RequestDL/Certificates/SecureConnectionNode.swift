//
//  File.swift
//  
//
//  Created by Brenno on 30/03/23.
//

import Foundation

protocol SecureConnectionPropertyNode {

    func make(_ make: inout Make) async throws
}

struct SecureConnectionNode: PropertyNode {

    private let node: SecureConnectionPropertyNode

    init(_ node: SecureConnectionPropertyNode) {
        self.node = node
    }

    func make(_ make: inout Make) async throws {
        guard make.isInsideSecureConnection else {
            fatalError("This property should be configured inside SecureConnection")
        }
        try await passthrough(&make)
    }
}

extension SecureConnectionNode {

    struct Contains {

        fileprivate let node: SecureConnectionPropertyNode

        func callAsFunction<Property>(_ type: Property.Type) -> Bool {
            node is Property
        }
    }

    var contains: Contains {
        .init(node: node)
    }
}

extension SecureConnectionNode {

    struct Passthrough {

        fileprivate let node: SecureConnectionPropertyNode

        func callAsFunction(_ make: inout Make) async throws {
            try await node.make(&make)
        }
    }

    var passthrough: Passthrough {
        .init(node: node)
    }
}
