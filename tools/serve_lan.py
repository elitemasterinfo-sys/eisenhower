"""Serves the app on port 8080 so a phone on the same Wi-Fi can open it.

Only the app's own files are served; backups/, tools/ and everything else answer 404.
"""
import http.server
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLOWED = {
    "/", "/index.html", "/sw.js", "/manifest.json", "/qrcode.js", "/icon-192.png", "/icon-512.png",
    "/fonts/vazirmatn-arabic.woff2", "/fonts/vazirmatn-latin.woff2",
}


class AppOnlyHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, ".woff2": "font/woff2", ".js": "text/javascript"}

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def allowed(self):
        return self.path.split("?", 1)[0].split("#", 1)[0] in ALLOWED

    def do_GET(self):
        if not self.allowed():
            return self.send_error(404)
        return super().do_GET()

    def do_HEAD(self):
        if not self.allowed():
            return self.send_error(404)
        return super().do_HEAD()


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("0.0.0.0", 8080), AppOnlyHandler).serve_forever()
