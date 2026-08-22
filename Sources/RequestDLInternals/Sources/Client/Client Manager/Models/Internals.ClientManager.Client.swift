//
// See LICENSE for this package's licensing information.
//

extension Internals.ClientManager {

    /// The concrete client cached behind one `Internals.ClientManager` table entry.
    ///
    /// `.nio` backs both plain NIO and NIOTransportServices -- `Internals.Client` is the same
    /// type either way, differentiated only by which `EventLoopGroup` `SessionProvider.group(with:)`
    /// handed it, so there is nothing for this enum to distinguish between those two. `.urlSession`
    /// is the one genuinely different transport, wired in by Phase 6 of `URLSESSION_TASK.md`.
    package enum Client: @unchecked Sendable {
        case nio(Internals.Client)

        #if canImport(Darwin)
        case urlSession(Internals.URLSessionClient)
        #endif

        // MARK: - Internal properties

        package var isRunning: Bool {
            switch self {
            case .nio(let client):
                return client.isRunning
            #if canImport(Darwin)
            case .urlSession(let client):
                return client.isRunning
            #endif
            }
        }

        // MARK: - Internal methods

        package func shutdown() async throws -> Bool {
            switch self {
            case .nio(let client):
                return try await client.shutdown()
            #if canImport(Darwin)
            case .urlSession(let client):
                return try await client.shutdown()
            #endif
            }
        }
    }
}
