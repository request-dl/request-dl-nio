//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import struct FoundationEssentials.UUID
#else
import struct Foundation.UUID
#endif

/// One run of a request, as a ``RequestMonitor`` sees it.
///
/// A monitor attached to several requests (every request of a ``GroupTask``, say) is told which
/// one each event is about through this. Two runs of the same request, such as the attempts of
/// `.retry`, are two executions.
public struct RequestExecution: Sendable, Hashable, Identifiable {

    /// Identifies this execution among every other one the monitor sees.
    public let id: UUID

    /// The URL the request was sent to.
    public let url: String

    /// The HTTP method of the request.
    public let method: String

    // MARK: - Inits

    init(url: String, method: String) {
        self.id = UUID()
        self.url = url
        self.method = method
    }
}
