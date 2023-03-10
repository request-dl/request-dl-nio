//
//  File.swift
//
//
//  Created by Brenno on 08/03/23.
//

import Foundation

#if os(macOS)
struct OpenSSLBundleReference {

    let certificatePath: String

    let privateKeyPath: String

    let pkcs12Path: String?

    let certificateDEREncodedPath: String?
}
#endif
