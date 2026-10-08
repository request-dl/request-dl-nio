//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#endif

/// A local TCP port that refuses connections and that no other test can take.
///
/// A port a server held a moment ago is not that: the system hands a freed port to the next
/// server that asks for one, and a test running in parallel can start one between the stop and
/// the request, which then connects and succeeds. Where the platform refuses a connection to a
/// bound socket that does not listen at once (Linux, Android), this one stays bound, so nothing
/// else is given it, and never listens. On Darwin it is only a port that was just released.
package final class RefusedPort: @unchecked Sendable {

    // MARK: - Package properties

    package let port: Int

    // MARK: - Private properties

    private var descriptor: Int32 = -1

    // MARK: - Inits

    package init() throws {
        // An enum on Glibc, a plain `Int32` everywhere else (Darwin, Musl, Bionic).
        #if canImport(Glibc)
        let socketType = Int32(SOCK_STREAM.rawValue)
        #else
        let socketType = SOCK_STREAM
        #endif

        let descriptor = socket(AF_INET, socketType, 0)

        guard descriptor >= 0 else {
            throw TransferServerError(code: errno)
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let isBound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, length) == 0 && getsockname(descriptor, $0, &length) == 0
            }
        }

        guard isBound else {
            let error = TransferServerError(code: errno)
            close(descriptor)
            throw error
        }

        self.port = Int(UInt16(bigEndian: address.sin_port))

        #if canImport(Darwin)
        // Darwin answers a connection to a bound socket that does not listen only after seconds,
        // where a port nobody holds is refused at once. So there the port is one that was held a
        // moment ago, which is all that can be done and leaves the race this type avoids elsewhere.
        close(descriptor)
        self.descriptor = -1
        #else
        self.descriptor = descriptor
        #endif
    }

    deinit {
        release()
    }

    // MARK: - Package methods

    /// Gives the port back. Call it when the test is done with the request, with `defer`: the
    /// object may be released as soon as its last use, which is before the request is made.
    package func release() {
        guard descriptor >= 0 else {
            return
        }

        close(descriptor)
        descriptor = -1
    }
}
