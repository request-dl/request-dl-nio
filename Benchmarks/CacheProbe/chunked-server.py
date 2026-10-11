#!/usr/bin/env python3
"""A server that answers GET /big/<mebibytes> with a chunked, cacheable body of that size.

There is no Content-Length, which is what makes the cache admit the response with a size hint
of zero and rely on counting what it is actually given.
"""

import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PIECE = bytes(64 * 1024)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        parts = self.path.strip("/").split("/")

        if len(parts) != 2 or parts[0] != "big" or not parts[1].isdigit():
            self.send_error(404)
            return

        pieces = int(parts[1]) * 16

        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Cache-Control", "public, max-age=3600")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        for _ in range(pieces):
            self.wfile.write(b"%x\r\n" % len(PIECE) + PIECE + b"\r\n")

        self.wfile.write(b"0\r\n\r\n")

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler)
    server.serve_forever()
