//
//  File.swift
//
//
//  Created by Brenno on 08/03/23.
//

import Foundation

#if os(macOS)
enum OpenSSLOption {

    /// String password
    case pkcs12(String)

    case der
}
#endif
