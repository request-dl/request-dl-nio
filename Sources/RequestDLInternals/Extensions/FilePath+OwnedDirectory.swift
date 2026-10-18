//
// See LICENSE for this package's licensing information.
//

import SystemPackage

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

#if canImport(Darwin) || canImport(Glibc) || canImport(Musl) || canImport(Android)

extension FilePath {

    /// A directory named `name` under `parent` that only `owner` can change, created owner only
    /// when it is not there yet; `nil` when the place cannot be trusted.
    ///
    /// For the one case where the cache has no per-user directory to go to and lands in the
    /// temporary directory, which every user of the machine can write to: a user who gets there
    /// first can create the directory the cache is about to use, and then owns it, and can
    /// rename it from under the process whenever they like. It is trusted when
    ///
    /// - what is at `parent/name` is a real directory (a symbolic link is not followed, since
    ///   anyone can plant one), owned by `owner`, that group and others cannot even read (the
    ///   names inside it encode the URLs it caches), and
    /// - nobody but `owner` or root can rename it away: `parent` is owned by one of them, and it
    ///   is either not writable by group or others or it has the sticky bit, which limits
    ///   renaming and removing to the owner of the entry.
    ///
    /// A directory the check does not pass is left alone, not repaired or removed: it is someone
    /// else's.
    ///
    /// - Parameter owner: The user the directory has to belong to. The effective user of this
    ///   process, except in a test.
    package static func ownedDirectory(
        named name: String,
        under parent: FilePath,
        owner: UInt32 = UInt32(geteuid())
    ) -> FilePath? {
        guard isUntamperable(parent: parent, owner: owner) else {
            return nil
        }

        let path = parent.appending(name)

        switch makeDirectory(atPath: path.string) {
        case .created, .alreadyThere:
            break
        case .failed:
            return nil
        }

        guard let status = status(of: path) else {
            return nil
        }

        let isDirectory = status.mode & 0o170000 == 0o040000
        let isOwnerOnly = status.mode & 0o077 == 0

        guard isDirectory, isOwnerOnly, status.owner == owner else {
            return nil
        }

        return path
    }

    /// A directory under `parent` with a name nobody could have guessed, created owner only.
    /// What the cache uses when `ownedDirectory(named:under:owner:)` found nothing it can trust:
    /// it does not survive the process, since every process makes its own, but nobody else
    /// could have made it first.
    package static func exclusiveDirectory(
        prefix: String,
        under parent: FilePath
    ) -> FilePath? {
        for _ in 0..<8 {
            let path = parent.appending("\(prefix)-\(UInt64.random(in: .min ... .max))")

            switch makeDirectory(atPath: path.string) {
            case .created:
                return path
            case .alreadyThere:
                continue
            case .failed:
                return nil
            }
        }

        return nil
    }

    // MARK: - Private static methods

    private static func isUntamperable(parent: FilePath, owner: UInt32) -> Bool {
        guard let status = status(of: parent) else {
            return false
        }

        guard status.mode & 0o170000 == 0o040000 else {
            return false
        }

        let isTrustedOwner = status.owner == owner || status.owner == 0
        let isWritableByOthers = status.mode & 0o022 != 0
        let isSticky = status.mode & 0o1000 != 0

        return isTrustedOwner && (!isWritableByOthers || isSticky)
    }

    private static func status(of path: FilePath) -> (mode: UInt32, owner: UInt32)? {
        statusOfItem(atPath: path.string)
    }
}

// MARK: - libc

private enum DirectoryCreation {
    case created
    case alreadyThere
    case failed
}

/// Outside `FilePath`'s extension because `FilePath` has members called `stat`, which would take
/// the place of the C function inside it.
private func makeDirectory(atPath path: String) -> DirectoryCreation {
    if mkdir(path, 0o700) == 0 {
        return .created
    }

    return errno == EEXIST ? .alreadyThere : .failed
}

private func statusOfItem(atPath path: String) -> (mode: UInt32, owner: UInt32)? {
    var buffer = stat()

    guard lstat(path, &buffer) == 0 else {
        return nil
    }

    return (UInt32(buffer.st_mode), UInt32(buffer.st_uid))
}

#endif
