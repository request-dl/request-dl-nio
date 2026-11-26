//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Security
import SwiftAsyncStream
import Testing

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The cleanup of the keys earlier versions left in the Keychain.
///
/// Nothing in this file reads, writes or deletes in a real Keychain: the deleting tests use
/// `FakeKeychainItemStore` only. (Any test that builds an identity through the default
/// `makeIdentity` starts the real cleanup, whose query finds nothing in an unsigned test process.)
struct InternalsLegacyIdentityItemsTests {

    typealias Items = Internals.LegacyIdentityItems
    typealias Item = Internals.KeychainItem

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let twoDaysAgo = now.addingTimeInterval(-2 * 86_400)

    /// 20 bytes, as the SHA-1 of a public key is.
    private static let applicationLabel = Data((0..<20).map { UInt8($0 &* 13 &+ 5) })
    private static let applicationLabelHex = Self.hex(applicationLabel)
    private static let sha256Hex = String(repeating: "ab12", count: 16)

    private static func hex(_ data: Data) -> String {
        data.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
    }

    private static func key(
        label: String? = "RequestDL.mtls.key." + applicationLabelHex,
        applicationLabel: Data? = applicationLabel,
        creationDate: Date? = twoDaysAgo,
        itemClass: Item.ItemClass = .key,
        ref: Int = 1
    ) -> Item {
        Item(
            itemClass: itemClass,
            label: label,
            applicationLabel: applicationLabel,
            creationDate: creationDate,
            persistentRef: Data("ref-\(ref)".utf8)
        )
    }

    // Spelled out one by one: a literal array of concatenations is too much for the type checker
    // once the `@Test` macro expands it.
    static let notOursLabels: [String] = {
        let hex64: String = String(repeating: "ab12", count: 16)
        let hex40: String = String(repeating: "cd34", count: 10)
        var labels: [String] = []
        labels.append("RequestDL.mtls.")
        labels.append("RequestDL.mtls.foo")
        labels.append("RequestDL.mtls.key")
        labels.append("RequestDL.mtls.key.")
        labels.append("RequestDL.mtls." + hex64)
        labels.append("RequestDL.mtls." + hex64 + "." + hex40)
        labels.append("requestdl.mtls.key." + hex64)
        labels.append("RequestDL.mtls.keys." + hex64)
        labels.append("RequestDL.mtls.key" + hex64)
        labels.append("RequestDL.mtlsXkey." + hex64)
        labels.append("XRequestDL.mtls.key." + hex64)
        labels.append(" RequestDL.mtls.key." + hex64)
        labels.append("RequestDL.mtls.key." + hex64 + ".extra")
        labels.append("com.example.RequestDL.mtls.key." + hex64)
        labels.append("My client key")
        labels.append("")
        labels.append(" ")
        return labels
    }()

    static let unicodeLabels: [String] = {
        let hex64: String = String(repeating: "ab12", count: 16)
        var labels: [String] = []
        labels.append("RequestDL.mtls.key.🔑")
        labels.append("RequestDL.mtls.key." + String(repeating: "é", count: 40))
        labels.append("RequestDL.mtls.key." + String(repeating: "０", count: 64))  // fullwidth digits
        labels.append("RequestDL.mtls.key." + String(repeating: "ab12", count: 15) + "ab1\u{0301}")  // combining mark
        labels.append("RequestDL．mtls.key." + hex64)  // fullwidth dot
        labels.append("RequestDL.mtls.key.\u{200B}" + hex64)  // zero width space
        labels.append("chave do usuário")
        return labels
    }()

    static let orphanLabels: [String] = {
        var labels: [String] = []
        labels.append("RequestDL.mtls.key." + applicationLabelHex)
        labels.append("RequestDL.mtls.key." + sha256Hex)
        return labels
    }()

