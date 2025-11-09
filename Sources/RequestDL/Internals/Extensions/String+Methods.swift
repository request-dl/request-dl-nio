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

    func trimmingPrefix(in characterSet: CharacterSet) -> String {
        if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
            return String(self.trimmingPrefix(while: {
                $0.unicodeScalars.allSatisfy(characterSet.contains)
            }))
        } else {
            return String(self.drop(while: {
                $0.unicodeScalars.allSatisfy(characterSet.contains)
            }))
        }
    }
}

extension Array where Element == String {

    func joinedAsPath() -> String {
        var cleanedComponents = self.map { component in
            let trimmed = component.trimmingCharacters(in: .urlPathAllowed.inverted)
            return trimmed.trimmingCharacters(in: .init(charactersIn: "/"))
        }.filter { !$0.isEmpty }

        if let lastOriginal = self.last, lastOriginal.hasSuffix("/"), !cleanedComponents.isEmpty {
            cleanedComponents[cleanedComponents.count - 1] += "/"
        }

        return cleanedComponents.joined(separator: "/")
    }
}
