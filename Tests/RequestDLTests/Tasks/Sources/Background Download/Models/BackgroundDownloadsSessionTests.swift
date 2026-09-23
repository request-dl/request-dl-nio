//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals
import Testing

@testable import RequestDL

import Foundation

/// Covers `BackgroundDownloads.Session`'s `taskDescription` encoding directly, independent of any
/// real `URLSessionTask`: this is what a delegate callback decodes after a relaunch, when
/// nothing else about the original request survives.
///
/// It needs to round-trip correctly on its own merits, not just "happen to work" against
/// whatever a live download produces.
struct BackgroundDownloadsSessionTests {

    @Test
    func encodeThenDecode_roundTripsIdAndDestination() async throws {
        // Given
        let id = "episode-42"
        let destination = URL(fileURLWithPath: "/tmp/episode-42.mp3")

        // When
        let encoded = try #require(BackgroundDownloads.Session.encode(id: id, destination: destination))
        let decoded = try #require(BackgroundDownloads.Session.decode(encoded))

        // Then
        #expect(decoded.id == id)
        #expect(decoded.destination == destination)
    }

    @Test
    func decode_whenTaskDescriptionIsNil_returnsNil() async throws {
        #expect(BackgroundDownloads.Session.decode(nil) == nil)
    }

    @Test
    func decode_whenTaskDescriptionIsNotEncodedByThisType_returnsNil() async throws {
        #expect(BackgroundDownloads.Session.decode("not a descriptor") == nil)
    }

    // MARK: - serverTrust encoding

    @Test
    func encodeThenDecodeServerTrust_roundTripsDescriptor() async throws {
        // Given
        let descriptor = Internals.ServerTrustPolicy.Descriptor(
            trustedRootCertificatesDER: [Data([0x01, 0x02, 0x03])],
            verification: .noHostnameVerification
        )

        // When
        let encoded = BackgroundDownloads.Session.encode(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3"),
            serverTrust: descriptor
        )
        let decoded = BackgroundDownloads.Session.decodeServerTrust(encoded)

        // Then
        #expect(decoded == descriptor)
    }

    @Test
    func decodeServerTrust_whenNoneWasEncoded_returnsNil() async throws {
        // Given: the common case, a plain download with `serverTrust` defaulted to `nil`.
        let encoded = BackgroundDownloads.Session.encode(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        )

        // When / Then
        #expect(BackgroundDownloads.Session.decodeServerTrust(encoded) == nil)
    }

    @Test
    func decodeServerTrust_whenTaskDescriptionIsNotEncodedByThisType_returnsNil() async throws {
        #expect(BackgroundDownloads.Session.decodeServerTrust("not a descriptor") == nil)
    }

    // MARK: - clientIdentity encoding

    @Test
    func encodeThenDecodeClientIdentity_roundTripsDescriptor() async throws {
        // Given
        let descriptor = Internals.ClientIdentityDescriptor(
            certificateChainFilePath: "/tmp/client.pem",
            privateKeyFilePath: "/tmp/client.key",
            privateKeyFormat: .pem
        )

        // When
        let encoded = BackgroundDownloads.Session.encode(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3"),
            clientIdentity: descriptor,
            clientIdentityHost: "configured.example.com"
        )
        let decoded = BackgroundDownloads.Session.decodeClientIdentity(
            encoded,
            challengedBy: "configured.example.com"
        )

        // Then
        #expect(decoded == descriptor)
    }