    static let keptLabels: [String] = {
        var labels: [String] = []
        labels.append("RequestDL.mtls.foo")
        labels.append("RequestDL.mtls.key." + String(repeating: "a", count: 39))
        labels.append("RequestDL.mtls.key." + String(repeating: "a", count: 41))
        labels.append("RequestDL.mtls.key." + String(repeating: "A", count: 64))
        labels.append("RequestDL.mtls." + String(repeating: "a", count: 64))
        labels.append("My client key")
        labels.append("")
        return labels
    }()

    // MARK: - isLibraryKeyLabel

    @Test
    func isLibraryKeyLabel_whenTheSuffixIs40HexOfTheApplicationLabel_isTrue() {
        #expect(
            Items.isLibraryKeyLabel(
                "RequestDL.mtls.key." + Self.applicationLabelHex,
                applicationLabel: Self.applicationLabel
            )
        )
    }

    @Test
    func isLibraryKeyLabel_whenTheSuffixIs64HexAndTheKeyHasA20ByteApplicationLabel_isTrue() {
        let label = "RequestDL.mtls.key." + Self.sha256Hex

        #expect(Items.isLibraryKeyLabel(label, applicationLabel: Self.applicationLabel))
        #expect(Items.isLibraryKeyLabel(label, applicationLabel: Data(repeating: 0, count: 20)))
    }

    @Test
    func isLibraryKeyLabel_whenTheSuffixIs64HexAndTheKeyHasNoSHA1ApplicationLabel_isFalse() {
        let label = "RequestDL.mtls.key." + Self.sha256Hex

        #expect(!Items.isLibraryKeyLabel(label, applicationLabel: nil))
        #expect(!Items.isLibraryKeyLabel(label, applicationLabel: Data()))
        #expect(!Items.isLibraryKeyLabel(label, applicationLabel: Data(repeating: 1, count: 19)))
        #expect(!Items.isLibraryKeyLabel(label, applicationLabel: Data(repeating: 1, count: 32)))
    }

    @Test
    func isLibraryKeyLabel_whenTheSuffixOf40HexIsNotTheApplicationLabel_isFalse() {
        let other = Data(Self.applicationLabel.reversed())

        #expect(!Items.isLibraryKeyLabel("RequestDL.mtls.key." + Self.applicationLabelHex, applicationLabel: other))
        #expect(!Items.isLibraryKeyLabel("RequestDL.mtls.key." + Self.applicationLabelHex, applicationLabel: nil))
        #expect(!Items.isLibraryKeyLabel("RequestDL.mtls.key." + Self.applicationLabelHex, applicationLabel: Data()))
    }

    @Test(arguments: [0, 1, 39, 41, 63, 65, 128])
    func isLibraryKeyLabel_whenTheHexHasAnotherLength_isFalse(_ length: Int) {
        let suffix = String(repeating: "a", count: length)

        #expect(
            !Items.isLibraryKeyLabel("RequestDL.mtls.key." + suffix, applicationLabel: Data(repeating: 0xAA, count: 20))
        )
        #expect(!Items.isLibraryKeyLabel("RequestDL.mtls.key." + suffix, applicationLabel: nil))
    }

    @Test
    func isLibraryKeyLabel_whenTheHexIsUppercase_isFalse() {
        #expect(
            !Items.isLibraryKeyLabel(
                "RequestDL.mtls.key." + Self.applicationLabelHex.uppercased(),
                applicationLabel: Self.applicationLabel
            )
        )
        #expect(
            !Items.isLibraryKeyLabel(
                "RequestDL.mtls.key." + Self.sha256Hex.uppercased(),
                applicationLabel: Self.applicationLabel
            )
        )
    }

    @Test
    func isLibraryKeyLabel_whenTheSuffixHasANonHexCharacter_isFalse() {
        let suffix = String(Self.sha256Hex.dropLast()) + "g"

        #expect(!Items.isLibraryKeyLabel("RequestDL.mtls.key." + suffix, applicationLabel: nil))
        #expect(!Items.isLibraryKeyLabel("RequestDL.mtls.key." + suffix + "\n", applicationLabel: nil))
        #expect(!Items.isLibraryKeyLabel("RequestDL.mtls.key. " + Self.sha256Hex, applicationLabel: nil))
        #expect(!Items.isLibraryKeyLabel("RequestDL.mtls.key." + Self.sha256Hex + " ", applicationLabel: nil))
    }

    @Test(arguments: InternalsLegacyIdentityItemsTests.notOursLabels)
    func isLibraryKeyLabel_whenTheLabelIsNotOurs_isFalse(_ label: String) {
        #expect(!Items.isLibraryKeyLabel(label, applicationLabel: Self.applicationLabel))
        #expect(!Items.isLibraryKeyLabel(label, applicationLabel: nil))
    }

    @Test(arguments: InternalsLegacyIdentityItemsTests.unicodeLabels)
    func isLibraryKeyLabel_whenTheLabelIsUnicode_isFalse(_ label: String) {
        #expect(!Items.isLibraryKeyLabel(label, applicationLabel: Self.applicationLabel))
        #expect(!Items.isLibraryKeyLabel(label, applicationLabel: nil))
    }

    // MARK: - removeOrphanedKeys: what is removed

    @Test(arguments: InternalsLegacyIdentityItemsTests.orphanLabels)
    func removeOrphanedKeys_whenTheKeyIsOurOldOrphan_removesIt(_ label: String) {
        let store = FakeKeychainItemStore(items: [Self.key(label: label)])

        let removed = Items.removeOrphanedKeys(from: store, now: Self.now)

        #expect(removed == 1)
        #expect(store.deletedRefs == [Data("ref-1".utf8)])
        #expect(store.items.isEmpty)
    }

    @Test
    func removeOrphanedKeys_whenTheKeyIsYoungerThan24Hours_keepsIt() {
        let store = FakeKeychainItemStore(items: [
            Self.key(creationDate: Self.now.addingTimeInterval(-86_399), ref: 1),
            Self.key(creationDate: Self.now.addingTimeInterval(-60), ref: 2),
            Self.key(creationDate: Self.now, ref: 3),
            Self.key(creationDate: Self.now.addingTimeInterval(3_600), ref: 4),  // clock skew: in the future
        ])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 0)
        #expect(store.deletedRefs.isEmpty)
        #expect(store.items.count == 4)
    }

    @Test
    func removeOrphanedKeys_whenTheKeyIsExactly24HoursOld_keepsIt() {
        let store = FakeKeychainItemStore(items: [Self.key(creationDate: Self.now.addingTimeInterval(-86_400))])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 0)
        #expect(store.deletedRefs.isEmpty)
    }

    @Test
    func removeOrphanedKeys_whenTheMinimumAgeIsGiven_usesIt() {
        let store = FakeKeychainItemStore(items: [Self.key(creationDate: Self.now.addingTimeInterval(-7_200))])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now, minimumAge: 86_400) == 0)
        #expect(Items.removeOrphanedKeys(from: store, now: Self.now, minimumAge: 3_600) == 1)
    }

    @Test
    func removeOrphanedKeys_whenTheKeyHasNoCreationDate_keepsIt() {
        let store = FakeKeychainItemStore(items: [Self.key(creationDate: nil)])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 0)
        #expect(store.deletedRefs.isEmpty)
    }

    @Test
    func removeOrphanedKeys_whenTheKeyHasNoLabel_keepsIt() {
        let store = FakeKeychainItemStore(items: [Self.key(label: nil)])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 0)
        #expect(store.deletedRefs.isEmpty)
    }

    @Test(arguments: InternalsLegacyIdentityItemsTests.keptLabels)
    func removeOrphanedKeys_whenTheLabelIsNotOurs_keepsIt(_ label: String) {
        let store = FakeKeychainItemStore(items: [Self.key(label: label)])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 0)
        #expect(store.deletedRefs.isEmpty)
    }

    @Test
    func removeOrphanedKeys_whenTheLabelOf40HexIsNotTheKeysOwnApplicationLabel_keepsIt() {
        let store = FakeKeychainItemStore(items: [
            Self.key(applicationLabel: Data(Self.applicationLabel.reversed()), ref: 1),
            Self.key(applicationLabel: nil, ref: 2),
        ])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 0)
        #expect(store.deletedRefs.isEmpty)
    }

    @Test(arguments: [Item.ItemClass.certificate, .other])
    func removeOrphanedKeys_whenTheItemIsNotAKey_keepsIt(_ itemClass: Item.ItemClass) {
        // Even one with a label and an age that would be an orphan's, if it were a key.
        let store = FakeKeychainItemStore(items: [
            Self.key(itemClass: itemClass, ref: 1),
            Self.key(label: "RequestDL.mtls.key." + Self.sha256Hex, itemClass: itemClass, ref: 2),
        ])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 0)
        #expect(store.deletedRefs.isEmpty)
        #expect(store.items.count == 2)
    }

    @Test
    func removeOrphanedKeys_whenTheStoreHoldsOrphansAndOthers_removesOnlyTheOrphans() {
        let store = FakeKeychainItemStore(items: [
            Self.key(ref: 1),
            Self.key(label: "RequestDL.mtls.key." + Self.sha256Hex, ref: 2),
            Self.key(label: "RequestDL.mtls.foo", ref: 3),
            Self.key(creationDate: Self.now, ref: 4),
            Self.key(itemClass: .certificate, ref: 5),
            Self.key(creationDate: nil, ref: 6),
        ])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 2)
        #expect(store.deletedRefs == [Data("ref-1".utf8), Data("ref-2".utf8)])
        #expect(store.items.map(\.persistentRef) == (3...6).map { Data("ref-\($0)".utf8) })
    }

    // MARK: - removeOrphanedKeys: how it is removed

    @Test
    func removeOrphanedKeys_removesEachItemByItsOwnPersistentRef_andContinuesWhenOneFails() {
        let store = FakeKeychainItemStore(
            items: [Self.key(ref: 1), Self.key(ref: 2), Self.key(ref: 3)],
            failingDeletes: [Data("ref-2".utf8): errSecItemNotFound]
        )

        let removed = Items.removeOrphanedKeys(from: store, now: Self.now)

        #expect(removed == 2)
        #expect(store.deleteAttempts == [Data("ref-1".utf8), Data("ref-2".utf8), Data("ref-3".utf8)])
        #expect(store.items.map(\.persistentRef) == [Data("ref-2".utf8)])
    }

    @Test(arguments: [
        errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled, errSecInteractionRequired,
        errSecNotAvailable,
    ])
    func removeOrphanedKeys_whenSecurityNeedsTheUser_stopsWithoutInsisting(_ status: OSStatus) {
        let store = FakeKeychainItemStore(
            items: [Self.key(ref: 1), Self.key(ref: 2), Self.key(ref: 3)],
            failingDeletes: [Data("ref-2".utf8): status]
        )

        let removed = Items.removeOrphanedKeys(from: store, now: Self.now)

        #expect(removed == 1)
        #expect(store.deleteAttempts == [Data("ref-1".utf8), Data("ref-2".utf8)])
        #expect(store.items.map(\.persistentRef) == [Data("ref-2".utf8), Data("ref-3".utf8)])
    }

    @Test
    func removeOrphanedKeys_whenTheDeleteFailsWithAnythingElse_triesTheNext() {
        let store = FakeKeychainItemStore(
            items: [Self.key(ref: 1), Self.key(ref: 2)],
            failingDeletes: [Data("ref-1".utf8): errSecMissingEntitlement]
        )

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 1)
        #expect(store.deleteAttempts == [Data("ref-1".utf8), Data("ref-2".utf8)])
    }

    @Test
    func removeOrphanedKeys_whenOnlyLabelsIsGiven_removesOnlyThoseLabels() {
        let first = "RequestDL.mtls.key." + String(repeating: "a", count: 64)
        let second = "RequestDL.mtls.key." + String(repeating: "b", count: 64)
        let store = FakeKeychainItemStore(items: [
            Self.key(label: first, ref: 1),
            Self.key(label: second, ref: 2),
        ])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now, onlyLabels: [second]) == 1)
        #expect(store.items.map(\.label) == [first])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now, onlyLabels: []) == 0)
        #expect(Items.removeOrphanedKeys(from: store, now: Self.now, onlyLabels: ["RequestDL.mtls.foo"]) == 0)
        #expect(store.items.count == 1)
    }

    @Test
    func removeOrphanedKeys_whenOnlyLabelsNamesALabelThatIsNotOurs_stillKeepsIt() {
        let store = FakeKeychainItemStore(items: [Self.key(label: "My client key")])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now, onlyLabels: ["My client key"]) == 0)
        #expect(store.items.count == 1)
    }

    @Test(arguments: [errSecMissingEntitlement, errSecInteractionNotAllowed, errSecParam, -25300, errSecNotAvailable])
    func removeOrphanedKeys_whenTheQueryFails_doesNotThrowAndReturnsZero(_ status: OSStatus) {
        let store = FakeKeychainItemStore(items: [Self.key()], failingQuery: status)

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 0)
        #expect(store.deletedRefs.isEmpty)
        #expect(store.items.count == 1)
    }

    @Test
    func removeOrphanedKeys_whenCalledAgain_returnsZero() {
        let store = FakeKeychainItemStore(items: [Self.key(ref: 1), Self.key(ref: 2)])

        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 2)
        #expect(Items.removeOrphanedKeys(from: store, now: Self.now) == 0)
        #expect(store.deletedRefs.count == 2)
    }

    @Test
    func removeOrphanedKeys_whenCalledFromManyThreads_removesEachItemOnce() async {
        let store = FakeKeychainItemStore(items: (0..<50).map { Self.key(ref: $0) })

        let total = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<8 {
                group.addTask { Items.removeOrphanedKeys(from: store, now: Self.now) }
            }
            return await group.reduce(0, +)
        }

        #expect(total == 50)
        #expect(store.items.isEmpty)
        #expect(store.deletedRefs.count == 50)
    }

    @Test
    func removeOrphanedKeys_whenTheStoreIsEmpty_returnsZero() {
        #expect(Items.removeOrphanedKeys(from: FakeKeychainItemStore(items: []), now: Self.now) == 0)
    }
}

