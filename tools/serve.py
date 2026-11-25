"""Serve dist/site with the headers love.js needs.

Usage: python3 tools/serve.py [directory] [port]
"""

import functools
import http.server
import socket
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".love": "application/octet-stream",
        ".js": "text/javascript",
    }

    def end_headers(self):
        # love.js uses SharedArrayBuffer, which browsers only allow on
        # cross-origin isolated pages.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else "dist/site"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8000
    handler = functools.partial(Handler, directory=directory)
    server = http.server.ThreadingHTTPServer(("0.0.0.0", port), handler)
    host = socket.gethostname()
    print(f"Serving {directory} on port {port}")
    print(f"  local:   http://localhost:{port}/")
    print(f"  exe.dev: https://{host}.exe.xyz:{port}/  (if this is an exe.dev VM)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
