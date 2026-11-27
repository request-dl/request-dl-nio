//
// See LICENSE for this package's licensing information.
//

/// A response that means "not now", rather than "never": the same as a lost connection to whatever
/// is retrying.
struct ResumableUploadTransientResponse: Error {
    let status: UInt

    /// Whether a server that answers with `status` is saying "not now": a `408`, `425`, `429` or
    /// a `5xx`. Any other `4xx` is a "no".
    static func isTransient(status: UInt) -> Bool {
        switch status {
        case 408, 425, 429, 500..<600:
            return true
        default:
            return false
        }
    }
}