    @Test
    func decodeClientIdentity_whenNoneWasEncoded_returnsNil() async throws {
        // Given: the common case, no client certificate configured.
        let encoded = BackgroundDownloads.Session.encode(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        )

        // When / Then
        #expect(
            BackgroundDownloads.Session.decodeClientIdentity(
                encoded,
                challengedBy: "configured.example.com"
            ) == nil
        )
    }

    @Test
    func decodeClientIdentity_whenTaskDescriptionIsNotEncodedByThisType_returnsNil() async throws {
        #expect(
            BackgroundDownloads.Session.decodeClientIdentity(
                "not a descriptor",
                challengedBy: "configured.example.com"
            ) == nil
        )
    }

    /// The regression this gate exists for: a background session follows redirects on its own, so
    /// the host challenging us for a client certificate is not necessarily the host the download
    /// was scheduled against. Presenting the identity anyway would hand it to whoever controls
    /// the redirect.
    @Test
    func decodeClientIdentity_whenChallengedByADifferentHost_returnsNil() async throws {
        // Given: an mTLS download scheduled against one host...
        let encoded = BackgroundDownloads.Session.encode(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3"),
            clientIdentity: Internals.ClientIdentityDescriptor(
                certificateChainFilePath: "/tmp/client.pem",
                privateKeyFilePath: "/tmp/client.key",
                privateKeyFormat: .pem
            ),
            clientIdentityHost: "configured.example.com"
        )

        // When / Then: ...is not offered to another one, however it was reached.
        #expect(
            BackgroundDownloads.Session.decodeClientIdentity(
                encoded,
                challengedBy: "attacker.example.com"
            ) == nil
        )
    }

    /// A `taskDescription` written by a version of this package that predates the host gate: it
    /// has to keep decoding (the download itself is still valid and still running), but it can't
    /// prove which host it was scheduled for, so the identity is withheld rather than guessed at.
    @Test
    func decodeClientIdentity_whenNoHostWasRecorded_returnsNil() async throws {
        // Given
        let encoded = BackgroundDownloads.Session.encode(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3"),
            clientIdentity: Internals.ClientIdentityDescriptor(
                certificateChainFilePath: "/tmp/client.pem",
                privateKeyFilePath: "/tmp/client.key",
                privateKeyFormat: .pem
            )
        )

        // When / Then: `id`/`destination` still decode, so the download keeps working...
        #expect(BackgroundDownloads.Session.decode(encoded)?.id == "episode-42")

        // ...but no host can match a missing one.
        #expect(
            BackgroundDownloads.Session.decodeClientIdentity(
                encoded,
                challengedBy: "configured.example.com"
            ) == nil
        )
    }

    @Test
    func encodeThenDecode_carriesBothServerTrustAndClientIdentityIndependently() async throws {
        // Given: both configured at once, the mTLS + custom-trust-roots combination.
        let serverTrust = Internals.ServerTrustPolicy.Descriptor(
            trustedRootCertificatesDER: [Data([0x01])],
            verification: .fullVerification
        )
        let clientIdentity = Internals.ClientIdentityDescriptor(
            certificateChainFilePath: "/tmp/client.pem",
            privateKeyFilePath: "/tmp/client.key",
            privateKeyFormat: .pem
        )

        // When
        let encoded = BackgroundDownloads.Session.encode(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3"),
            serverTrust: serverTrust,
            clientIdentity: clientIdentity,
            clientIdentityHost: "configured.example.com"
        )

        // Then
        #expect(BackgroundDownloads.Session.decodeServerTrust(encoded) == serverTrust)
        #expect(
            BackgroundDownloads.Session.decodeClientIdentity(
                encoded,
                challengedBy: "configured.example.com"
            ) == clientIdentity
        )
    }

    // MARK: - firstTask(matching:in:)

    /// `cancel(id:)`'s own matching logic, pulled out so it's testable against a plain array of
    /// tasks instead of a real background `URLSession.allTasks`.
    ///
    /// Every task below comes from `URLSession.shared`, created but never resumed; it's just a
    /// way to get a real `URLSessionTask` object to set `taskDescription` on.
    @Test
    func firstTaskMatching_whenOneTaskHasMatchingID_returnsIt() async throws {
        // Given
        let url = try #require(URL(string: "https://example.com"))
        let wanted = URLSession.shared.downloadTask(with: url)
        wanted.taskDescription = BackgroundDownloads.Session.encode(
            id: "episode-42",
            destination: URL(fileURLWithPath: "/tmp/episode-42.mp3")
        )

        let other = URLSession.shared.downloadTask(with: url)
        other.taskDescription = BackgroundDownloads.Session.encode(
            id: "episode-1",
            destination: URL(fileURLWithPath: "/tmp/episode-1.mp3")
        )

        // When
        let match = BackgroundDownloads.Session.firstTask(matching: "episode-42", in: [other, wanted])

        // Then
        #expect(match === wanted)
    }

    @Test
    func firstTaskMatching_whenNoTaskHasMatchingID_returnsNil() async throws {
        // Given
        let url = try #require(URL(string: "https://example.com"))
        let task = URLSession.shared.downloadTask(with: url)
        task.taskDescription = BackgroundDownloads.Session.encode(
            id: "episode-1",
            destination: URL(fileURLWithPath: "/tmp/episode-1.mp3")
        )

        // When / Then
        #expect(BackgroundDownloads.Session.firstTask(matching: "episode-42", in: [task]) == nil)
    }

    @Test
    func firstTaskMatching_ignoresTasksWithNoOrUnrecognizedTaskDescription() async throws {
        // Given
        let url = try #require(URL(string: "https://example.com"))

        let noDescription = URLSession.shared.downloadTask(with: url)

        let unrecognized = URLSession.shared.downloadTask(with: url)
        unrecognized.taskDescription = "not a descriptor"

        // When / Then: neither crashes nor false-matches; a task this type didn't create simply
        // isn't a candidate.
        let match = BackgroundDownloads.Session.firstTask(
            matching: "episode-42",
            in: [noDescription, unrecognized]
        )
        #expect(match == nil)
    }

    @Test
    func firstTaskMatching_whenListIsEmpty_returnsNil() async throws {
        #expect(BackgroundDownloads.Session.firstTask(matching: "episode-42", in: []) == nil)
    }

    // MARK: - cancel(id:)

    @Test
    func cancel_whenNoDownloadHasEverBeenScheduled_returnsFalse() async throws {
        // Given: a fresh `Session` that has never scheduled anything, so there is no
        // `URLSession` to even ask.
        let session = BackgroundDownloads.Session()

        // When / Then
        #expect(await session.cancel(id: "episode-42") == false)
    }
}

#endif
