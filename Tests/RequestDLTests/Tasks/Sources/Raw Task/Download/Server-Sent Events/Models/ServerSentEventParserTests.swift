//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct ServerSentEventParserTests {

    /// Feeds one line across many small chunks and checks both that the content comes out
    /// correct and that assembling it doesn't scale quadratically with the number of chunks.
    @available(iOS 16, tvOS 16, watchOS 9, macOS 13, *)
    @Test
    func feed_whenOneLineArrivesAcrossManySmallChunks_scalesLinearlyAndKeepsTheWholeLine() {
        // Given: the first chunk carries the "data: " field prefix; every later chunk just keeps
        // extending that same still-unterminated line, the same shape a long value streamed in
        // small pieces (the default `ReadingMode` reads 1 KiB at a time) would take.
        var parser = ServerSentEventParser()
        let chunkCount = 3000
        let chunkText = String(repeating: "a", count: 100)

        // When
        let clock = ContinuousClock()
        let start = clock.now
        #expect(parser.feed(Data("data: \(chunkText)".utf8)).isEmpty)
        for _ in 1..<chunkCount {
            #expect(parser.feed(Data(chunkText.utf8)).isEmpty)
        }
        let events = parser.feed(Data("\n\n".utf8))
        let elapsed = clock.now - start

        // Then: the whole line survived intact across all 3000 chunks...
        #expect(
            events == [
                ServerSentEvent(
                    id: nil,
                    event: "message",
                    data: String(repeating: "a", count: chunkCount * chunkText.count),
                    retry: nil
                )
            ]
        )
        // ...and assembling it cost roughly `chunkCount` units of work, not `chunkCount²`. At
        // ~300,000 bytes total this comfortably finishes in well under a second when scanning is
        // linear.
        #expect(elapsed < .seconds(2))
    }

    @Test
    func feed_whenSingleFrameSentInOneChunk_shouldEmitEvent() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("event: greeting\ndata: hello\n\n".utf8))

        // Then
        #expect(
            events == [
                ServerSentEvent(id: nil, event: "greeting", data: "hello", retry: nil)
            ]
        )
    }

    @Test
    func feed_whenLineIsSplitAcrossChunks_shouldStillEmitEvent() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let first = parser.feed(Data("data: hel".utf8))
        let second = parser.feed(Data("lo\n\n".utf8))

        // Then
        #expect(first.isEmpty)
        #expect(
            second == [
                ServerSentEvent(id: nil, event: "message", data: "hello", retry: nil)
            ]
        )
    }

    @Test
    func feed_whenCRLFTerminatorIsSplitAcrossChunks_shouldNotProduceSpuriousEmptyLine() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let first = parser.feed(Data("data: hello\r".utf8))
        let second = parser.feed(Data("\ndata: world\r\n\r\n".utf8))

        // Then
        #expect(first.isEmpty)
        #expect(
            second == [
                ServerSentEvent(id: nil, event: "message", data: "hello\nworld", retry: nil)
            ]
        )
    }

    @Test
    func feed_whenMultipleDataLines_shouldJoinWithNewline() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("data: line one\ndata: line two\n\n".utf8))

        // Then
        #expect(
            events == [
                ServerSentEvent(id: nil, event: "message", data: "line one\nline two", retry: nil)
            ]
        )
    }

    @Test
    func feed_whenLineIsComment_shouldBeIgnored() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data(": keep-alive\ndata: hello\n\n".utf8))

        // Then
        #expect(
            events == [
                ServerSentEvent(id: nil, event: "message", data: "hello", retry: nil)
            ]
        )
    }

    @Test
    func feed_whenFrameHasNoDataLine_shouldNotEmitEvent() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("event: ping\n\n".utf8))

        // Then
        #expect(events.isEmpty)
    }

    @Test
    func feed_whenIdIsSet_shouldPersistAcrossSubsequentEvents() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let first = parser.feed(Data("id: 1\ndata: hello\n\n".utf8))
        let second = parser.feed(Data("data: world\n\n".utf8))

        // Then
        #expect(
            first == [
                ServerSentEvent(id: "1", event: "message", data: "hello", retry: nil)
            ]
        )
        #expect(
            second == [
                ServerSentEvent(id: "1", event: "message", data: "world", retry: nil)
            ]
        )
    }

    @Test
    func feed_whenIdContainsNullCharacter_shouldBeIgnored() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("id: 1\u{0000}\ndata: hello\n\n".utf8))

        // Then
        #expect(
            events == [
                ServerSentEvent(id: nil, event: "message", data: "hello", retry: nil)
            ]
        )
    }

    @Test
    func feed_whenRetryIsDigitsOnly_shouldBeParsed() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("retry: 3000\ndata: hello\n\n".utf8))

        // Then
        #expect(
            events == [
                ServerSentEvent(id: nil, event: "message", data: "hello", retry: 3000)
            ]
        )
    }

    @Test
    func feed_whenRetryIsNotDigitsOnly_shouldBeIgnored() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("retry: soon\ndata: hello\n\n".utf8))

        // Then
        #expect(
            events == [
                ServerSentEvent(id: nil, event: "message", data: "hello", retry: nil)
            ]
        )
    }

    @Test
    func feed_whenFieldHasNoColon_shouldTreatItAsFieldNameWithEmptyValue() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("data\n\n".utf8))

        // Then
        #expect(
            events == [
                ServerSentEvent(id: nil, event: "message", data: "", retry: nil)
            ]
        )
    }

    @Test
    func feed_whenMultipleFramesInSingleChunk_shouldEmitEventsInOrder() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("data: first\n\ndata: second\n\n".utf8))

        // Then
        #expect(
            events == [
                ServerSentEvent(id: nil, event: "message", data: "first", retry: nil),
                ServerSentEvent(id: nil, event: "message", data: "second", retry: nil),
            ]
        )
    }

    @Test
    func finish_whenTrailingLineHasNoTerminator_shouldStillDispatch() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let fed = parser.feed(Data("data: hello\n".utf8))
        let finished = parser.finish()

        // Then
        #expect(fed.isEmpty)
        #expect(finished == ServerSentEvent(id: nil, event: "message", data: "hello", retry: nil))
    }

    @Test
    func finish_whenBufferIsEmpty_shouldReturnNil() {
        // Given
        var parser = ServerSentEventParser()

        // When
        _ = parser.feed(Data("data: hello\n\n".utf8))
        let finished = parser.finish()

        // Then
        #expect(finished == nil)
    }
}
