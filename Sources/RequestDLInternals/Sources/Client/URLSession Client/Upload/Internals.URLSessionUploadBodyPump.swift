//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Dispatch
import Foundation
import SwiftAsyncStream

extension Internals {

    /// Hands a materialized upload body to `URLSession` through a bound stream pair RequestDL
    /// writes itself, so the upload can be paused: the `.urlSession` counterpart to
    /// `Internals.StreamWriterSequence`'s gate on the `.nio` path.
    ///
    /// ## Why a bound pair
    ///
    /// `httpBody` and an `httpBodyStream` over a file are both pulled by CFNetwork itself, as fast
    /// as the socket takes them; nothing RequestDL could do between two reads would stop the next
    /// one. `URLSessionTask.suspend()` is not an answer either: it's the OS mechanism this exists
    /// to avoid depending on (it was measured losing its suspension under load on the response
    /// side, see `Internals.URLSessionClient.executeSessionTask`), and with
    /// `bytes(for:delegate:)` there isn't even a task to call it on until the response head
    /// arrives, i.e. after the upload.
    ///
    /// A pair from `Stream.getBoundStreams` is different: CFNetwork reads the input end, and the
    /// output end only has what this type writes into it. Measured with a 24 MiB body, fixed
    /// length and chunked: CFNetwork recognizes the end of the body once the output end closes,
    /// nothing more reaches the server while this stops writing, and the body arrives
    /// byte-identical after resuming. (The end-of-body bug `Internals.URLSessionUploadFile`
    /// documents only ever affected custom `InputStream` subclasses.)
    ///
    /// ## How it writes
    ///
    /// On a serial queue of its own, driven by the output end's "can accept bytes" events
    /// (`CFWriteStreamSetDispatchQueue`): no thread is blocked on a full pair, and none is held
    /// for the length of a pause. While `gate` is shut, a pending event is simply remembered and
    /// served once the gate opens. Reading the source (a `Data`, or a file read in pieces) happens
    /// on that same queue, one piece at a time, so a large file is never loaded whole.
    ///
    /// ## Resends
    ///
    /// A 307/308 redirect, or an authentication retry, makes `URLSession` ask for the body again
    /// (`needNewBodyStream`). ``makeStream()`` answers with a fresh pair written from the start of
    /// the body, abandoning the previous one.
    ///
    /// Only used when an `Internals.TransferControl` is supplied; the paths that can't be paused
    /// are unaffected.
    final class URLSessionUploadBodyPump: @unchecked Sendable {

        // MARK: - Internal properties

        /// The exact size of the body, for `Content-Length`: without one, `URLSession` sends a
        /// stream body chunked.
        let size: Int64

        // MARK: - Private static properties

        /// The pair's own buffer, i.e. the most CFNetwork can have been handed but not yet sent
        /// when the gate shuts. Also the size of each piece read from the source.
        private static let bufferSize = 65_536

        // MARK: - Private properties

        private let source: Source
        private let gate: Internals.FlowControlWindow
        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _writer: Writer?
        private var _isStopped = false

        // MARK: - Inits

        /// - Parameter gate: Shut while the execution is suspended; see
        ///   `Internals.TransferControl.gate`.
        init(_ materialized: Internals.URLSessionUploadFile.Materialized, gate: Internals.FlowControlWindow) throws {
            switch materialized {
            case .data(let data):
                source = .data(data)
                size = Int64(data.count)

            case .file(let bufferURL):
                let url = bufferURL.absoluteURL()
                source = .file(url)
                size = try Self.fileSize(url)

            case .existingFile(let url):
                source = .file(url)
                size = try Self.fileSize(url)
            }

            self.gate = gate
        }

        // MARK: - Internal methods

        /// A new stream over the whole body, from its first byte. Any stream handed out before is
        /// abandoned: its writer stops, and CFNetwork, which asked for this one, no longer reads it.
        func makeStream() throws -> InputStream {
            var input: InputStream?
            var output: OutputStream?

            Stream.getBoundStreams(withBufferSize: Self.bufferSize, inputStream: &input, outputStream: &output)

            guard let input, let output else {
                throw URLError(.cannotCreateFile)
            }

            let writer = try Writer(output: output, source: source, gate: gate, pieceSize: Self.bufferSize)

            let (previous, isStopped) = lock.withLock { () -> (Writer?, Bool) in
                let previous = _writer
                _writer = writer
                return (previous, _isStopped)
            }

            previous?.stop()

            if isStopped {
                writer.stop()
            } else {
                writer.start()
            }

            return input
        }

        /// Stops writing for good, closing whichever stream is current. Called once the exchange
        /// is over, whichever way it ended.
        func stop() {
            let writer = lock.withLock { () -> Writer? in
                _isStopped = true
                return _writer
            }

            writer?.stop()
        }

        // MARK: - Private static methods

        private static func fileSize(_ url: URL) throws -> Int64 {
            // Checked up front, not left to the stream: see `attachUploadBody(_:to:)`, which does
            // the same for the same reason.
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

            guard let size = (attributes[.size] as? NSNumber)?.int64Value else {
                throw URLError(.cannotOpenFile, userInfo: [NSURLErrorFailingURLErrorKey: url])
            }

            return size
        }
    }
}

