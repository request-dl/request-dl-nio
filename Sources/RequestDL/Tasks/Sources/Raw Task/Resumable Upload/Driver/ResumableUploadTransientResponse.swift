//
// See LICENSE for this package's licensing information.
//

/// A response that means "not now", rather than "never": the same as a lost connection to whatever
/// is retrying.
struct ResumableUploadTransientResponse: Error {
    let status: UInt
}
