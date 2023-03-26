/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

public struct Certificate: Property {

    private let source: CertificateNode.Source
    private let format: CertificateFormat

    public init<Bytes: Sequence>(
        _ bytes: Bytes,
        format: CertificateFormat = .pem
    ) where Bytes.Element == UInt8 {
        self.source = .bytes(Array(bytes))
        self.format = format
    }

    public init(_ file: String, format: CertificateFormat = .pem) {
        self.source = .file(file)
        self.format = format
    }

    public init(
        _ file: String,
        in bundle: Bundle,
        format: CertificateFormat = .pem
    ) {
        guard
            let path = bundle.resolveURL(forResourceName: {
                let pathExtension = ".\(format.pathExtension)"
                if file.hasSuffix(pathExtension) {
                    return file
                } else {
                    return "\(file)\(pathExtension)"
                }
            }())?.absolutePath()
        else { fatalError() }

        self.init(
            path,
            format: format
        )
    }

    public var body: Never {
        bodyException()
    }
}

extension Certificate: PrimitiveProperty {

    func makeObject() -> CertificateNode {
        CertificateNode(
            source: source,
            format: format
        )
    }
}
