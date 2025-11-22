/*
 See LICENSE for this package's licensing information.
*/

import Testing

@testable import RequestDL

struct RequestFailureErrorTests {

    @Test
    func errorDescription() {
        let error = RequestFailureError()
        #expect(error.localizedDescription == "The request received no response.")
    }
}
