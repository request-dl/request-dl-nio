# See LICENSE for this package's licensing information.
#
# The server `memory-probe` talks to, in a process of its own so that what is measured is the client:
#
#   GET  /download?bytes=N   answers with N zero bytes, in chunks of 64 KiB.
#   POST /upload (or PUT)    reads the whole body, chunked or not, and answers with how many bytes it was.
#   GET  /redirect           answers 302 to /small.
#   GET  /small              answers with a few bytes.
#
#     python3 server.py <port>

import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

CHUNK = b"\x00" * 65536

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _body(self, text, code=200, extra=()):
        data = text.encode()
        self.send_response(code)
        for k, v in extra:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/download":
            n = int(parse_qs(u.query)["bytes"][0])
            self.send_response(200)
            self.send_header("Content-Length", str(n))
            self.end_headers()
            while n > 0:
                piece = CHUNK if n >= len(CHUNK) else CHUNK[:n]
                self.wfile.write(piece)
                n -= len(piece)
        elif u.path == "/redirect":
            self._body("", 302, [("Location", "/small")])
        else:
            self._body("ok")

    def _read_body(self):
        total = 0
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            while True:
                size = int(self.rfile.readline().strip().split(b";")[0] or b"0", 16)
                if size == 0:
                    self.rfile.readline()
                    break
                left = size
                while left:
                    b = self.rfile.read(min(left, 65536))
                    if not b:
                        return total
                    left -= len(b)
                    total += len(b)
                self.rfile.readline()
        else:
            left = int(self.headers.get("Content-Length", 0))
            while left:
                b = self.rfile.read(min(left, 65536))
                if not b:
                    break
                left -= len(b)
                total += len(b)
        return total

    def do_POST(self):
        self._body("received=%d" % self._read_body())

    do_PUT = do_POST

ThreadingHTTPServer.request_queue_size = 256
ThreadingHTTPServer.daemon_threads = True
ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
