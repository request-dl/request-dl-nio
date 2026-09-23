//
// See LICENSE for this package's licensing information.
//

extension Internals.ClientManager {

    /// The concrete client cached behind one `Internals.ClientManager` table entry.
    ///
    /// `.nio` backs both plain NIO and NIOTransportServices: `Internals.Client` is the same
    /// type either way, differentiated only by which `EventLoopGroup` `SessionProvider.group(with:)`
    /// handed it, so there is nothing for this enum to distinguish between those two. `.urlSession`
    /// is the one genuinely different transport.
    package enum Client: @unchecked Sendable {
        #if canImport(NIOCore)
        case nio(Internals.Client)
        #endif

        #if canImport(Darwin)
        case urlSession(Internals.URLSessionClient)
        #endif

        // MARK: - Internal properties

        package var isRunning: Bool {
            switch self {
            #if canImport(NIOCore)
            case .nio(let client):
                return client.isRunning
            #endif
            #if canImport(Darwin)
            case .urlSession(let client):
                return client.isRunning
            #endif
            }
        }

        /// The identity of the concrete client behind this case, so two enum values holding the
        /// very same client can be told apart from two holding equivalent ones.
        package var objectIdentifier: ObjectIdentifier {
            switch self {
            #if canImport(NIOCore)
            case .nio(let client):
                return ObjectIdentifier(client)
            #endif
            #if canImport(Darwin)
            case .urlSession(let client):
                return ObjectIdentifier(client)
            #endif
            }
        }

        // MARK: - Internal methods

        package func shutdown() async throws -> Bool {
            switch self {
            #if canImport(NIOCore)
            case .nio(let client):
                return try await client.shutdown()
            #endif
            #if canImport(Darwin)
            case .urlSession(let client):
                return try await client.shutdown()
            #endif
            }
        }
    }
}
