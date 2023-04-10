/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A typealias that combines the `UploadProgress` and `DownloadProgress`
 protocols to represent both upload and download progress.
 */
public typealias Progress = UploadProgress & DownloadProgress
