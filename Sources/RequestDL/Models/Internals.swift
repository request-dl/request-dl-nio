/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

enum Internals {

    typealias Session = RequestDLInternals.Session

    typealias ConnectionContext = Session.ConnectionContext

    typealias SecureConnection = Session.SecureConnection

    typealias Request = RequestDLInternals.Request

    typealias Headers = RequestDLInternals.Headers
}

extension Internals {

    typealias TLSVersion = RequestDLInternals.TLSVersion

    typealias Certificate = RequestDLInternals.Certificate

    typealias PrivateKey = RequestDLInternals.PrivateKey

    typealias PSKClientIdentityResponse = RequestDLInternals.PSKClientIdentityResponse

    typealias PSKServerIdentityResponse = RequestDLInternals.PSKServerIdentityResponse
}

extension Internals {

    typealias AsyncBytes = RequestDLInternals.AsyncBytes

    typealias AsyncResponse = RequestDLInternals.AsyncResponse
}

extension Internals {

    typealias ResponseHead = RequestDLInternals.ResponseHead

    typealias Response = RequestDLInternals.Response
}

extension Internals {

    typealias TimeAmount = RequestDLInternals.TimeAmount
}

extension Internals {

    typealias RequestBody = RequestDLInternals.RequestBody

    typealias BodyItem = RequestDLInternals.BodyItem
}

extension Internals {

    typealias Log = RequestDLInternals.Log
}

extension Internals {

    @discardableResult
    static func raise(_ value: Int32) -> Int32 {
        SwiftOverride.raise(value)
    }
}
