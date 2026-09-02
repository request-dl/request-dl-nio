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

    @Test
    func feed_whenSingleFrameSentInOneChunk_shouldEmitEvent() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("event: greeting\ndata: hello\n\n".utf8))

        // Then
        #expect(events == [
            ServerSentEvent(id: nil, event: "greeting", data: "hello", retry: nil)
        ])
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
        #expect(second == [
            ServerSentEvent(id: nil, event: "message", data: "hello", retry: nil)
        ])
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
        #expect(second == [
            ServerSentEvent(id: nil, event: "message", data: "hello\nworld", retry: nil)
        ])
    }

    @Test
    func feed_whenMultipleDataLines_shouldJoinWithNewline() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("data: line one\ndata: line two\n\n".utf8))

        // Then
        #expect(events == [
            ServerSentEvent(id: nil, event: "message", data: "line one\nline two", retry: nil)
        ])
    }

    @Test
    func feed_whenLineIsComment_shouldBeIgnored() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data(": keep-alive\ndata: hello\n\n".utf8))

        // Then
        #expect(events == [
            ServerSentEvent(id: nil, event: "message", data: "hello", retry: nil)
        ])
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
        #expect(first == [
            ServerSentEvent(id: "1", event: "message", data: "hello", retry: nil)
        ])
        #expect(second == [
            ServerSentEvent(id: "1", event: "message", data: "world", retry: nil)
        ])
    }

    @Test
    func feed_whenIdContainsNullCharacter_shouldBeIgnored() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("id: 1\u{0000}\ndata: hello\n\n".utf8))

        // Then
        #expect(events == [
            ServerSentEvent(id: nil, event: "message", data: "hello", retry: nil)
        ])
    }

    @Test
    func feed_whenRetryIsDigitsOnly_shouldBeParsed() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("retry: 3000\ndata: hello\n\n".utf8))

        // Then
        #expect(events == [
            ServerSentEvent(id: nil, event: "message", data: "hello", retry: 3000)
        ])
    }

    @Test
    func feed_whenRetryIsNotDigitsOnly_shouldBeIgnored() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("retry: soon\ndata: hello\n\n".utf8))

        // Then
        #expect(events == [
            ServerSentEvent(id: nil, event: "message", data: "hello", retry: nil)
        ])
    }

    @Test
    func feed_whenFieldHasNoColon_shouldTreatItAsFieldNameWithEmptyValue()  {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("data\n\n".utf8))

        // Then
        #expect(events == [
            ServerSentEvent(id: nil, event: "message", data: "", retry: nil)
        ])
    }

    @Test
    func feed_whenMultipleFramesInSingleChunk_shouldEmitEventsInOrder() {
        // Given
        var parser = ServerSentEventParser()

        // When
        let events = parser.feed(Data("data: first\n\ndata: second\n\n".utf8))

        // Then
        #expect(events == [
            ServerSentEvent(id: nil, event: "message", data: "first", retry: nil),
            ServerSentEvent(id: nil, event: "message", data: "second", retry: nil)
        ])
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
