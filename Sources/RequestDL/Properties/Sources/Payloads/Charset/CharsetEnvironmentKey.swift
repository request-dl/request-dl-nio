/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct CharsetEnvironmentKey: RequestEnvironmentKey {

    static var defaultValue: Charset {
        .utf8
    }
}

extension RequestEnvironmentValues {

    var charset: Charset {
        get { self[CharsetEnvironmentKey.self] }
        set { self[CharsetEnvironmentKey.self] = newValue }
    }
}

extension Property {

    /**
     Specifies the character set (charset) to be used for encoding data.

     - Parameter charset: The character set to use for encoding.
     - Returns: A modified property with the specified charset.
     */
    public func charset(_ charset: Charset) -> some Property {
        environment(\.charset, charset)
    }
}
