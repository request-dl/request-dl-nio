/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct FormNode: PropertyNode {

    // MARK: - Internal properties

    let fragmentLength: Int?
    let items: [FormItem]

    // MARK: - Inits

    init(
        fragmentLength: Int?,
        item: FormItem
    ) {
        self.init(
            fragmentLength: fragmentLength,
            items: [item]
        )
    }

    init(
        fragmentLength: Int?,
        items: [FormItem]
    ) {
        self.fragmentLength = fragmentLength
        self.items = items
    }

    // MARK: - Internal methods

    func make(_ make: inout Make) async throws {
        let constructor = FormGroupBuilder(items)

        make.request.headers.set(
            name: "Content-Type",
            value: "multipart/form-data; boundary=\"\(constructor.boundary)\""
        )

        let buffers = constructor()

        make.request.headers.setContentLengthIfNeeded(
            buffers.lazy
                .map(\.estimatedBytes)
                .reduce(.zero, +)
        )

        make.request.body = Internals.Body(
            fragmentLength,
            buffers: buffers
        )
    }
}

extension HTTPHeaders {

    mutating func setContentLengthIfNeeded(_ length: Int) {
        let contains = contains(name: "Content-Length") {
            $0.split(separator: ";")
                .lazy
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains { Int($0) != nil }
        }

        guard !contains else {
            return
        }

        if length > .zero {
            add(name: "Content-Length", value: String(length))
        }
    }
}
