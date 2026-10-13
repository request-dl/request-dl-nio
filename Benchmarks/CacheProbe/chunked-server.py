#!/usr/bin/env python3
"""A server for the measurements of the cache probe.

GET /big/<mebibytes> answers with a chunked, cacheable body of that size. There is no
Content-Length, which is what makes the cache admit the response with a size hint of zero and
rely on counting what it is actually given.

GET /count answers with how many /big requests reached the server, so a caller can tell a
response that came from the cache from one that did not.

PUT /upload reads the body, with a Content-Length or chunked, and answers with a few bytes.
"""

import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PIECE = bytes(64 * 1024)
COUNT_LOCK = threading.Lock()
COUNT = 0


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_PUT(self):
        if self.path != "/upload":
            self.send_error(404)
            return

        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            while True:
                size = int(self.rfile.readline().strip().split(b";")[0] or b"0", 16)

                if size == 0:
                    self.rfile.readline()
                    break

                self.rfile.read(size + 2)
        else:
            self.rfile.read(int(self.headers.get("Content-Length", "0")))

        body = b"ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        global COUNT
        parts = self.path.strip("/").split("/")

        if parts == ["count"]:
            body = str(COUNT).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if len(parts) != 2 or parts[0] != "big" or not parts[1].isdigit():
            self.send_error(404)
            return

        with COUNT_LOCK:
            COUNT += 1

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
