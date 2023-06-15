/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// Represents a step in the response process.
public enum ResponseStep: Hashable {
    /// An upload step.
    case upload(UploadStep)
    /// A download step.
    case download(DownloadStep)
}
