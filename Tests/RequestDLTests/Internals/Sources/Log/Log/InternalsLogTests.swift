/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InternalsLogTests: XCTestCase {

    let line: UInt = #line
    let file: StaticString = #file

    func testDebug() async {
        // Given
        let message1 = "Hello World!"
        let message2 = "Earth is a small planet"

        // When
        let expecting = expectation(description: "print")

        let payload = SendableBox<(String, String, [Sendable])?>(nil)
        
        Internals.Override.Print.replace {
            payload(($0, $1, $2))
            expecting.fulfill()
        }

        Internals.Log.debug(message1, message2, line: line, file: file)

        // Then
        await _fulfillment(of: [expecting])

        XCTAssertEqual(payload()?.0, " ")
        XCTAssertEqual(payload()?.1, "\n")
        XCTAssertEqual(payload()?.2 as? [String], [
            debugOutput(message1, message2)
        ])
    }

    func testWarning() async throws {
        // Given
        let message1 = "Hello World!"
        let message2 = "Earth is a small planet"

        // When
        let expecting = expectation(description: "print")

        let payload = SendableBox<(String, String, [Sendable])?>(nil)
        Internals.Override.Print.replace {
            payload(($0, $1, $2))
            expecting.fulfill()
        }

        defer { Internals.Override.Print.restore() }

        Internals.Log.warning(message1, message2, line: line, file: file)

        // Then
        await _fulfillment(of: [expecting])

        XCTAssertEqual(payload()?.0, " ")
        XCTAssertEqual(payload()?.1, "\n")
        XCTAssertEqual(payload()?.2 as? [String], [
            warningOutput(message1, message2)
        ])
    }

    func testFailure() async throws {
        // Given
        let message1 = "Hello World!"
        let message2 = "Earth is a small planet"

        // When
        let expecting = expectation(description: "print")

        let payload = SendableBox<(String, StaticString, UInt)?>(nil)
        Internals.Override.FatalError.replace {
            payload(($0, $1, $2))
            expecting.fulfill()
            Thread.exit()
            return Swift.fatalError()
        }

        defer { Internals.Override.FatalError.restore() }

        Thread.detachNewThread { [line, file] in
            Internals.Log.failure(message1, message2, line: line, file: file)
        }

        // Then
        await _fulfillment(of: [expecting])

        XCTAssertEqual(payload()?.0, failureOutput(message1, message2))
        XCTAssertEqual((payload()?.1).map { "\($0)" }, "\(file)")
        XCTAssertEqual(payload()?.2, line)
    }
}

extension InternalsLogTests {

    func debugOutput(_ contents: String...) -> String {
        """
        RequestDL.Log 💙 DEBUG

        \(contents.joined(separator: " "))

        -> \(file):\(line)
        """
    }

    func warningOutput(_ contents: String...) -> String {
        """
        RequestDL.Log ⚠️ WARNING

        \(contents.joined(separator: " "))

        -> \(file):\(line)
        """
    }

    func failureOutput(_ contents: String...) -> String {
        """
        RequestDL.Log 💔 FAILURE

        \(contents.joined(separator: " "))

        -> \(file):\(line)
        """
    }
}
