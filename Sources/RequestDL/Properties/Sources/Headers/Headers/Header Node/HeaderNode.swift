/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct HeaderNode: PropertyNode {

    // MARK: - Internal properties

    let key: String
    let value: String
    let strategy: HeaderStrategy
    let separator: String?

    var makeHeadersClosure: @Sendable (inout HTTPHeaders) -> Void {
        { self(&$0) }
    }

    // MARK: - Init

    init(
        key: String,
        value: String,
        strategy: HeaderStrategy,
        separator: String?
    ) {
        self.key = key
        self.value = value
        self.strategy = strategy
        self.separator = separator
    }

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        self(&make.request.headers)
    }

    // MARK: - Private methods

    private func callAsFunction(_ headers: inout HTTPHeaders) {
        guard !key.isEmpty else {
            return
        }

        switch strategy {
        case .adding:
            if let separator {
                let currentValue = (headers[key] ?? [])
                let inlineValue = (currentValue + [value]).joined(separator: separator)
                headers.set(name: key, value: inlineValue)
            } else {
                headers.add(name: key, value: value)
            }
        case .setting:
            headers.set(name: key, value: value)
        }
    }
}

// MARK: - CustomReflectable

extension HeaderNode: CustomReflectable {

    var customMirror: Mirror {
        Mirror(self, children: [
            (label: "key", value: key),
            (label: "value", value: value),
            (label: "strategy", value: strategy),
            (label: "separator", value: separator as Any)
        ])
    }
}
