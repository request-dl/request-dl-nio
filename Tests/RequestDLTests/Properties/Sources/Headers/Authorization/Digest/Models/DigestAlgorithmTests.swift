//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct DigestAlgorithmTests {

    @Test
    func rawValue_whenNilOrMD5_resolvesToMD5() {
        #expect(DigestAlgorithm(rawValue: nil) == .md5)
        #expect(DigestAlgorithm(rawValue: "MD5") == .md5)
        #expect(DigestAlgorithm(rawValue: "md5") == .md5)
    }

    @Test
    func rawValue_whenSHA256_resolvesToSHA256() {
        #expect(DigestAlgorithm(rawValue: "SHA-256") == .sha256)
        #expect(DigestAlgorithm(rawValue: "sha-256") == .sha256)
    }

    @Test
    func rawValue_whenSessionVariants_resolvesAndFlagsAsSession() {
        #expect(DigestAlgorithm(rawValue: "MD5-sess") == .md5Sess)
        #expect(DigestAlgorithm(rawValue: "SHA-256-sess") == .sha256Sess)
        #expect(DigestAlgorithm.md5Sess.isSession)
        #expect(DigestAlgorithm.sha256Sess.isSession)
        #expect(!DigestAlgorithm.md5.isSession)
        #expect(!DigestAlgorithm.sha256.isSession)
    }

    @Test
    func rawValue_whenUnknown_isNil() {
        #expect(DigestAlgorithm(rawValue: "SHA-512") == nil)
    }

    // MARK: - Known hash vectors

    @Test
    func hexDigest_md5_matchesKnownVectors() {
        #expect(DigestAlgorithm.md5.hexDigest("") == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(DigestAlgorithm.md5.hexDigest("abc") == "900150983cd24fb0d6963f7d28e17f72")
    }

    @Test
    func hexDigest_sha256_matchesKnownVectors() {
        #expect(
            DigestAlgorithm.sha256.hexDigest("")
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        #expect(
            DigestAlgorithm.sha256.hexDigest("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
