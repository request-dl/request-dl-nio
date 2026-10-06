//
// See LICENSE for this package's licensing information.
//

/// What a download that is continued from a ``DownloadResumptionPoint`` does when the server
/// doesn't answer with the rest of the same resource: it changed since the point was taken, it no
/// longer has that many bytes, or it doesn't support asking for a part at all. See
/// ``RequestTask/continuingDownload(from:whenChanged:)``.
public enum ChangedDownloadBehavior: Sendable, Hashable {

    /// Fails with a ``DownloadResumptionError``, and nothing of the answer reaches you. The safe
    /// choice for a download whose bytes you keep yourself: whatever you hold is what you decide
    /// about, and the download can be started again from the beginning. The default.
    case fail

    /// Asks again for the whole resource and hands that on, in place of the rest.
    ///
    /// What a browser, or a download that owns its file, does. You tell it apart from the rest by
    /// the head of the result: a `200`, where the rest is a `206`. When it is a `200`, what you
    /// held of the old resource is of no use: replace it with what comes now, starting at byte
    /// zero.
    ///
    /// Only for an answer that is not the rest of the same resource. A request that can't be
    /// continued at all (``DownloadResumptionError/Reason/requestNotResumable``), a point that
    /// is already at the end (``DownloadResumptionError/Reason/alreadyComplete``), or a server
    /// that refuses outright (``DownloadResumptionError/Reason/unexpectedStatus(_:)``) still fail.
    /// And it only reaches the continuation itself: a resource that changes later, while the
    /// connection is being reconnected by ``RequestTask/resumingDownloads(_:)``, fails as before,
    /// since by then bytes of the new resource have already been handed on.
    case restart
}
