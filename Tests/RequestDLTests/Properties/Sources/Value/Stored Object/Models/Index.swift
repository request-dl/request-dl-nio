//
// See LICENSE for this package's licensing information.
//

class Index: @unchecked Sendable {

    let rawValue: Int

    init(_ producer: IndexProducer) {
        rawValue = producer()
    }
}