// MARK: - Source

extension Internals.URLSessionUploadBodyPump {

    fileprivate enum Source {
        case data(Data)
        case file(URL)
    }

    /// Reads a `Source` front to back, one piece at a time.
    fileprivate enum Reader {
        case data(Data, offset: Int)
        case file(FileHandle)

        init(_ source: Source) throws {
            switch source {
            case .data(let data):
                self = .data(data, offset: data.startIndex)
            case .file(let url):
                self = .file(try FileHandle(forReadingFrom: url))
            }
        }

        /// The next piece, empty at the end.
        mutating func read(upTo count: Int) throws -> Data {
            switch self {
            case .data(let data, let offset):
                let end = min(offset + count, data.endIndex)
                self = .data(data, offset: end)
                return data[offset..<end]

            case .file(let handle):
                return try handle.read(upToCount: count) ?? Data()
            }
        }

        func close() {
            if case .file(let handle) = self {
                try? handle.close()
            }
        }
    }
}

// MARK: - Writer

extension Internals.URLSessionUploadBodyPump {

    /// Writes one stream's worth of the body. Every piece of mutable state is touched only on
    /// `queue`, which is also where the output stream delivers its events.
    fileprivate final class Writer: @unchecked Sendable {

        // MARK: - Private properties

        private let queue = DispatchQueue(label: "com.requestdl.urlsession.upload-body-pump")
        private let output: OutputStream
        private let gate: Internals.FlowControlWindow
        private let pieceSize: Int

        // MARK: - Unsafe properties (queue only)

        private var _reader: Reader
        private var _piece = Data()
        private var _pieceOffset = 0
        private var _isWaitingForGate = false
        private var _isFinished = false

        // MARK: - Inits

        init(output: OutputStream, source: Source, gate: Internals.FlowControlWindow, pieceSize: Int) throws {
            self.output = output
            self.gate = gate
            self.pieceSize = pieceSize
            self._reader = try Reader(source)
        }

        // MARK: - Internal methods

        func start() {
            queue.async {
                self.schedule()
                self.output.open()
            }
        }

        func stop() {
            queue.async {
                self.finish()
            }
        }

        // MARK: - Private methods (queue only)

        private func schedule() {
            // CoreFoundation retains `self` for as long as it is the stream's client, through the
            // context's own retain/release callbacks, so an event already on its way can never
            // outlive the writer it is addressed to.
            var context = CFStreamClientContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: { info in
                    guard let info else { return nil }
                    _ = Unmanaged<Writer>.fromOpaque(info).retain()
                    return info
                },
                release: { info in
                    guard let info else { return }
                    Unmanaged<Writer>.fromOpaque(info).release()
                },
                copyDescription: nil
            )

            let events: CFOptionFlags =
                CFStreamEventType.canAcceptBytes.rawValue
                | CFStreamEventType.errorOccurred.rawValue
                | CFStreamEventType.endEncountered.rawValue

            CFWriteStreamSetClient(
                output,
                events,
                { _, event, info in
                    guard let info else { return }
                    Unmanaged<Writer>.fromOpaque(info).takeUnretainedValue().handle(event)
                },
                &context
            )

            CFWriteStreamSetDispatchQueue(output, queue)
        }

        private func handle(_ event: CFStreamEventType) {
            switch event {
            case .canAcceptBytes:
                write()
            case .errorOccurred, .endEncountered:
                // CFNetwork is done with this stream: the exchange failed or ended, or it asked
                // for a fresh one.
                finish()
            default:
                break
            }
        }

        private func write() {
            guard !_isFinished else {
                return
            }

            while output.hasSpaceAvailable {
                // Checked before every write, so a suspension takes effect within one piece.
                guard gate.isWritable else {
                    waitForGate()
                    return
                }

                if _pieceOffset == _piece.count {
                    do {
                        _piece = try _reader.read(upTo: pieceSize)
                        _pieceOffset = .zero
                    } catch {
                        // Closing now would read as the end of the body; with its
                        // `Content-Length` declared, a body cut short fails the request instead
                        // of being accepted as complete.
                        finish()
                        return
                    }

                    guard !_piece.isEmpty else {
                        // The whole body is in the pair: closing is what tells CFNetwork so.
                        finish()
                        return
                    }
                }

                let written = _piece.withUnsafeBytes { raw -> Int in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return .zero
                    }

                    return output.write(base + _pieceOffset, maxLength: _piece.count - _pieceOffset)
                }

                guard written > .zero else {
                    if written < .zero {
                        finish()
                    }

                    return
                }

                _pieceOffset += written
            }
        }

        /// Registers once per pause: `gate` keeps every waiter until it opens.
        private func waitForGate() {
            guard !_isWaitingForGate else {
                return
            }

            _isWaitingForGate = true

            gate.whenWritable { [weak self] in
                guard let self else {
                    return
                }

                queue.async {
                    self._isWaitingForGate = false
                    self.write()
                }
            }
        }

        private func finish() {
            guard !_isFinished else {
                return
            }

            _isFinished = true

            CFWriteStreamSetClient(output, 0, nil, nil)
            CFWriteStreamSetDispatchQueue(output, nil)
            output.close()
            _reader.close()
        }
    }
}

#endif
