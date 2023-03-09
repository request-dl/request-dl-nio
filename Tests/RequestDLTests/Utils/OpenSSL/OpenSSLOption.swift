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
    case pfx(String)

    case der
}
#endif