/// A Keychain that lives in memory. The cleanup is tested on this and nothing else.
final class FakeKeychainItemStore: Internals.KeychainItemStore, @unchecked Sendable {

    private let lock = Lock()
    private var storage: [Internals.KeychainItem]
    private var deleted: [Data] = []
    private var attempts: [Data] = []

    private let failingDeletes: [Data: OSStatus]
    private let failingQuery: OSStatus?

    init(
        items: [Internals.KeychainItem],
        failingDeletes: [Data: OSStatus] = [:],
        failingQuery: OSStatus? = nil
    ) {
        self.storage = items
        self.failingDeletes = failingDeletes
        self.failingQuery = failingQuery
    }

    var items: [Internals.KeychainItem] {
        lock.withLock { storage }
    }

    var deletedRefs: [Data] {
        lock.withLock { deleted }
    }

    var deleteAttempts: [Data] {
        lock.withLock { attempts }
    }

    /// Like the real one, whatever the kind of the item: the cleanup does not rely on the store
    /// to leave certificates out.
    func queryKeys() throws -> [Internals.KeychainItem] {
        try lock.withLock {
            if let failingQuery {
                throw Internals.KeychainFailure(status: failingQuery)
            }
            return storage
        }
    }

    func delete(persistentRef: Data) throws {
        try lock.withLock {
            attempts.append(persistentRef)

            if let status = failingDeletes[persistentRef] {
                throw Internals.KeychainFailure(status: status)
            }

            guard let index = storage.firstIndex(where: { $0.persistentRef == persistentRef }) else {
                throw Internals.KeychainFailure(status: errSecItemNotFound)
            }

            storage.remove(at: index)
            deleted.append(persistentRef)
        }
    }
}

#endif
