//
// See LICENSE for this package's licensing information.
//

import RequestDL

extension Session {

    /// A dedicated pool for the `LocalServer`-backed test suite.
    ///
    /// ## Why this exists
    ///
    /// Every test that omits an explicit `Session` gets the library's default: provider
    /// `.shared`, which is `MultiThreadedEventLoopGroup.shared`, and `ClientManager.shared`
    /// reuses one `Internals.Client` — one `AsyncHTTPClient`, one connection pool — for any two
    /// requests whose built `Internals.Session.Configuration` compares equal. Every file in this
    /// suite that talks to `LocalServer` through `TrustRoots { Certificate(the same server
    /// resource) }` builds the same configuration, so all of them, across every test function in
    /// every one of those files, share that single pool for the life of the process.
    ///
    /// `LocalServer.shared` is one `ServerManager` on one port for the same reason, so this
    /// family already funnels through one server; there is no reason for it to also funnel
    /// through the library's general-purpose default pool, which is sized for a normal
    /// application talking to a handful of hosts, not for a test binary firing requests at one
    /// target as fast as `swift test` can schedule them.
    ///
    /// ## What this does not fix
    ///
    /// A connection that is never returned to a pool eventually starves it regardless of the
    /// pool's size. This is not that: use it after confirming the failure self-heals on a
    /// retry, which is what distinguishes contention against a small pool (rare, but no test
    /// asserts a bound on how long a shared resource takes to be handed back) from an actual
    /// leak (worth its own investigation).
    static var localServer: Session {
        Session("com.requestdl.tests.local-server", numberOfThreads: 2)
            .maximumConnectionsPerHost(64)
    }
}
