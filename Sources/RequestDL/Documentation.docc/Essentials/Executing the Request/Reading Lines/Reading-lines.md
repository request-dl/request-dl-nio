# Reading a response by line or by separator

Turn the bytes of a download into lines, records or events as they arrive, without letting a source that never ends fill memory.

## Overview

``RequestDL/DownloadTask`` hands you ``RequestDL/AsyncBytes``, the body in the chunks the client received. Text protocols such as NDJSON, logs and `text/event-stream` are not made of chunks but of lines. Three methods on ``RequestDL/AsyncBytes`` cut the stream for you.

```swift
let result = try await DownloadTask {
    BaseURL("example.com")
    Path("stream.ndjson")
}
.result()

for try await line in result.payload.lines() {
    let record = try JSONDecoder().decode(Record.self, from: Data(line.utf8))
    print(record)
}
```

- ``RequestDL/AsyncBytes/lines(maximumLength:)`` yields one `String` per line. A line ends at `LF`, `CRLF` or a lone `CR`, including when the two bytes of a `CRLF` arrive in different chunks.
- ``RequestDL/AsyncBytes/items(separatedBy:maximumLength:)-([UInt8],_)`` yields one `Data` per item between any non-empty separator, such as `0x1E` (record separator) or `"\n\n"`. The separator may arrive split across chunks.
- ``RequestDL/AsyncBytes/events(maximumLineLength:)`` parses `text/event-stream` into ``RequestDL/ServerSentEvent`` values, with the same limit on a line.

The cutting happens as you ask for the next element, so a slow consumer slows the download down through the usual back pressure. Only the item being read is kept in memory.

### What an item is

The delimiter is not part of the item. An empty line is delivered as an empty string, so the lines of `"a\n\nb"` are `a`, an empty line and `b`, unlike some line APIs that drop empty lines. A last item with nothing after it is delivered when the stream ends, and a delimiter at the very end does not add an empty item. `lines()` decodes UTF-8 and turns an invalid sequence into U+FFFD.

### Bounding memory

A server that never sends a line break would keep the line growing for as long as the connection lasts. Every method stops that:

```swift
do {
    for try await line in result.payload.lines(maximumLength: 64 * 1_024) {
        handle(line)
    }
} catch let error as AsyncBytesItemTooLargeError {
    print("A line passed \(error.maximumLength) bytes")
}
```

``RequestDL/AsyncBytesItemTooLargeError`` is thrown as soon as an item grows past `maximumLength` without ending, counted in bytes and without its delimiter. Items that ended before it have already been delivered, the sequence ends there, and **the transfer is cancelled** instead of running on for as long as you hold the bytes.

`lines(maximumLength:)` and `items(separatedBy:maximumLength:)` default to 1 MiB, which is generous for text protocols; lower it when you know your data. ``RequestDL/AsyncBytes/events()`` has no limit, to keep what it always did. Use ``RequestDL/AsyncBytes/events(maximumLineLength:)`` when the source is not trusted. The limit is per line, so it bounds a `data:` field but not an event made of very many short lines.

### Moving off ReadingMode separators

``RequestDL/ReadingMode``'s `init(separator:)` and `init(separator:maximumItemSize:)` are deprecated. They cut the stream inside the download, where the bytes are counted as consumed the moment they enter the accumulator, so back pressure cannot see what piles up. Reading the delivered stream, as above, can.

```swift
// Before
let result = try await DownloadTask {
    BaseURL("example.com")
    ReadingMode(separator: "\n", maximumItemSize: 65_536)
}
.result()

for try await item in result.payload {
    // each item still carried its separator at the end
}

// After
let result = try await DownloadTask {
    BaseURL("example.com")
}
.result()

for try await line in result.payload.lines(maximumLength: 65_535) {
    // the line, without its line break
}
```

Four differences to account for: `lines()` also ends a line at `CR` and `CRLF` (use `items(separatedBy: "\n")` for exactly the old cut), the new methods do not include the delimiter in the items, `maximumItemSize` counted it while `maximumLength` does not, and the old error was ``RequestDL/ReadingModeItemTooLargeError`` where the new one is ``RequestDL/AsyncBytesItemTooLargeError``. ``RequestDL/ReadingMode`` with `init(length:)` stays: it sets the size of the chunks the client reads.

## Topics

### Reading by line or separator

- ``RequestDL/AsyncBytes/lines(maximumLength:)``
- ``RequestDL/AsyncBytes/items(separatedBy:maximumLength:)-([UInt8],_)``
- ``RequestDL/AsyncBytesLines``
- ``RequestDL/AsyncBytesItems``

### Server-Sent Events

- ``RequestDL/AsyncBytes/events()``
- ``RequestDL/AsyncBytes/events(maximumLineLength:)``
- ``RequestDL/ServerSentEvents``
- ``RequestDL/ServerSentEvent``

### Errors

- ``RequestDL/AsyncBytesItemTooLargeError``
- ``RequestDL/ReadingModeItemTooLargeError``
