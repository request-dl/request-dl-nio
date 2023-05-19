/*
 See LICENSE for this package's licensing information.
*/

import Foundation

private struct CharsetEnvironmentKey: EnvironmentKey {

    static var defaultValue: Charset = .utf8
}

extension EnvironmentValues {

    var charset: Charset {
        get { self[CharsetEnvironmentKey.self] }
        set { self[CharsetEnvironmentKey.self] = newValue }
    }
}

extension Property {

    public func charset(_ charset: Charset) -> some Property {
        environment(\.charset, charset)
    }
}
