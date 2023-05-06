/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension String {

    func addingRFC3986PercentEncoding(
        withAllowedCharacters allowedCharacters: CharacterSet = CharacterSet()
    ) -> String {
        addingPercentEncoding(
            withAllowedCharacters: .urlQueryRFC3986Allowed.union(allowedCharacters)
        ) ?? self
    }

    func splitByUppercasedCharacters() -> [String] {
        reduce([String]()) {
            guard let last = $0.last else {
                return ["\($1)"]
            }

            let reduced = $0.dropLast()

            if let lastReducedCharacter = last.last, !lastReducedCharacter.isUppercase && $1.isUppercase {
                return reduced + [last] + ["\($1)"]
            }

            return reduced + ["\(last)\($1)"]
        }
    }
}
