/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

class SecureConnectionNode: NodeObject {

    private let closure: (inout RequestDLInternals.Session.SecureConnection) -> Void

    init(_ closure: @escaping (inout RequestDLInternals.Session.SecureConnection) -> Void) {
        self.closure = closure
    }

    func makeProperty(_ make: Make) async throws {
        print("[RequestDL] TLS should be configure inside SecureConnection property")
    }
}

extension SecureConnectionNode {

    func callAsFunction(_ secureConnection: inout RequestDLInternals.Session.SecureConnection) async throws {
        closure(&secureConnection)
    }
}
