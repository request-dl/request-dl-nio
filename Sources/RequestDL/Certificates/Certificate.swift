import Foundation

public struct Certificate {

    let type: ValidationType
    let hash: String

    public init(
        _ type: ValidationType,
        hash: String
    ) {
        self.hash = hash
        self.type = type
    }

    public init(_ hash: String) {
        self.init(.byPublicKey, hash: hash)
    }
}

extension Certificate {

    public enum ValidationType {
        case byPublicKey
        case byPrivateKey
    }
}
