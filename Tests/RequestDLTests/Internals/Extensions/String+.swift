/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension String {

    static func randomString(length: Int) -> String {
        let lowercaseCharacters = "abcdefghijklmnopqrstuvwxyz"
        let uppercaseCharacters = lowercaseCharacters.uppercased()
        let decimalCharacters = "0123456789"

        let characters = [
            lowercaseCharacters,
            uppercaseCharacters,
            decimalCharacters
        ].joined()

        var string = ""

        for _ in 0 ..< length {
            string += String(characters.randomElement()!)
        }

        return string
    }
}
