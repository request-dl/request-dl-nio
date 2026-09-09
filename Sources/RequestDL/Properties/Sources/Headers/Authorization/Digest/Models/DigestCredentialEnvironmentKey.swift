//
// See LICENSE for this package's licensing information.
//

private struct DigestCredentialEnvironmentKey: RequestEnvironmentKey {
    static let defaultValue = DigestCredential()
}

extension RequestEnvironmentValues {

    var digestCredential: DigestCredential {
        get { self[DigestCredentialEnvironmentKey.self] }
        set { self[DigestCredentialEnvironmentKey.self] = newValue }
    }
}
