/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InternalsLogTests {

    let line: UInt = #line
    let file: StaticString = #file

    @Test
    func debug() async {
        // Given
        let message1 = "Hello World!"
        let message2 = "Earth is a small planet"

        // When
        let expecting = AsyncSignal()

        let payload = SendableBox<(String, String, [Sendable])?>(nil)

        await Internals.Override.Print.replace {
            payload(($0, $1, $2))
            expecting.signal()
        } perform: {
            Internals.Log.debug(message1, message2, line: line, file: file)

            // Then
            await expecting.wait()

            #expect(payload()?.0 == " ")
            #expect(payload()?.1 == "\n")
            #expect(payload()?.2 as? [String] == [
                debugOutput(message1, message2)
            ])
        }
    }

    @Test
    func warning() async throws {
        // Given
        let message1 = "Hello World!"
        let message2 = "Earth is a small planet"

        // When
        let expecting = AsyncSignal()

        let payload = SendableBox<(String, String, [Sendable])?>(nil)
        await Internals.Override.Print.replace {
            payload(($0, $1, $2))
            expecting.signal()
        } perform: {
            Internals.Log.warning(message1, message2, line: line, file: file)

            // Then
            await expecting.wait()

            #expect(payload()?.0 == " ")
            #expect(payload()?.1 == "\n")
            #expect(payload()?.2 as? [String] == [
                warningOutput(message1, message2)
            ])
        }
    }

    @Test
    func failure() async throws {
        // Given
        let message1 = "Hello World!"
        let message2 = "Earth is a small planet"

        // When
        let payload = SendableBox<(String, StaticString, UInt)?>(nil)
        let expectation = AsyncSignal()

        Thread {
            Internals.Override.FatalError.replace {
                payload(($0, $1, $2))
                expectation.signal()
                Thread.exit()
                return Swift.fatalError()
            } perform: {
                _ = Internals.Log.failure(message1, message2, line: line, file: file)
            }
        }.start()

        await expectation.wait()

        #expect(payload()?.0 == failureOutput(message1, message2))
        #expect((payload()?.1).map { "\($0)" } == "\(file)")
        #expect(payload()?.2 == line)
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
